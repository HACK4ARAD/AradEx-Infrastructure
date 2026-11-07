# AradExperience pe AWS (Terraform): plan de implementare

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AradExperience (API Spring Boot + PWA Vue + Postgres) rulează pe AWS `eu-north-1`, pe `https://<domeniu>`, cu deploy automat la merge pe `main` și testele BE în pipeline. Toată infrastructura e scrisă în Terraform.

**Architecture:** Un root Terraform în `AradEx-Infrastructure/terraform/` cu 6 module locale: `network`, `data`, `api`, `edge`, `pipelines` și `monitoring`. CloudFront servește `/` din S3 și trimite `/api/*` printr-un VPC origin spre un ALB intern, în fața unui Fargate ARM. Baza de date e RDS Postgres 16 izolată. Două CodePipeline V2 pornesc la push pe `main`. State-ul stă în S3 cu lock nativ.

**Tech Stack:** Terraform 1.17.1 · `hashicorp/aws` `~> 6.72` · `hashicorp/random` `~> 3.9` · `terraform test` cu `mock_provider` · Node 26 (`node --test`, fără dependențe) doar pentru testul CloudFront Function-ului.

**Spec:** `docs/superpowers/specs/2026-11-07-aws-infrastructure-design.md` (revizia 2, Terraform).

## Global Constraints

- Cont `712710404828`, regiune `eu-north-1`, certificatul în `us-east-1` (provider alias `aws.us_east_1`). Profilul CLI `aws-toolkit` (`export AWS_PROFILE=aws-toolkit`). **Fără `profile` în cod.**
- Tot codul stă în `AradEx-Infrastructure`, branch `feat/T04-aws-infra`. **Nicio modificare în `AradEx-Backend` sau `AradEx-Frontend`.** `AradEx-Plan` se schimbă doar în Task 12.
- Commit-uri scurte în engleză, **fără `Co-Authored-By:`** și fără „Generated with Claude Code”. Fără push sau PR până nu cere Zoltan.
- **Fără secrete în git.** `alert_email` stă în `terraform/local.auto.tfvars` (ignorat de git).
- **Orice `apply` sau `destroy` pe contul real se face doar după ce Zoltan vede `plan`-ul și spune „da”** (Task-urile 9–11).
- **Nume fixe:**
  - ECR `aradex-api`; cluster `aradex`; serviciul `aradex-api`; containerul `api`, port `8080`;
  - log group `/aradex/api`; baza de date `aradexperience`, user `arad`;
  - secretele `aradex/jwt` și `aradex/openai`; snapshot-ul final `aradex-final`;
  - topic SNS `aradex-alerts`; pipeline-urile `aradex-backend` și `aradex-frontend`; conexiunea `aradex-github`;
  - bucket-ul de state `aradex-tfstate-712710404828`.
- Health check `/api/v1/health`; grace period 180 s; task 512 / 1024, ARM64.
- `VITE_API_URL=https://<domeniu>/api/v1`; `CORS_ORIGINS=https://<domeniu>` (fără domeniu: `http://localhost:5173`); `OPENAI_MODEL=gpt-4o-mini`; `SPRING_PROFILES_ACTIVE=prod`; `POSTGRES_URL=jdbc:postgresql://<endpoint>:5432/aradexperience?sslmode=require`.
- **Convenții de cod:**
  - modulele primesc **ID-uri, ARN-uri și string-uri**, nu obiecte;
  - politicile IAM se scriu cu `jsonencode()`, nu cu `data "aws_iam_policy_document"`, ca să fie deterministe sub mock;
  - fără data sources care cer cont (ID-urile politicilor gestionate CloudFront și prefix list-ul sunt constante).
- **Comenzi** (din `AradEx-Infrastructure/`):
  - `terraform -chdir=terraform init -backend=false`;
  - `terraform -chdir=terraform test` (toate testele) sau `-filter=tests/<x>.tftest.hcl`;
  - `terraform fmt -check -recursive terraform`;
  - `terraform -chdir=terraform validate`.
- **Testele** folosesc `mock_provider "aws"` (+ `alias = "us_east_1"`) și `command = apply` (mock-ul generează valorile calculate). Nu cer credențiale și nu creează nimic.

## Review Focus

1. **Reload pe un link adânc al SPA-ului** întoarce `index.html`, dar **un 404 sau 403 al API-ului rămâne JSON**. Prin urmare *fără* `custom_error_response` pe distribuție; rescrierea o face CloudFront Function-ul, doar pe comportamentul default. Testat în Task 5.
2. **Cereri autentificate și POST spre API prin CloudFront:** `Authorization`, query string-ul și body-ul ajung la Spring, cu toate cele 7 metode HTTP. Testat în Task 5.
3. **PWA-ul vechi rămâne în cache** dacă `index.html` sau `sw.js` primesc cache lung. Testat în Task 6.
4. **Spring Boot + Flyway pornește încet**, deci grace period-ul de 180 s e obligatoriu. Testat în Task 4.
5. **JDBC fără `sslmode=require`** e refuzat de RDS (`rds.force_ssl=1`). Testat în Task 4.

---

## File structure (`AradEx-Infrastructure/`)

```
terraform/
  versions.tf      terraform + provider-e (versiuni)       backend.tf   backend "s3" (use_lockfile)
  providers.tf     aws (eu-north-1) + aws.us_east_1, default_tags
  variables.tf     domain_name, alert_email, api_desired_count, github_owner, backend_repo, frontend_repo, branch (+ validări)
  main.tf          apelurile de module (edge + pipelines condiționate de domain_name)
  outputs.tf       name_servers, site_url, distribution_id, bucket_name, connection_arn, ecr_url, cluster/service
  terraform.tfvars valori nesecrete         .terraform.lock.hcl (în git)
  bootstrap/main.tf  bucket-ul de state (state local, rulat o dată)
  modules/network/   main.tf variables.tf outputs.tf
  modules/data/      main.tf variables.tf outputs.tf
  modules/api/       main.tf iam.tf variables.tf outputs.tf
  modules/edge/      main.tf variables.tf outputs.tf versions.tf (configuration_aliases)  functions/spa-rewrite.js  functions/spa-rewrite.test.mjs
  modules/pipelines/ main.tf iam.tf variables.tf outputs.tf  buildspecs/api-test.yml api-build.yml web.yml
  modules/monitoring/ main.tf variables.tf outputs.tf
  tests/  root.tftest.hcl network.tftest.hcl data.tftest.hcl api.tftest.hcl edge.tftest.hcl pipelines.tftest.hcl monitoring.tftest.hcl
scripts/ set-openai-key.sh · redeploy.sh · destroy.sh
README.md (rescris) · .gitignore (+ .terraform/, *.tfstate*, *.tfplan, local.auto.tfvars)
```

---

### Task 1: Root-ul, variabilele, backend-ul, bootstrap

**Files:**
- Create: `terraform/{versions,backend,providers,variables,main,outputs}.tf`, `terraform/terraform.tfvars`, `terraform/bootstrap/main.tf`, `terraform/tests/root.tftest.hcl`
- Modify: `.gitignore`
- Add to git: spec-ul și planul

**Interfaces:**
- Produces: variabilele root
  - `domain_name` (string, implicit `""`);
  - `alert_email` (string, obligatorie);
  - `api_desired_count` (number, implicit 0, doar 0 sau 1);
  - `github_owner` (`"HACK4ARAD"`), `backend_repo` (`"AradEx-Backend"`), `frontend_repo` (`"AradEx-Frontend"`), `branch` (`"main"`);
  - `local.has_domain = var.domain_name != ""`.

- [ ] **Step 1:** `.gitignore` primește `.terraform/`, `*.tfstate`, `*.tfstate.*`, `*.tfplan`, `terraform/local.auto.tfvars`, `.superpowers/`. Creează `versions.tf` (`required_version = ">= 1.17"`, aws `~> 6.72`, random `~> 3.9`) și `backend.tf` (`bucket`, `key = "aradex/terraform.tfstate"`, `region = "eu-north-1"`, `encrypt = true`, `use_lockfile = true`). `providers.tf`: `aws` + `aws` cu `alias = "us_east_1"`, ambele cu `default_tags { tags = { Project = "AradExperience" } }`.
- [ ] **Step 2: Testele care pică**, în `tests/root.tftest.hcl` (`command = plan`, mock-uri pentru ambii provideri):
  - `invalid_email` → `variables { alert_email = "nu-email" }`, `expect_failures = [var.alert_email]`;
  - `invalid_domain` → `domain_name = "nu un domeniu"`, `expect_failures = [var.domain_name]`;
  - `invalid_count` → `api_desired_count = 3`, `expect_failures = [var.api_desired_count]`;
  - `defaults_ok` → doar `alert_email = "a@b.ro"`; `assert { condition = var.github_owner == "HACK4ARAD" && var.branch == "main" && var.api_desired_count == 0 }`.
- [ ] **Step 3:** `terraform -chdir=terraform init -backend=false && terraform -chdir=terraform test` → FAIL (variabilele nu există).
- [ ] **Step 4:** Scrie `variables.tf` cu `validation`:
  - email `can(regex("^[^@\\s]+@[^@\\s]+$", ...))`;
  - domeniu `"" sau ^[a-z0-9-]+(\\.[a-z0-9-]+)+$`;
  - count `contains([0, 1], ...)`.

  `main.tf` deocamdată doar `locals { has_domain = var.domain_name != "" }`. `terraform.tfvars`: `api_desired_count = 0`.
- [ ] **Step 5:** `terraform -chdir=terraform test` → 4 passed. `terraform fmt -check -recursive terraform` → nimic.
- [ ] **Step 6:** `terraform/bootstrap/main.tf`, cu state local:
  - `aws_s3_bucket` `aradex-tfstate-712710404828`;
  - versioning `Enabled`;
  - SSE `AES256`;
  - public access block complet.

  `terraform -chdir=terraform/bootstrap init && terraform -chdir=terraform/bootstrap validate` → valid.
- [ ] **Step 7:** Commit `chore(terraform): root, variables, backend, bootstrap` (include spec, plan și `.terraform.lock.hcl`).

### Task 2: Modulul `network`

**Files:** `terraform/modules/network/*`, `terraform/tests/network.tftest.hcl`, `terraform/main.tf`.

**Interfaces:**
- Produces outputs: `vpc_id`, `public_subnet_ids` (list, 2), `isolated_subnet_ids` (list, 2), `alb_sg_id`, `task_sg_id`, `db_sg_id`.

- [ ] **Step 1: Testele care pică** (`run` cu `module { source = "./modules/network" }`):
  - `vpc_cidr` → `aws_vpc.this.cidr_block == "10.40.0.0/16"`, DNS hostnames și DNS support pornite;
  - `subnets` → 2 publice (`map_public_ip_on_launch = true`) în `eu-north-1a` / `eu-north-1b` și 2 izolate;
  - `no_nat` → route table-ul izolat nu are rute (`length(aws_route_table.isolated.route) == 0`); modulul nu declară `aws_nat_gateway`, verificat la review;
  - `public_default_route` → `aws_route.public_internet.destination_cidr_block == "0.0.0.0/0"` spre IGW;
  - `alb_ingress` → `aws_vpc_security_group_ingress_rule.alb_from_cloudfront`: `prefix_list_id == "pl-fab65393"`, `from_port == 80`;
  - `task_ingress` → `referenced_security_group_id == aws_security_group.alb.id`, port 8080;
  - `db_ingress` → `referenced_security_group_id == aws_security_group.task.id`, port 5432;
  - `no_open_ingress` → nicio regulă de intrare cu `cidr_ipv4 == "0.0.0.0/0"`.
- [ ] **Step 2:** `terraform -chdir=terraform test -filter=tests/network.tftest.hcl` → FAIL.
- [ ] **Step 3:** Implementează:
  - `aws_vpc`, `aws_internet_gateway`, 2 × `aws_subnet` publice + 2 izolate (`/24`, AZ-urile fixe `eu-north-1a/b`);
  - route table public cu ruta spre IGW și route table izolat fără rute;
  - 3 × `aws_security_group`, cu reguli separate `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` (egress `0.0.0.0/0` pe toate).

  Apelează modulul din root `main.tf`.
- [ ] **Step 4:** Testele trec. Commit `feat(terraform): network module`.

### Task 3: Modulul `data`

**Files:** `terraform/modules/data/*`, `terraform/tests/data.tftest.hcl`, `terraform/main.tf`.

**Interfaces:**
- Consumes: `isolated_subnet_ids`, `db_sg_id`.
- Produces outputs: `db_endpoint` (adresa, fără port), `db_secret_arn` (secretul gestionat de RDS), `jwt_secret_arn`, `openai_secret_arn`, `db_instance_id`.

- [ ] **Step 1: Testele care pică:**
  - `postgres` → `aws_db_instance.this`:
    - `engine == "postgres"`, `startswith(engine_version, "16")`, `instance_class == "db.t4g.micro"`;
    - `allocated_storage == 20`, `storage_type == "gp3"`, `storage_encrypted`;
    - `!multi_az`, `!publicly_accessible`, `backup_retention_period == 1`, `!deletion_protection`;
    - `db_name == "aradexperience"`, `username == "arad"`, `manage_master_user_password`;
  - `final_snapshot` → `!skip_final_snapshot && final_snapshot_identifier == "aradex-final"`;
  - `force_ssl` → `aws_db_parameter_group.this`, family `postgres16`, parametrul `rds.force_ssl = "1"`;
  - `isolated` → `aws_db_subnet_group.this.subnet_ids == toset(var.isolated_subnet_ids)`;
  - `jwt` → `random_password.jwt`: `length == 64`, `special == false`; `aws_secretsmanager_secret.jwt.name == "aradex/jwt"`;
  - `openai_placeholder` → `aws_secretsmanager_secret.openai.name == "aradex/openai"`, `aws_secretsmanager_secret_version.openai.secret_string == "REPLACE_ME"`.
- [ ] **Step 2:** Rulează → FAIL.
- [ ] **Step 3:** Implementează:
  - `engine_version = "16"` (RDS alege ultima versiune minoră);
  - `apply_immediately = true`;
  - versiunea secretului `openai` cu `lifecycle { ignore_changes = [secret_string] }`;
  - `recovery_window_in_days = 0` pe ambele secrete (ștergere imediată luni).
- [ ] **Step 4:** Testele trec. Commit `feat(terraform): data module`.

### Task 4: Modulul `api`

**Files:** `terraform/modules/api/*`, `terraform/tests/api.tftest.hcl`, `terraform/main.tf`.

**Interfaces:**
- Consumes: `vpc_id`, `public_subnet_ids`, `isolated_subnet_ids`, `alb_sg_id`, `task_sg_id`; `db_endpoint`, `db_secret_arn`, `jwt_secret_arn`, `openai_secret_arn`; `domain_name`, `desired_count`.
- Produces outputs: `ecr_repository_url`, `ecr_repository_arn`, `cluster_name`, `service_name`, `alb_arn`, `alb_dns_name`, `alb_arn_suffix`, `target_group_arn_suffix`, `task_execution_role_arn`, `task_role_arn`.

- [ ] **Step 1: Testele care pică** (variabile de test: `db_endpoint = "db.example.internal"`, `domain_name = "aradex.example"`):
  - `ecr` → `name == "aradex-api"`, `force_delete`; lifecycle-ul conține `"countNumber":10`;
  - `task` → `cpu == "512"`, `memory == "1024"`, `runtime_platform[0].cpu_architecture == "ARM64"`, `requires_compatibilities == toset(["FARGATE"])`;
  - `container_env` → `local.container` (decodat din `container_definitions`):
    - numele `api`, port 8080;
    - env-ul `SPRING_PROFILES_ACTIVE=prod`, `OPENAI_MODEL=gpt-4o-mini`, `CORS_ORIGINS=https://aradex.example`;
    - `POSTGRES_URL == "jdbc:postgresql://db.example.internal:5432/aradexperience?sslmode=require"` (**Review Focus 5**);
  - `container_secrets` → numele sortate `JWT_SECRET, OPENAI_API_KEY, POSTGRES_PASSWORD, POSTGRES_USER`; `POSTGRES_USER.valueFrom` se termină în `:username::`;
  - `cors_fallback` → `domain_name = ""` dă `CORS_ORIGINS=http://localhost:5173`;
  - `service` → `aws_ecs_service.api`:
    - `name == "aradex-api"`, `desired_count == 0`, `launch_type == "FARGATE"`, `enable_execute_command`;
    - `health_check_grace_period_seconds == 180` (**Review Focus 4**);
    - `deployment_minimum_healthy_percent == 100`, `deployment_maximum_percent == 200`;
    - `deployment_circuit_breaker[0].enable && .rollback`;
    - `network_configuration[0].assign_public_ip`;
  - `desired_one` → `desired_count = 1` dă `desired_count == 1`;
  - `alb_internal` → `aws_lb.api.internal`, subneturile izolate; listener-ul pe portul 80 HTTP, care trimite spre target group;
  - `tg_health` → `port == 8080`, `target_type == "ip"`, health check `/api/v1/health`, interval 15, healthy 2, unhealthy 3, `deregistration_delay == "10"`;
  - `logs` → `/aradex/api`, retenție 7;
  - `iam` → politica rolului de execuție permite `secretsmanager:GetSecretValue` doar pe cele 3 ARN-uri primite; rolul taskului are acțiunile `ssmmessages:*Channel` (ECS Exec).
- [ ] **Step 2:** Rulează → FAIL.
- [ ] **Step 3:** Implementează:
  - `container_definitions = jsonencode([...])`, cu imaginea `${repo_url}:latest` și logurile prin `awslogs`;
  - secretele: `"${db_secret_arn}:username::"`, `"${db_secret_arn}:password::"`, `jwt_secret_arn`, `openai_secret_arn`;
  - rolul de execuție: `AmazonECSTaskExecutionRolePolicy` (managed) + politică inline pentru secrete;
  - serviciul: `load_balancer { container_name = "api", container_port = 8080 }`, `depends_on` pe listener.
- [ ] **Step 4:** Testele trec; `terraform validate` e OK. Commit `feat(terraform): api module`.

### Task 5: Modulul `edge` (domeniu, certificat, S3, CloudFront)

**Files:** `terraform/modules/edge/*`, inclusiv `functions/spa-rewrite.js` și `functions/spa-rewrite.test.mjs`; `terraform/tests/edge.tftest.hcl`; `terraform/main.tf`, `terraform/outputs.tf`.

**Interfaces:**
- Consumes: `domain_name`, `alb_arn`, `alb_dns_name`; providerii `aws` și `aws.us_east_1` (`configuration_aliases`).
- Produces outputs: `name_servers`, `bucket_name`, `bucket_arn`, `distribution_id`, `distribution_arn`, `site_url`.
- În root: `module "edge" { count = local.has_domain ? 1 : 0 }`; output-urile root sunt `one(module.edge[*].x)`.

- [ ] **Step 1: Testul care pică pentru funcție** (`node:test` + `node:assert`; încarcă fișierul cu `fs` și `new Function(src + "\nreturn handler;")`):
  - `/m/events/42` → uri `/index.html`;
  - `/w` → `/index.html`;
  - `/` → `/index.html`;
  - `/assets/index-abc.js` și `/sw.js` → neschimbate;
  - host `www.aradex.example`, uri `/m` → `statusCode 301`, `headers.location.value == "https://aradex.example/m"`.
- [ ] **Step 2:** `node --test terraform/modules/edge/functions/` → FAIL (fișierul lipsește).
- [ ] **Step 3:** Scrie `spa-rewrite.js` (`cloudfront-js-2.0`):
  - host `www.*` → 301 spre host-ul fără `www.`, cu același uri;
  - altfel, dacă ultimul segment nu conține `.`, setează uri `/index.html`.

  Rulează `node --test` → PASS.
- [ ] **Step 4: Testele care pică** (`edge.tftest.hcl`, `domain_name = "aradex.example"`):
  - `cert` → `aws_acm_certificate.this`: `domain_name == "aradex.example"`, `subject_alternative_names == toset(["www.aradex.example"])`, `validation_method == "DNS"`;
  - `zone` → `aws_route53_zone.this.name == "aradex.example"`;
  - `bucket_private` → public access block complet `true`; `aws_cloudfront_origin_access_control.s3.signing_behavior == "always"`; policy-ul bucket-ului permite `s3:GetObject` doar pentru `cloudfront.amazonaws.com` cu `AWS:SourceArn` = distribuția;
  - `no_error_responses` → `length(aws_cloudfront_distribution.this.custom_error_response) == 0` (**Review Focus 1**);
  - `default_behavior` → `viewer_protocol_policy == "redirect-to-https"`, `compress`, `cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6"` (CachingOptimized), `function_association` cu `event_type == "viewer-request"`;
  - `api_behaviors` → `ordered_cache_behavior` are pattern-urile `["/api/*", "/swagger-ui*", "/v3/api-docs*"]`, fiecare cu:
    - `cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"` (CachingDisabled);
    - `origin_request_policy_id == "b689b0a8-53d0-40ab-baf2-68738e2966ac"` (AllViewerExceptHostHeader);
    - `length(allowed_methods) == 7`;
    - **fără** `function_association` (**Review Focus 2**);
  - `vpc_origin` → `aws_cloudfront_vpc_origin.api.vpc_origin_endpoint_config[0]`: `origin_protocol_policy == "http-only"`, `http_port == 80`, `arn == var.alb_arn`;
  - `dist` → `aliases == toset(["aradex.example", "www.aradex.example"])`, `default_root_object == "index.html"`, `http_version == "http2and3"`, certificatul ACM cu `sni-only` și `TLSv1.2_2021`;
  - `dns` → `aws_route53_record` A și AAAA, alias spre distribuție, pentru apex și `www` (4 înregistrări);
  - `cert_provider` → certificatul e creat cu `provider = aws.us_east_1`. Se verifică prin rularea testului cu un mock separat pentru alias, cu `region = "us-east-1"` în `mock_provider`.
- [ ] **Step 5:** Rulează → FAIL.
- [ ] **Step 6:** Implementează:
  - `aws_acm_certificate_validation` cu înregistrări `for_each` pe `domain_validation_options`;
  - funcția: `aws_cloudfront_function` `aradex-spa-rewrite`, `runtime = "cloudfront-js-2.0"`, `code = file(...)`, `publish = true`;
  - bucket-ul: `force_destroy = true`;
  - originea API: `domain_name = var.alb_dns_name`, `vpc_origin_config { vpc_origin_id = aws_cloudfront_vpc_origin.api.id }`.
- [ ] **Step 7:** Toate testele trec (`terraform test` + `node --test`). Commit `feat(terraform): edge module with spa rewrite`.

### Task 6: Modulul `pipelines` + buildspecs

**Files:** `terraform/modules/pipelines/*` (inclusiv `buildspecs/*.yml`), `terraform/tests/pipelines.tftest.hcl`, `terraform/main.tf`, `terraform/outputs.tf`.

**Interfaces:**
- Consumes: `github_owner`, `backend_repo`, `frontend_repo`, `branch`; `ecr_repository_url`, `ecr_repository_arn`, `cluster_name`, `service_name`, `task_execution_role_arn`, `task_role_arn` (pentru `iam:PassRole` în deploy); `bucket_name`, `bucket_arn`, `distribution_id`, `distribution_arn`; `domain_name`.
- Produces outputs: `connection_arn`, `backend_pipeline_arn`, `frontend_pipeline_arn`, `backend_pipeline_name`, `frontend_pipeline_name`.
- În root: `count = local.has_domain ? 1 : 0`.

- [ ] **Step 1: Testele care pică** (pe conținutul buildspec-urilor, prin `strcontains(aws_codebuild_project.X.source[0].buildspec, ...)`):
  - `api_test_spec` conține:
    - `corretto21`, `chmod +x gradlew`, `./gradlew test --no-daemon`;
    - `TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX: public.ecr.aws/docker/library/`, `TESTCONTAINERS_RYUK_DISABLED: "true"`;
    - `build/test-results/test`;
  - `api_build_spec` conține:
    - `docker pull public.ecr.aws/docker/library/gradle:8.14-jdk21`, `docker tag public.ecr.aws/docker/library/gradle:8.14-jdk21 gradle:8.14-jdk21`;
    - echivalentele pentru `eclipse-temurin:21-jre`;
    - `$CODEBUILD_RESOLVED_SOURCE_VERSION`, `imagedefinitions.json`, `"name":"api"`;
    - **nu** conține `--pull`;
  - `web_spec` conține:
    - `nodejs: 22`, `npm ci`, `npm run build`;
    - `max-age=31536000, immutable`;
    - `no-cache`, `index.html`, `sw.js`, `registerSW.js`, `manifest.webmanifest`, `workbox-` (**Review Focus 3**);
    - `create-invalidation`;
  - `connection` → `aws_codestarconnections_connection.github`: `provider_type == "GitHub"`, `name == "aradex-github"`;
  - `backend_pipeline` → `pipeline_type == "V2"`, `name == "aradex-backend"`, etapele `["Source", "Test", "Build", "Deploy"]`, `Deploy` cu provider-ul `ECS`; `trigger[0].git_configuration[0].push[0].branches[0].includes == ["main"]`; `FullRepositoryId == "HACK4ARAD/AradEx-Backend"`;
  - `frontend_pipeline` → `aradex-frontend`, etapele `["Source", "BuildAndPublish"]`, `FullRepositoryId == "HACK4ARAD/AradEx-Frontend"`;
  - `api_builds_arm_privileged` → `environment[0].type == "ARM_CONTAINER"`, imaginea `aws/codebuild/amazonlinux-aarch64-standard:3.0`, `privileged_mode == true` pe test și build;
  - `web_env` → `aws/codebuild/standard:7.0`; env-ul `VITE_API_URL=https://aradex.example/api/v1`, `VITE_DEMO=true`, `BUCKET`, `DISTRIBUTION_ID`;
  - `artifacts_bucket` → `force_destroy`.
- [ ] **Step 2:** Rulează → FAIL.
- [ ] **Step 3:** Implementează:
  - buildspec-urile în YAML conform spec §5.1 și §5.2; `buildspec = file("${path.module}/buildspecs/x.yml")`;
  - un rol CodePipeline (S3 pe artefacte, `codestar-connections:UseConnection`, `codebuild:StartBuild/BatchGetBuilds`, ECS `Describe*`/`UpdateService`/`RegisterTaskDefinition`, `iam:PassRole` pe cele 2 roluri de task);
  - un rol CodeBuild (logs, artefacte, ECR push pe repo + `GetAuthorizationToken`, `s3` pe bucket-ul site-ului, `cloudfront:CreateInvalidation` pe distribuție, reports);
  - cache `LOCAL` cu modurile `LOCAL_DOCKER_LAYER_CACHE` și `LOCAL_CUSTOM_CACHE` pe proiectele API.
- [ ] **Step 4:** Testele trec. Commit `feat(terraform): pipelines module`.

### Task 7: Modulul `monitoring` + verificarea root-ului

**Files:** `terraform/modules/monitoring/*`, `terraform/tests/monitoring.tftest.hcl`; extinde `terraform/tests/root.tftest.hcl`; `terraform/main.tf`.

**Interfaces:**
- Consumes: `alert_email`, `api_desired_count`, `alb_arn_suffix`, `target_group_arn_suffix`, `cluster_name`, `service_name`, `pipeline_arns` (list(string), poate fi goală).
- Produces outputs: `topic_arn`.

- [ ] **Step 1: Testele care pică:**
  - `email_sub` → `aws_sns_topic.alerts.name == "aradex-alerts"`; subscription cu `protocol == "email"`, `endpoint == var.alert_email`;
  - `topic_policy` → permite `sns:Publish` pentru `codestar-notifications.amazonaws.com` și `cloudwatch.amazonaws.com`;
  - `healthy_alarm_only_when_running` → cu count 1, `length(aws_cloudwatch_metric_alarm.healthy_hosts) == 1`, `metric_name == "HealthyHostCount"`, `comparison_operator == "LessThanThreshold"`, `threshold == 1`, `evaluation_periods == 2`, `period == 60`, `treat_missing_data == "breaching"`; cu count 0, lungimea e 0;
  - `alarm_5xx` → `HTTPCode_Target_5XX_Count`, `statistic == "Sum"`, `period == 300`, `threshold == 10`, `GreaterThanOrEqualToThreshold`, `notBreaching`;
  - `alarm_cpu` → `CPUUtilization`, namespace `AWS/ECS`, `threshold == 85`, 2 × 300;
  - `pipeline_rules` → cu 2 ARN-uri, 2 × `aws_codestarnotifications_notification_rule`, cu evenimentele `codepipeline-pipeline-pipeline-execution-failed` și `...-succeeded`; cu listă goală, 0;
  - `budget` → `aws_budgets_budget.monthly`: `limit_amount == "50"`, `limit_unit == "USD"`, 2 notificări `ACTUAL`, praguri 40 și 100 `PERCENTAGE`, cu `subscriber_email_addresses == [var.alert_email]`;
  - în `root.tftest.hcl`:
    - `no_domain` → `alert_email` setat, fără domeniu: `length(module.edge) == 0 && length(module.pipelines) == 0`;
    - `with_domain` → `domain_name = "aradex.example"`, `api_desired_count = 1`: `length(module.edge) == 1 && length(module.pipelines) == 1`.
- [ ] **Step 2:** Rulează → FAIL.
- [ ] **Step 3:** Implementează modulul și conectează-l în root. `pipeline_arns = local.has_domain ? [module.pipelines[0].backend_pipeline_arn, module.pipelines[0].frontend_pipeline_arn] : []`. Atenție: `count` pe notification rules depinde de `length(var.pipeline_arns)`, care e cunoscut la plan.
- [ ] **Step 4:** `terraform -chdir=terraform test` → toate trec; `terraform validate` și `fmt -check` → OK. Commit `feat(terraform): monitoring module`.

### Task 8: Scripturi și README

**Files:** Create `scripts/set-openai-key.sh`, `scripts/redeploy.sh`, `scripts/destroy.sh`. Modify `README.md`.

- [ ] **Step 1:** Toate scripturile încep cu `set -euo pipefail`, `export AWS_PROFILE=${AWS_PROFILE:-aws-toolkit} AWS_REGION=eu-north-1`.
  - `set-openai-key.sh` → `read -rs` pentru cheie, `aws secretsmanager put-secret-value --secret-id aradex/openai --secret-string "$KEY"`, apoi `aws ecs update-service --cluster aradex --service aradex-api --force-new-deployment`. Cheia nu apare în argumentele scriptului.
  - `redeploy.sh api|web` → `aws codepipeline start-pipeline-execution --name aradex-backend|aradex-frontend`; orice alt argument dă mesajul de folosire și codul de ieșire 2.
  - `destroy.sh` → cere tastarea `DESTROY`, apoi `terraform -chdir=terraform destroy`, apoi listează snapshot-ul `aradex-final`.
- [ ] **Step 2:** `bash -n scripts/*.sh` → OK; `scripts/redeploy.sh foo; echo $?` → `2`.
- [ ] **Step 3:** README:
  - „Local” (neschimbat);
  - „AWS: de la zero la live” (bootstrap → `local.auto.tfvars` → `init` → `plan`/`apply` în pași, ca în Task-urile 9–11);
  - „Redeploy”;
  - „Ștergere”;
  - „Variabile”.
- [ ] **Step 4:** Commit `docs(infra): scripts and aws runbook`.

### Task 9: Bootstrap + primul apply: network, data, api (0 taskuri)

- [ ] **Step 1: STOP.** Arată-i lui Zoltan `terraform -chdir=terraform/bootstrap plan` și explică pasul. Așteaptă „da”. Apoi `apply` → bucket-ul de state există.
- [ ] **Step 2:** Creează `terraform/local.auto.tfvars` cu `alert_email`. `terraform -chdir=terraform init` (cu backend-ul S3) → `Successfully configured the backend "s3"`.
- [ ] **Step 3: STOP.** `terraform -chdir=terraform plan -out=phase1.tfplan`, fără `domain_name`, deci doar network, data, api și monitoring. Arată-i lui Zoltan rezumatul (resursele, ~1,5 $/zi). Așteaptă „da”.
- [ ] **Step 4:** `terraform -chdir=terraform apply phase1.tfplan` → `Apply complete`. RDS durează ~5–10 min. Dacă planul gratuit refuză ceva, notează eroarea exactă și ajustează doar parametrul refuzat (test + cod).
- [ ] **Step 5:** Verifică:
  - `aws rds describe-db-instances` → `available`, `PubliclyAccessible: false`;
  - `aws ecs describe-services --cluster aradex --services aradex-api` → `desiredCount 0`;
  - secretele există.

  Zoltan rulează `scripts/set-openai-key.sh`.

### Task 10: Domeniu, certificat, CloudFront

- [ ] **Step 1:** Zoltan cumpără domeniul. Pune `domain_name = "<domeniu>"` în `terraform.tfvars`. Commit `chore(terraform): set domain`.
- [ ] **Step 2: STOP.** `terraform plan -target=module.edge[0].aws_route53_zone.this -out=zone.tfplan` (doar zona). Aprobarea lui Zoltan, apoi `apply` și `terraform output name_servers`.
- [ ] **Step 3:** Zoltan pune cele 4 NS la registrar. Verifică `dig NS <domeniu> +short` → serverele `awsdns`.
- [ ] **Step 4: STOP.** `terraform plan -target=module.edge -out=edge.tfplan` (tot `edge`, încă fără `pipelines`), aprobarea lui Zoltan, apoi `apply`. Validarea ACM durează câteva minute după propagarea NS.
- [ ] **Step 5:** Verifică:
  - `curl -sI https://<domeniu>/` → TLS valid; 403 sau 404 de la S3 (bucket gol);
  - `curl -s -o /dev/null -w '%{http_code}' https://<domeniu>/api/v1/health` → `503` (0 taskuri), ceea ce dovedește că ruta ajunge la ALB.

  **Dacă `aws_cloudfront_vpc_origin` eșuează în `eu-north-1`**, aplică planul de rezervă din spec §2.1:
  - ALB public (`internal = false`, subneturile publice);
  - originea `custom_origin_config` cu header-ul `X-Origin-Verify` (un `random_password`);
  - o regulă de listener care întoarce 403 fără header.

  Testele din Task 4 și Task 5 se ajustează în același commit.

### Task 11: Pipeline-uri, primul release, monitorizare

- [ ] **Step 1: STOP.** `terraform plan -out=pipes.tfplan` (adaugă `pipelines` și regulile de notificare), aprobarea lui Zoltan, apoi `apply`.
- [ ] **Step 2:** Zoltan:
  - consolă → Developer Tools → Connections → `aradex-github` → „Update pending connection”;
  - instalează aplicația pe HACK4ARAD, cu acces doar la `AradEx-Backend` și `AradEx-Frontend`.

  Verifică `aws codestar-connections get-connection --connection-arn $(terraform output -raw connection_arn)` → `AVAILABLE`.
- [ ] **Step 3:** `scripts/redeploy.sh web` → `Succeeded`, iar `https://<domeniu>/m` se încarcă. `scripts/redeploy.sh api` → dacă T01 nu compilează încă, `Test` sau `Build` pică. E acceptat; se reia după merge-ul T01.
- [ ] **Step 4:** După primul `Build` reușit al BE: `api_desired_count = 1`, apoi `plan` + aprobare + `apply`. Verifică:
  - `curl https://<domeniu>/api/v1/health` → `{"status":"ok",...}`;
  - `/api/v1/me` fără token → `401`;
  - `/api/v1/events/999999` → JSON ProblemDetail, nu HTML.
- [ ] **Step 5:** Zoltan confirmă abonarea din emailul AWS SNS.
- [ ] **Step 6: Test de rollback** (cu aprobare): o revizie de task definition cu imaginea `aradex-api:does-not-exist`, aplicată prin `aws ecs update-service`. Așteaptă:
  - serviciul revine singur;
  - `/health` rămâne 200 tot timpul;
  - sosește emailul.

  După test, rulează `terraform apply` ca revizia să revină la cea din Terraform.
- [ ] **Step 7:** Pe telefon: `/m` se încarcă și „Add to Home Screen” e disponibil.
- [ ] **Step 8:** Commit `chore(terraform): enable api service`.

### Task 12: Documentația în AradEx-Plan

**Files:** Modify `AradEx-Plan/docs/DEPLOY.md`, `AradEx-Plan/docs/PLAN.md` (doar T04 și T16a).

- [ ] **Step 1:** `git -C AradEx-Plan switch -c feat/T04-aws-infra origin/main`.
- [ ] **Step 2:** Rescrie `DEPLOY.md`:
  - componentele (CloudFront, S3, Fargate, RDS, CodePipeline);
  - URL-urile reale;
  - accesul (Zoltan, cont AWS);
  - redeploy (merge pe `main` sau `scripts/redeploy.sh`);
  - logurile `/aradex/api`;
  - schimbările de infrastructură (`terraform plan` / `apply` din `AradEx-Infrastructure/terraform`);
  - ștergerea de luni.
- [ ] **Step 3:** La T04 și T16a, adaugă o notă de o linie: „Deploy pe AWS (CloudFront + Fargate + RDS, Terraform) în loc de Render/Netlify/Neon; vezi `docs/DEPLOY.md` și `AradEx-Infrastructure/README.md`.”
- [ ] **Step 4:** Commit `docs: aws deploy`. Push și PR-uri **doar când cere Zoltan**.

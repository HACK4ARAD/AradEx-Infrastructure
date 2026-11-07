# AradExperience pe AWS: design de infrastructură

**Data:** 7 nov 2026 · **Owner:** Zoltan (P1) · **Repo:** `AradEx-Infrastructure` · **Story-uri:** T04 (deploy v0), T16a (deploy final)
**Stare:** spec aprobat.
- **Revizia 2 (7 nov):** infrastructura se scrie în Terraform, nu în CDK, la cererea lui Zoltan.
- **Revizia 3 (7 nov):** contul are cota CodeBuild „Concurrently running builds” = 0 pentru toate mediile, deci CodePipeline/CodeBuild nu pot rula. La cererea lui Zoltan, **deploy-ul trece pe GitHub Actions cu OIDC**, iar **Fargate trece pe x86_64** (runner-ele GitHub gratuite sunt x86; build nativ cu `Dockerfile`-ul existent). Diferențele sunt în §1, §3, §4, §5, §6, §7, §8, §10.
- **Revizia 4 (7 nov, la deploy):** organizația AWS a contului (SCP `p-wpt9usyn`) interzice `iam:CreateOpenIDConnectProvider` și permite doar regiunile `eu-north-1` și `us-east-1`. În loc de OIDC: modulul `github_deploy` creează utilizatorii IAM `aradex-gha-backend` și `aradex-gha-frontend` (`force_destroy`), cu aceleași permisiuni. Cheile le creează `scripts/github-keys.sh` direct în secretele repo-urilor (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`), deci nu ajung în Terraform, git sau chat. Se șterg la `terraform destroy`.

## 1. Scop și constrângeri

**Scop:** AradExperience (API Spring Boot + PWA Vue + Postgres) rulează pe AWS, pe un domeniu propriu cu HTTPS, cu deploy automat la merge pe `main`, sigur pentru demo-ul de duminică 8 nov 2026 (code freeze la 10:00).

**Ce a cerut Zoltan:**
- tot pe AWS, în locul Render / Netlify / Neon din `AradEx-Plan/docs/DEPLOY.md`;
- simplu și fără costuri mari, dar solid;
- durata de viață: **doar weekendul de demo**, se șterge luni;
- domeniu propriu, **cumpărat extern**, cu DNS-ul în AWS;
- deploy **automat la merge pe `main`** în `AradEx-Backend` și `AradEx-Frontend`, cu **testele BE rulate înainte de deploy** (GitHub Actions);
- alertele pe email merg la adresa contului lui Zoltan.

**Constrângeri constatate:**
- Contul `712710404828`, regiunea `eu-north-1`, profilul CLI `aws-toolkit`. E pe **planul gratuit AWS** (100 $ credite, activ până în mai 2027) și e gol (doar VPC-ul implicit).
- Pe planul gratuit, Route 53 Domains e blocat, deci domeniul se cumpără la un registrar extern.
- App Runner nu există în `eu-north-1`.
- Docker nu e instalat local, deci imaginile se construiesc în AWS.
- Regula echipei spunea că repo-urile de cod nu au workflows. **Revizia 3 o schimbă, la decizia lui Zoltan:** câte un singur fișier nou, `.github/workflows/deploy.yml`, în `AradEx-Backend` și `AradEx-Frontend`. Restul codului lor rămâne neatins.
- Cota CodeBuild a contului e 0, deci nu folosim CodeBuild/CodePipeline.
- Fără secrete în git.

**Criterii de reușită:**
1. `https://<domeniu>/` deschide PWA-ul, iar `https://<domeniu>/api/v1/health` răspunde `{status:"ok"}`.
2. Un merge pe `main` în Backend ajunge live în ≤ 10 min; unul în Frontend în ≤ 5 min.
3. Un deploy BE stricat (test roșu sau container care nu pornește) nu scoate din funcțiune versiunea care rulează.
4. Scannerul QR (camera) și geolocația merg pe telefon, ceea ce cere HTTPS.
5. Costul total al weekendului e ≤ 15 $, din credite.
6. Luni, `terraform destroy` șterge tot, în afară de snapshot-ul final al bazei de date.

## 2. Arhitectura

```
                 https://<domeniu>   (+ www.<domeniu> → redirect)
                              │
                     CloudFront (cert ACM în us-east-1)
              ┌───────────────┴─────────────────────────┐
   / (default)│                                         │ /api/* · /swagger-ui* · /v3/api-docs*
              ▼                                         ▼  fără cache; forward la Authorization, query, body
   S3 privat (dist/ al FE), acces doar prin OAC     VPC origin → ALB intern (HTTP :80)
   rutele SPA → /index.html (CloudFront Function)                                  │
                                                                ▼
                                       ECS Fargate · 1 task · x86_64 · 0,5 vCPU / 1 GB
                                       subnet public, IP public doar pentru ieșire
                                                                │ :5432 (SSL)
                                                                ▼
                                       RDS PostgreSQL 16 · db.t4g.micro · 20 GB gp3, criptat
                                       subnet izolat, fără acces din internet
```

### 2.1 Rețea
- VPC nou `10.40.0.0/16`, 2 zone. Subneturi publice (Fargate) și izolate (RDS). **Fără NAT Gateway.**
- Security groups:
  - ALB: intrare doar din CloudFront (VPC origin);
  - task: intrare `8080` doar din SG-ul ALB;
  - RDS: intrare `5432` doar din SG-ul taskului.
- Taskul are IP public numai pentru ieșire: ECR, Secrets Manager, CloudWatch Logs, SSM (ECS Exec), OpenAI, OSRM. Nicio regulă de intrare nu îl expune.
- **Plan de rezervă**, dacă VPC origin nu funcționează în `eu-north-1`: ALB public, cu SG pe prefix list-ul `com.amazonaws.global.cloudfront.origin-facing` (`pl-fab65393`) și un header secret `X-Origin-Verify` pus de CloudFront și verificat de o regulă pe listener. Restul designului rămâne la fel.

### 2.2 Un singur domeniu
- Domeniul `<domeniu>` (încă nedecis; variabila Terraform `domain_name`) are o zonă Route 53 creată de Terraform. Zoltan pune cele 4 nameservere la registrar.
- Certificat ACM în `us-east-1` pentru `<domeniu>` și `www.<domeniu>`, validat prin DNS.
- Frontend-ul și API-ul sunt pe același origin, deci browserul nu face cereri CORS. `CORS_ORIGINS` rămâne totuși setat la `https://<domeniu>`.
- `VITE_API_URL` trebuie să fie **absolut** (`https://<domeniu>/api/v1`), pentru că `shared/api/client.ts` construiește URL-ul cu `new URL(...)`.

### 2.3 CloudFront
- **Comportamentul default (S3):** politica de cache `CachingOptimized`, compresie, HTTP/2+3, redirect HTTP → HTTPS. O CloudFront Function (viewer-request, doar aici) rescrie rutele SPA `/m/*` și `/w/*` spre `/index.html` și redirecționează `www` spre domeniu. **Fără `custom_error_response` pe distribuție**: ar transforma și erorile 403/404 ale API-ului în HTML.
- **`/api/*`, `/swagger-ui*`, `/v3/api-docs*` (ALB):** `CachingDisabled` + `AllViewerExceptHostHeader`, toate metodele HTTP, timeout de citire 60 s (apelurile AI).
- Logurile CloudFront sunt oprite (weekend).

## 3. Componente (module Terraform)

Terraform ≥ 1.17, provider-ul `hashicorp/aws` 6.72.x și `hashicorp/random` 3.9.x, în `AradEx-Infrastructure/terraform/`:
- **un root module**, `terraform/`, cu două provider-e AWS: `eu-north-1` (implicit) și alias-ul `aws.us_east_1`;
- **module locale**, în `terraform/modules/`, fiecare cu un singur rol.

| Modul | Regiune | Conține | Primește de la |
|---|---|---|---|
| `network` | eu-north-1 | VPC, subneturi, security groups | — |
| `data` | eu-north-1 | RDS Postgres 16 (parola gestionată de RDS în Secrets Manager), secretele `aradex/jwt` și `aradex/openai` | network |
| `api` | eu-north-1 | ECR `aradex-api`, cluster ECS, task definition, serviciu Fargate, ALB intern, target group, log group, rolurile IAM ale taskului | network, data |
| `edge` | eu-north-1 + `aws.us_east_1` | zona Route 53, certificat ACM (us-east-1) + validarea DNS, bucket S3 (privat, OAC), CloudFront Function, VPC origin, distribuția CloudFront, înregistrări A/AAAA | api |
| `github_oidc` | eu-north-1 | providerul OIDC GitHub în IAM, rolul `aradex-gha-backend` (ECR push + deploy ECS), rolul `aradex-gha-frontend` și parametrii SSM `/aradex/web/*` (aceștia doar cu domeniu) | api, edge |
| `monitoring` | eu-north-1 | topic SNS (email), alarme CloudWatch, buget AWS | api |

- `edge`, precum și rolul FE și parametrii SSM din `github_oidc`, se creează **doar dacă `domain_name` e setat**. Așa `network`, `data`, `api`, rolul BE și `monitoring` pot porni înainte de cumpărarea domeniului.
- **Variabile** (în `terraform.tfvars`, fără secrete): `domain_name`, `api_desired_count` (0/1), `github_owner` (`HACK4ARAD`), `backend_repo`, `frontend_repo`, `branch` (`main`).
- `alert_email` stă într-un `local.auto.tfvars` ignorat de git, sau se dă cu `-var`.
- **State:** S3 cu lock nativ (`use_lockfile = true`, fără DynamoDB), în bucket-ul `aradex-tfstate-712710404828` (eu-north-1, versionat, criptat, fără acces public). Bucket-ul îl creează o dată un mic root separat, `terraform/bootstrap/`, cu state local.

## 4. Configurarea API-ului

| Variabilă | Sursă |
|---|---|
| `POSTGRES_URL` | compusă în Terraform: `jdbc:postgresql://<rds-endpoint>:5432/aradexperience?sslmode=require` |
| `POSTGRES_USER`, `POSTGRES_PASSWORD` | secretul gestionat de RDS (`manage_master_user_password = true`, cheile `username` și `password`), injectat ca ECS secret |
| `JWT_SECRET` | `random_password` (64 de caractere, fără caractere speciale), scris în secretul `aradex/jwt`. Valoarea ajunge și în state-ul Terraform, care e criptat și privat în S3. |
| `OPENAI_API_KEY` | secretul `aradex/openai`, creat cu valoarea placeholder `REPLACE_ME` și `ignore_changes` pe valoare. Zoltan pune cheia reală cu `scripts/set-openai-key.sh` (citește din stdin). Cheia nu apare nici în git, nici în state. |
| `OPENAI_MODEL` | `gpt-4o-mini` |
| `CORS_ORIGINS` | `https://<domeniu>` |
| `SPRING_PROFILES_ACTIVE` | `prod` |

- **Taskul:** 0,5 vCPU / 1 GB, x86_64. `JAVA_OPTS` vine din `Dockerfile`-ul existent.
- **Health check-ul ALB:** `/api/v1/health`, interval 15 s, 2 verificări bune / 3 rele.
- **Grace period-ul serviciului:** 180 s, pentru Spring Boot + Flyway.
- **Deployment:** min 100 % / max 200 %, circuit breaker cu rollback activat.
- **Executarea comenzilor:** ECS Exec e activat, pentru depanare (`aws ecs execute-command`), fără acces public la baza de date.
- **Logurile** merg în CloudWatch `/aradex/api`, păstrate 7 zile.
- **Primul deploy:** se face cu `api_desired_count = 0`, pentru că ECR e gol și T01 poate încă să nu compileze. După primul deploy reușit din GitHub Actions (care urcă imaginea în ECR), `api_desired_count = 1` și `terraform apply`.
- **Task definition-ul:** Terraform îl definește cu imaginea `aradex-api:latest`. Workflow-ul BE înregistrează revizii noi, cu tag-ul commit-ului. Un `terraform apply` ulterior readuce revizia Terraform, care folosește `:latest`, adică aceeași imagine construită ultima, deci nu pierdem nimic. Asta e intenționat; nu folosim `ignore_changes` pe `task_definition`, ca modificările de variabile din Terraform să ajungă în serviciu.

**Baza de date:**
- RDS Postgres 16 (ultima versiune minoră disponibilă), `db.t4g.micro`, Single-AZ, 20 GB gp3, criptată, `rds.force_ssl=1`;
- backup automat 1 zi, deletion protection oprit;
- **la ștergere se face snapshot automat** (`skip_final_snapshot = false`, `final_snapshot_identifier = "aradex-final"`);
- baza inițială se numește `aradexperience`.
- **Flyway** rulează V1… și seed-urile la fiecare pornire, deci datele de producție sunt identice cu cele locale.

## 5. Fluxul de deploy (GitHub Actions + OIDC)

GitHub obține credențiale AWS temporare prin OIDC (`token.actions.githubusercontent.com`, audience `sts.amazonaws.com`), deci nu există chei AWS stocate în GitHub. Fiecare rol acceptă **doar** repo-ul și branch-ul lui: `sub = repo:HACK4ARAD/<repo>:ref:refs/heads/main`.

### 5.1 Backend: `AradEx-Backend/.github/workflows/deploy.yml`, la push pe `main` (+ pornire manuală)
1. **`test`** (`ubuntu-24.04`, Temurin 21, `gradle/actions/setup-gradle`): `./gradlew test`. Testcontainers folosește Docker-ul runner-ului. Un test roșu oprește workflow-ul.
2. **`deploy`** (`needs: test`), cu rolul `aradex-gha-backend`:
   - login ECR, apoi `docker build` cu `Dockerfile`-ul existent și push cu tag-urile `<sha>` și `latest`;
   - task definition-ul curent `aradex-api` (`describe-task-definition`) cu imaginea nouă, în containerul `api`;
   - `amazon-ecs-deploy-task-definition` pe serviciul `aradex-api`, cluster `aradex`, cu `wait-for-service-stability`;
   - rolling update; circuit breaker-ul revine automat la revizia anterioară dacă taskul nou nu trece health check-ul.
- `concurrency: deploy-api` (deploy-urile nu se suprapun).

### 5.2 Frontend: `AradEx-Frontend/.github/workflows/deploy.yml`, la push pe `main` (+ pornire manuală)
Un singur job (Node 22), cu rolul `aradex-gha-frontend`:
1. Citește din SSM `/aradex/web/bucket`, `/aradex/web/distribution_id` și `/aradex/web/api_url` (`https://<domeniu>/api/v1`).
2. Rulează `npm ci`, `npm run test`, apoi `npm run build` cu `VITE_API_URL` din SSM și `VITE_DEMO=true`.
3. Urcă fișierele în S3 cu aceleași reguli de cache ca înainte:
   - `assets/`: `max-age=31536000, immutable`, fără ștergere;
   - restul fișierelor: `max-age=3600`;
   - `index.html`, `sw.js`, `registerSW.js`, `manifest.webmanifest`, `workbox-*.js`: `no-cache`.
4. Invalidează CloudFront cu `/*`.

### 5.3 Ce nu e automat
- Infrastructura (Terraform) se schimbă **doar** cu `terraform apply` rulat de Zoltan.
- **Redeploy manual:** butonul „Run workflow” din tab-ul Actions (`workflow_dispatch`) sau `gh workflow run deploy.yml -R HACK4ARAD/<repo>`.
- **Pas unic:** GitHub Actions trebuie să fie permis în organizația HACK4ARAD (Settings → Actions). Organizațiile gratuite au 2000 de minute pe lună pentru repo-uri private; un deploy BE durează ~6–8 min, unul FE ~2 min.

## 6. Erori și reziliență

| Situație | Ce se întâmplă |
|---|---|
| Test BE roșu | workflow-ul se oprește la `test`; versiunea live rămâne; GitHub trimite email autorului commit-ului |
| Containerul nou nu trece health check-ul | circuit breaker-ul revine la task definition-ul anterior; email |
| Taskul moare în timpul demo-ului | ECS pornește altul automat (~1–2 min); alarma „0 taskuri sănătoase” trimite email |
| Build FE eșuat | S3 rămâne cu versiunea anterioară (upload-ul nu rulează) |
| OpenAI cade sau cheia e greșită | aplicația are deja fallback (`offline: true`), infrastructura nu e afectată |
| OSRM sau tile-urile OSM cad | fallback-ul din FE (linie dreaptă); infrastructura nu e afectată |
| Limita Docker Hub | nu se aplică practic runner-elor GitHub |
| Credite pe sfârșite | alerte de buget la 20 $ și 50 $ |

## 7. Monitorizare
- Topic SNS `aradex-alerts` cu abonament pe email (adresa contului lui Zoltan; se confirmă o dată din email).
- **Alarme:**
  - `HealthyHostCount < 1` pe target group, 2 minute;
  - `HTTPCode_Target_5XX_Count ≥ 10` în 5 minute;
  - CPU-ul serviciului ECS > 85 % timp de 10 minute.
- Eșecurile de deploy le notifică GitHub (email către autorul commit-ului / watcher-ii repo-ului), nu SNS.
- Buget lunar de 50 $, cu alerte la 20 $ (40 %) și 50 $ (100 %).

## 8. Cost (estimat, `eu-north-1`, ~4 zile vineri–luni)

| Resursă | ~ $ / zi | ~ $ / weekend |
|---|---|---|
| ALB | 0,6 | 2,5 |
| Fargate 0,5 vCPU / 1 GB x86 | 0,6 | 2,4 |
| RDS db.t4g.micro + 20 GB | 0,45 | 1,8 |
| IPv4 public (task), Secrets Manager (3), Route 53 (zonă), CloudFront, SSM, CloudWatch (GitHub Actions: gratuit, în cele 2000 min/lună) | ~0,5 | ~2 |
| **Total** | **~2** | **~8–10** |

Totul vine din cele 100 $ de credite. Domeniul extern se plătește separat, la registrar.

## 9. Ștergere (luni 9 nov)
`scripts/destroy.sh`, adică `terraform destroy` în `terraform/`. Bucket-urile au `force_destroy = true`, iar ECR are `force_delete = true`, deci ștergerea nu se blochează pe conținut. Rămân:
- snapshot-ul final RDS `aradex-final` (îl ștergi tu dacă nu-l vrei);
- bucket-ul de state (se șterge la final cu `terraform destroy` în `terraform/bootstrap/`, după ce îl golești);
- domeniul de la registrar.

## 10. Ce se schimbă în repo-uri
- **`AradEx-Infrastructure`:**
  - `terraform/` (root-ul, `bootstrap/`, `modules/` din §3, `tests/`);
  - `scripts/` (`set-openai-key.sh`, `redeploy.sh`, `destroy.sh`);
  - README actualizat (pași de la zero la live);
  - `.gitignore` pentru `.terraform/`, `*.tfstate*`, `*.tfplan`, `local.auto.tfvars`. Lock file-ul `.terraform.lock.hcl` **intră** în git.
- **`AradEx-Plan`:**
  - `docs/DEPLOY.md` rescris pentru AWS (URL-uri, acces, redeploy, ștergere);
  - o notă la T04 și T16a în `docs/PLAN.md` că deploy-ul e pe AWS în loc de Render / Netlify / Neon.
- **`AradEx-Backend`, `AradEx-Frontend`:** doar `.github/workflows/deploy.yml` (revizia 3).
- **`AradEx-Plan/CLAUDE.md`:** regula „repo-urile de cod nu au workflows” se actualizează (excepție: `deploy.yml`).

## 11. Testare și verificare
- `terraform fmt -check -recursive` și `terraform validate`.
- `terraform test`, cu `mock_provider "aws"` și `command = plan`. Asertează pe atributele resurselor fără credențiale și fără resurse create.
- `terraform plan` pe contul real, înainte de fiecare `apply`, arătat lui Zoltan.
- **Smoke după fiecare etapă:**
  - `curl https://<domeniu>/api/v1/health`;
  - un `curl` fără token pe o rută protejată întoarce 401;
  - `/m` se încarcă pe telefon;
  - scannerul QR cere permisiunea camerei.
- **Test de rollback** (o dată, sâmbătă): un deploy cu imagine care nu pornește → serviciul revine singur, iar alarma și emailul sosesc.
- **Test de deploy:** un commit banal pe `main` în FE ajunge live în ≤ 5 min.

## 12. În afara scopului
Multi-AZ, WAF, autoscaling, staging separat, acces AWS pentru colegi, bastion sau tunel spre baza de date, CDN pentru imagini încărcate de utilizatori (aplicația nu are upload în v1).

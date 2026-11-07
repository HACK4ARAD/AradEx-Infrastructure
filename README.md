# AradEx-Infrastructure

Infrastructura AradExperience (Hack4Arad 2026). Owner: **P1 · Zoltan** (T00, T04, T16a). Designul: `docs/superpowers/specs/2026-11-07-aws-infrastructure-design.md`.

## Local
```
docker compose up -d      # Postgres 16 pe localhost:5432, db aradexperience, user/parolă arad/arad
docker compose down       # oprește (datele rămân în volumul aradexperience_pg)
```
Fiecare task își face baza lui: `createdb -h localhost -U arad aradexperience_txx` (parola `arad`).
Fără Docker: Postgres 16 local cu rolul `arad` (parola `arad`, `CREATEDB`).

## AWS (Terraform)
Un singur domeniu cu HTTPS: CloudFront servește `/` din S3 (PWA-ul) și trimite `/api/*` spre un ALB intern → Fargate (API). Baza de date e RDS Postgres 16, izolată de internet. GitHub Actions face deploy la fiecare merge pe `main`, cu acces AWS prin OIDC (fără chei): `AradEx-Backend` (teste → imagine → ECS) și `AradEx-Frontend` (teste + build → S3 → invalidare). Workflow-urile sunt în `.github/workflows/deploy.yml` din fiecare repo.

Cont `712710404828`, regiunea `eu-north-1`, profilul `aws-toolkit`. **Nicio cheie sau parolă în repo.**

```
terraform/
  bootstrap/        bucket-ul pentru state (rulat o singură dată, state local)
  *.tf              root-ul: variabile, provider-e (eu-north-1 + us-east-1), backend S3, module
  modules/          network · data · api · edge (domeniu, cert, CloudFront) · github_oidc (roluri pentru GitHub Actions) · monitoring
  tests/            terraform test (mock-uri, fără credențiale)
scripts/            set-openai-key.sh · redeploy.sh · destroy.sh
```

### De la zero la live
Toate comenzile se dau din rădăcina repo-ului, cu `export AWS_PROFILE=aws-toolkit`. **Înainte de orice `apply`, citește `plan`-ul.**

1. **Bucket-ul de state** (o singură dată):
   ```
   terraform -chdir=terraform/bootstrap init
   terraform -chdir=terraform/bootstrap apply
   ```
2. **Variabile locale.** Creează `terraform/local.auto.tfvars` (ignorat de git) cu:
   ```
   alert_email = "adresa-ta@exemplu.ro"
   ```
3. **Rețea, bază de date, API** (încă fără domeniu, 0 containere):
   ```
   terraform -chdir=terraform init
   terraform -chdir=terraform plan -out=phase1.tfplan
   terraform -chdir=terraform apply phase1.tfplan
   ./scripts/set-openai-key.sh
   ```
4. **Domeniul.** După cumpărare, pune `domain_name = "<domeniu>"` în `terraform/terraform.tfvars`, apoi:
   ```
   terraform -chdir=terraform apply -target='module.edge[0].aws_route53_zone.this'   # ghilimelele contează în zsh
   terraform -chdir=terraform output name_servers   # pune-le la registrar
   dig NS <domeniu> +short                          # așteaptă să apară serverele awsdns
   terraform -chdir=terraform plan -target='module.edge' -out=edge.tfplan
   terraform -chdir=terraform apply edge.tfplan     # certificatul se validează în câteva minute
   ```
5. **Deploy automat (GitHub Actions):**
   - aplică restul: `terraform -chdir=terraform plan -out=all.tfplan`, apoi `apply all.tfplan` (rolul FE și parametrii SSM `/aradex/web/*`);
   - pe GitHub: HACK4ARAD → Settings → Actions → permite rularea workflow-urilor;
   - fă merge la workflow-urile din branch-urile `feat/T04-aws-infra` din `AradEx-Backend` și `AradEx-Frontend`, sau pornește-le manual:
     ```
     gh workflow run deploy.yml -R HACK4ARAD/AradEx-Frontend
     gh workflow run deploy.yml -R HACK4ARAD/AradEx-Backend
     ```
6. **Pornește API-ul**, după primul workflow BE reușit (imaginea e în ECR; cu 0 taskuri, pasul ECS trece fără să pornească nimic): `api_desired_count = 1` în `terraform.tfvars`, apoi `plan` + `apply`.
7. **Confirmă emailul** de la AWS SNS (alertele).

### Redeploy
- Automat: orice merge pe `main` în `AradEx-Backend` sau `AradEx-Frontend`.
- Manual: `./scripts/redeploy.sh api` sau `./scripts/redeploy.sh web` (pornește workflow-ul din GitHub), ori „Run workflow” în tab-ul Actions.
- Infrastructura se schimbă doar cu `terraform plan` + `apply`, rulate de Zoltan.

### Depanare
- Swagger (`https://<domeniu>/swagger-ui.html`) arată documentația, dar „Try it out” nu merge prin CloudFront: Spring vede adresa internă a ALB-ului. Testează cu `curl` sau din aplicație. Dacă PWA-ul e instalat în browser, deschide Swagger într-o fereastră privată (service worker-ul redirecționează navigarea spre aplicație).
- Loguri API: CloudWatch `/aradex/api`. Loguri deploy: tab-ul Actions din `AradEx-Backend` / `AradEx-Frontend`.
- Shell în containerul API: `aws ecs execute-command --cluster aradex --task <task-id> --container api --interactive --command sh`.

### Teste
```
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform test
terraform -chdir=terraform validate -no-tests
terraform fmt -check -recursive terraform
node --test terraform/modules/edge/functions/
```

### Ștergere (după demo)
`./scripts/destroy.sh` cere confirmarea `DESTROY` și șterge tot. Dacă ștergerea VPC-ului pică cu `DependencyViolation`, rulează scriptul din nou: CloudFront eliberează cu întârziere interfețele de rețea ale VPC origin-ului. Rămân:
- snapshot-ul final RDS `aradex-final`;
- bucket-ul de state, pe care îl ștergi la final cu `terraform -chdir=terraform/bootstrap destroy`, după ce îl golești.

### Variabile (`terraform/terraform.tfvars`, fără secrete)
| Variabilă | Implicit | Ce face |
|---|---|---|
| `domain_name` | `""` | domeniul; până e setat, CloudFront, rolul GitHub pentru FE și parametrii SSM nu se creează |
| `api_desired_count` | `0` | 0 până există o imagine în ECR, apoi 1 |
| `alert_email` | — | în `local.auto.tfvars`; alertele și bugetul |
| `github_owner`, `backend_repo`, `frontend_repo`, `branch` | `HACK4ARAD`, `AradEx-Backend`, `AradEx-Frontend`, `main` | singurele repo-uri și branch care pot asuma rolurile OIDC |

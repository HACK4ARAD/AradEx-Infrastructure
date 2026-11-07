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
Un singur domeniu cu HTTPS, direct pe un ALB public (certificat ACM în `eu-north-1`): `/api/*`, `/swagger-ui*` și `/v3/api-docs*` merg la API (Spring, Fargate), restul la PWA (nginx, Fargate); HTTP și `www` redirecționează spre `https://<domeniu>`. Baza de date e RDS Postgres 16, izolată de internet. **Fără CloudFront:** contul nu poate crea distribuții până nu e verificat de AWS Support. GitHub Actions face deploy la fiecare merge pe `main`, cu cheile a doi utilizatori IAM dedicați, cu permisiuni înguste (organizația AWS interzice OIDC): `AradEx-Backend` (teste → imagine → ECS) și `AradEx-Frontend` (teste + build → imagine nginx → ECS). Workflow-urile sunt în `.github/workflows/deploy.yml` din fiecare repo.

Cont `712710404828`, regiunea `eu-north-1`, profilul `aws-toolkit`. **Nicio cheie sau parolă în repo.**

```
terraform/
  bootstrap/        bucket-ul pentru state (rulat o singură dată, state local)
  *.tf              root-ul: variabile, provider-e (eu-north-1 + us-east-1), backend S3, module
  modules/          network · data · api (ALB, listeneri, API) · web (nginx cu PWA-ul) · edge (zona DNS, certificat) · github_deploy (utilizatori IAM pentru GitHub Actions) · monitoring
  tests/            terraform test (mock-uri, fără credențiale)
scripts/            set-anthropic-key.sh · set-google-places-key.sh · github-keys.sh · redeploy.sh · destroy.sh
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
   ./scripts/set-anthropic-key.sh       # cheia Claude API (ANTHROPIC_API_KEY); modelul: anthropic_model, implicit claude-haiku-5-5
   ./scripts/set-google-places-key.sh   # opțional (T17): cheia Google Places API (New) → GOOGLE_PLACES_API_KEY
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
   - aplică restul: `terraform -chdir=terraform plan -out=all.tfplan`, apoi `apply all.tfplan` (certificat, HTTPS, serviciul web, utilizatorul FE, parametrul SSM `/aradex/web/api_url`);
   - pe GitHub: HACK4ARAD → Settings → Actions → permite rularea workflow-urilor;
   - pune cheile în secretele repo-urilor (nu apar pe ecran; cheile vechi se șterg): `./scripts/github-keys.sh api` și `./scripts/github-keys.sh web`. Scriptul cere `gh` autentificat cu acces la organizația HACK4ARAD;
   - fă merge la workflow-urile din branch-urile `feat/T04-aws-infra` din `AradEx-Backend` și `AradEx-Frontend`, sau pornește-le manual:
     ```
     gh workflow run deploy.yml -R HACK4ARAD/AradEx-Frontend
     gh workflow run deploy.yml -R HACK4ARAD/AradEx-Backend
     ```
6. **Pornește containerele**, după primul workflow reușit al fiecărui repo (imaginea e în ECR; cu 0 taskuri, pasul ECS trece fără să pornească nimic): `api_desired_count = 1` și `web_desired_count = 1` în `terraform.tfvars`, apoi `plan` + `apply`.
7. **Confirmă emailul** de la AWS SNS (alertele).

### Redeploy
- Automat: orice merge pe `main` în `AradEx-Backend` sau `AradEx-Frontend`.
- Manual: `./scripts/redeploy.sh api` sau `./scripts/redeploy.sh web` (pornește workflow-ul din GitHub), ori „Run workflow” în tab-ul Actions.
- Infrastructura se schimbă doar cu `terraform plan` + `apply`, rulate de Zoltan.

### Depanare
- Swagger (`https://<domeniu>/swagger-ui.html`) arată documentația; „Try it out” poate încerca `http://` (Spring nu citește `X-Forwarded-Proto`) și browserul îl blochează. Testează cu `curl` sau din aplicație. Dacă PWA-ul e instalat în browser, deschide Swagger într-o fereastră privată (service worker-ul redirecționează navigarea spre aplicație).
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
`./scripts/destroy.sh` cere confirmarea `DESTROY` și șterge tot. Dacă ștergerea VPC-ului pică cu `DependencyViolation`, rulează scriptul din nou (interfețele de rețea ale ALB-ului se eliberează cu întârziere). Rămân:
- snapshot-ul final RDS `aradex-final`;
- bucket-ul de state, pe care îl ștergi la final cu `terraform -chdir=terraform/bootstrap destroy`, după ce îl golești.

### Variabile (`terraform/terraform.tfvars`, fără secrete)
| Variabilă | Implicit | Ce face |
|---|---|---|
| `domain_name` | `""` | domeniul; până e setat, HTTPS-ul, serviciul web, utilizatorul GitHub pentru FE și parametrul SSM nu se creează |
| `api_desired_count` | `0` | 0 până există o imagine în ECR `aradex-api`, apoi 1 |
| `web_desired_count` | `0` | 0 până există o imagine în ECR `aradex-web`, apoi 1 |
| `anthropic_model` | `claude-haiku-5-5` | modelul Claude pentru chat și planificator (`ANTHROPIC_MODEL`) |
| `alert_email` | — | în `local.auto.tfvars`; alertele și bugetul |
| `github_owner`, `backend_repo`, `frontend_repo`, `branch` | `HACK4ARAD`, `AradEx-Backend`, `AradEx-Frontend`, `main` | singurele repo-uri și branch care pot asuma rolurile OIDC |

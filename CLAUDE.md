# AradEx-Infrastructure

Doar P1 (Zoltan) modifică acest repo (T00, T04, T16a). Regulile echipei: `../AradEx-Plan/CLAUDE.md`. Producția e pe AWS (`eu-north-1`), descrisă în Terraform în `terraform/`; runbook-ul e în `README.md`, designul în `docs/superpowers/specs/`. **Orice `terraform apply`/`destroy` și orice acțiune în contul AWS sau în setările GitHub se fac doar cu aprobarea lui Zoltan, după ce a văzut `terraform plan`.** **Niciun secret în repo**: cheile stau în Secrets Manager (AWS) și în secretele repo-urilor GitHub (`scripts/github-keys.sh`), iar `terraform/local.auto.tfvars` e ignorat de git. Testele: `terraform -chdir=terraform test` (fără credențiale).
## Commit-uri
Mesaje scurte în engleză (`feat(events): list + filters`). **Fără `Co-Authored-By:` și fără „Generated with Claude Code”** — hook-ul din `.githooks` le scoate (`git config core.hooksPath .githooks`). Branch `feat/Txx-...` din `origin/main`, PR în acest repo; regulile complete: `../AradEx-Plan/CLAUDE.md`.

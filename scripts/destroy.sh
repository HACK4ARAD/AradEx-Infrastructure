#!/usr/bin/env bash
# Șterge TOATĂ infrastructura AradExperience din AWS (în afară de snapshot-ul final RDS și bucket-ul de state).
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aws-toolkit}" AWS_REGION=eu-north-1
cd "$(dirname "$0")/../terraform"

echo "Asta șterge VPC-ul, baza de date (cu snapshot final aradex-final), API-ul, PWA-ul, ALB-ul, utilizatorii GitHub Actions și alertele."
read -rp "Scrie DESTROY ca să continui: " answer
if [[ "$answer" != "DESTROY" ]]; then
  echo "Anulat."
  exit 1
fi

terraform destroy

echo
echo "Snapshot-ul final rămas (îl ștergi cu aws rds delete-db-snapshot dacă nu-l mai vrei):"
aws rds describe-db-snapshots --db-snapshot-identifier aradex-final \
  --query 'DBSnapshots[].{id:DBSnapshotIdentifier,status:Status,created:SnapshotCreateTime}' --output table || true
echo "Bucket-ul de state rămâne; îl ștergi la final cu: terraform -chdir=terraform/bootstrap destroy (după ce îl golești)."

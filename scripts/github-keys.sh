#!/usr/bin/env bash
# Creează o cheie nouă pentru utilizatorul IAM de deploy și o pune DIRECT în secretele repo-ului GitHub
# (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY). Cheia nu apare pe ecran, în fișiere sau în Terraform.
# Cheile vechi ale utilizatorului se șterg (rotație). Folosire: ./scripts/github-keys.sh api|web
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aws-toolkit}" AWS_REGION=eu-north-1

case "${1:-}" in
  api) user=aradex-gha-backend repo=HACK4ARAD/AradEx-Backend ;;
  web) user=aradex-gha-frontend repo=HACK4ARAD/AradEx-Frontend ;;
  *)
    echo "Folosire: $0 api|web" >&2
    exit 2
    ;;
esac

# Verificăm accesul la GitHub ÎNAINTE de a crea cheia.
if ! gh repo view "$repo" --json name >/dev/null 2>&1; then
  echo "gh nu vede $repo. Rulează 'gh auth login' (sau 'gh auth refresh') și autorizează organizația HACK4ARAD, apoi reîncearcă." >&2
  exit 1
fi
aws iam get-user --user-name "$user" >/dev/null

old_keys=$(aws iam list-access-keys --user-name "$user" --query 'AccessKeyMetadata[].AccessKeyId' --output text)

read -r key_id key_secret < <(aws iam create-access-key --user-name "$user" \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text)
# Dacă scrierea în GitHub pică, ștergem cheia nouă ca să nu rămână una nefolosită.
trap 'aws iam delete-access-key --user-name "$user" --access-key-id "$key_id" >/dev/null 2>&1 || true; echo "Eșec: cheia nouă a fost ștearsă." >&2' ERR

printf '%s' "$key_id" | gh secret set AWS_ACCESS_KEY_ID -R "$repo"
printf '%s' "$key_secret" | gh secret set AWS_SECRET_ACCESS_KEY -R "$repo"
unset key_secret
trap - ERR

for k in $old_keys; do
  aws iam delete-access-key --user-name "$user" --access-key-id "$k"
done
echo "Secretele AWS din $repo sunt setate (utilizator $user). Cheile vechi: șterse."

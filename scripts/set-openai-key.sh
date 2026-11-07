#!/usr/bin/env bash
# Pune cheia OpenAI în Secrets Manager (aradex/openai) și repornește API-ul ca s-o citească.
# Cheia se tastează (nu apare pe ecran, în argumente sau în istoricul shell-ului).
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aws-toolkit}" AWS_REGION=eu-north-1

read -rsp "OPENAI_API_KEY: " KEY
echo
if [[ -z "$KEY" ]]; then
  echo "Cheie goală, nu schimb nimic." >&2
  exit 1
fi

aws secretsmanager put-secret-value --secret-id aradex/openai --secret-string "$KEY" >/dev/null
unset KEY
echo "Cheia e salvată în aradex/openai."

aws ecs update-service --cluster aradex --service aradex-api --force-new-deployment >/dev/null
echo "API-ul repornește (1-3 minute) ca să citească noua cheie."

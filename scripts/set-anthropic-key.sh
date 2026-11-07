#!/usr/bin/env bash
# Pune cheia Claude API (Anthropic) în Secrets Manager (aradex/anthropic) și repornește API-ul ca s-o citească
# (ajunge în container ca ANTHROPIC_API_KEY). Cheia se tastează: nu apare pe ecran, în argumente sau în istoric.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aws-toolkit}" AWS_REGION=eu-north-1

read -rsp "ANTHROPIC_API_KEY: " KEY
echo
if [[ -z "$KEY" ]]; then
  echo "Cheie goală, nu schimb nimic." >&2
  exit 1
fi

aws secretsmanager put-secret-value --secret-id aradex/anthropic --secret-string "$KEY" >/dev/null
unset KEY
echo "Cheia e salvată în aradex/anthropic."

aws ecs update-service --cluster aradex --service aradex-api --force-new-deployment >/dev/null
echo "API-ul repornește (1-3 minute) ca să citească noua cheie."

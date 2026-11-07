#!/usr/bin/env bash
# Pune cheia Google Places API (New) în Secrets Manager (aradex/google-places) și repornește API-ul ca s-o citească
# (ajunge în container ca GOOGLE_PLACES_API_KEY; o folosește backend-ul în T17). Cheia se tastează: nu apare pe ecran.
# Cheia se creează în Google Cloud: doar „Places API (New)”, restricționată la acest API, cu cotă pe zi.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aws-toolkit}" AWS_REGION=eu-north-1

read -rsp "GOOGLE_PLACES_API_KEY: " KEY
echo
if [[ -z "$KEY" ]]; then
  echo "Cheie goală, nu schimb nimic." >&2
  exit 1
fi

aws secretsmanager put-secret-value --secret-id aradex/google-places --secret-string "$KEY" >/dev/null
unset KEY
echo "Cheia e salvată în aradex/google-places."

aws ecs update-service --cluster aradex --service aradex-api --force-new-deployment >/dev/null
echo "API-ul repornește (1-3 minute) ca să citească noua cheie."

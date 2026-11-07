#!/usr/bin/env bash
# T21: pune cheile Twilio Verify în Secrets Manager (aradex/twilio) și repornește API-ul ca să le citească
# (ajung în container ca TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_VERIFY_SERVICE_SID). Se tastează: nu apar pe ecran.
# Unde le găsești: console.twilio.com → Account Info (Account SID, Auth Token) și Verify → Services (Service SID, VA…).
# Cont trial: SMS-ul ajunge doar la numerele verificate în Twilio (Phone Numbers → Verified Caller IDs).
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aws-toolkit}" AWS_REGION=eu-north-1

read -rsp "TWILIO_ACCOUNT_SID (AC…): " SID; echo
read -rsp "TWILIO_AUTH_TOKEN: " TOKEN; echo
read -rsp "TWILIO_VERIFY_SERVICE_SID (VA…): " SERVICE; echo
if [[ -z "$SID" || -z "$TOKEN" || -z "$SERVICE" ]]; then
  echo "Una dintre valori e goală, nu schimb nimic." >&2
  exit 1
fi
if [[ "$SID" != AC* || "$SERVICE" != VA* ]]; then
  echo "Account SID începe cu AC, Verify Service SID cu VA. Verifică valorile." >&2
  exit 1
fi

# JSON-ul se construiește cu python ca valorile să nu apară în argumentele vreunui proces
SECRET=$(SID="$SID" TOKEN="$TOKEN" SERVICE="$SERVICE" python3 -c 'import json,os;print(json.dumps({"account_sid":os.environ["SID"],"auth_token":os.environ["TOKEN"],"verify_service_sid":os.environ["SERVICE"]}))')
unset SID TOKEN SERVICE
aws secretsmanager put-secret-value --secret-id aradex/twilio --secret-string file:///dev/stdin <<<"$SECRET" >/dev/null
unset SECRET
echo "Cheile sunt salvate în aradex/twilio."

aws ecs update-service --cluster aradex --service aradex-api --force-new-deployment >/dev/null
echo "API-ul repornește (1-3 minute) ca să citească noile chei."

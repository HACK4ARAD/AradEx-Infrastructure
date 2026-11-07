#!/usr/bin/env bash
# T25: pune cheile Stripe de TEST în Secrets Manager (aradex/stripe) și repornește API-ul ca să le citească (ajung în container ca
# STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY, STRIPE_WEBHOOK_SECRET). Se tastează: nu apar pe ecran.
# Unde le găsești: dashboard.stripe.com → comutatorul „Test mode” pornit → Developers → API keys (pk_test_…, sk_test_…);
# Developers → Webhooks → Add endpoint https://aradexperience.site/api/v1/payments/stripe/webhook, evenimentul
# payment_intent.succeeded → „Signing secret” (whsec_…). Cheile live (sk_live_/pk_live_) sunt refuzate aici și de backend.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aws-toolkit}" AWS_REGION=eu-north-1

read -rsp "STRIPE_SECRET_KEY (sk_test_…): " SK; echo
read -rsp "STRIPE_PUBLISHABLE_KEY (pk_test_…): " PK; echo
read -rsp "STRIPE_WEBHOOK_SECRET (whsec_…, Enter dacă nu ai încă webhook): " WH; echo
if [[ "$SK" != sk_test_* || "$PK" != pk_test_* ]]; then
  echo "Doar chei de TEST: secret_key începe cu sk_test_, publishable_key cu pk_test_. Nu schimb nimic." >&2
  exit 1
fi
if [[ -n "$WH" && "$WH" != whsec_* ]]; then
  echo "Webhook signing secret începe cu whsec_. Nu schimb nimic." >&2
  exit 1
fi

# JSON-ul se construiește cu python ca valorile să nu apară în argumentele vreunui proces
SECRET=$(SK="$SK" PK="$PK" WH="$WH" python3 -c 'import json,os;print(json.dumps({"secret_key":os.environ["SK"],"publishable_key":os.environ["PK"],"webhook_secret":os.environ["WH"]}))')
unset SK PK WH
aws secretsmanager put-secret-value --secret-id aradex/stripe --secret-string file:///dev/stdin <<<"$SECRET" >/dev/null
unset SECRET
echo "Cheile sunt salvate în aradex/stripe."

aws ecs update-service --cluster aradex --service aradex-api --force-new-deployment >/dev/null
echo "API-ul repornește (1-3 minute) ca să citească noile chei."

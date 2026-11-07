#!/usr/bin/env bash
# Pornește manual workflow-ul de deploy din GitHub Actions: ./scripts/redeploy.sh api|web
set -euo pipefail

case "${1:-}" in
  api) repo=HACK4ARAD/AradEx-Backend ;;
  web) repo=HACK4ARAD/AradEx-Frontend ;;
  *)
    echo "Folosire: $0 api|web" >&2
    exit 2
    ;;
esac

gh workflow run deploy.yml -R "$repo" --ref main
echo "Pornit deploy.yml în $repo. Urmărește: gh run watch -R $repo  (sau https://github.com/$repo/actions)"

#!/usr/bin/env bash
# Repornește manual un pipeline: ./scripts/redeploy.sh api|web
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-aws-toolkit}" AWS_REGION=eu-north-1

case "${1:-}" in
  api) pipeline=aradex-backend ;;
  web) pipeline=aradex-frontend ;;
  *)
    echo "Folosire: $0 api|web" >&2
    exit 2
    ;;
esac

id=$(aws codepipeline start-pipeline-execution --name "$pipeline" --query pipelineExecutionId --output text)
echo "Pornit $pipeline: $id"
echo "Urmărește: https://eu-north-1.console.aws.amazon.com/codesuite/codepipeline/pipelines/$pipeline/view"

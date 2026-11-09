#!/usr/bin/env bash
# Charge .env et définit les helpers communs. À "sourcer" : source scripts/00_env.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.env" ] || { echo "Copie _env.example vers .env d'abord"; exit 1; }
set -a; source "$ROOT/.env"; set +a

export AWS_PAGER=""
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
ACCOUNT_ID="000000000000"
BUCKET="shorts-trend-snapshots"
TABLE="ShortsTrendState"
TOPIC_NAME="shorts-trend-alerts"
SNAP_QUEUE="shorts-snapshot-queue"
SNAP_DLQ="shorts-snapshot-dlq"
NOTIF_QUEUE="shorts-notifications-queue"
ROLE_NAME="shorts-lambda-role"
RULE_NAME="shorts-trend-schedule"
API_KEY_PARAM="/shorts-trend/youtube-api-key"

aws_() { aws --endpoint-url "$AWS_ENDPOINT" "$@"; }
sqs_url() { aws_ sqs get-queue-url --queue-name "$1" --query QueueUrl --output text; }
sqs_arn() { aws_ sqs get-queue-attributes --queue-url "$(sqs_url "$1")" --attribute-names QueueArn --query Attributes.QueueArn --output text; }

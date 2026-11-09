#!/usr/bin/env bash
# Étape 1 : infrastructure de base (S3, DynamoDB, SQS, SNS, SSM, IAM)
source "$(dirname "$0")/00_env.sh"

echo "→ Vérification de Floci"
curl -fsS "$AWS_ENDPOINT/_floci/health" >/dev/null || { echo "Floci ne répond pas (docker compose up -d)"; exit 1; }

echo "→ S3"
aws_ s3api create-bucket --bucket "$BUCKET" >/dev/null 2>&1 || true

echo "→ DynamoDB"
aws_ dynamodb create-table --table-name "$TABLE" \
  --attribute-definitions AttributeName=pk,AttributeType=S \
  --key-schema AttributeName=pk,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST >/dev/null 2>&1 || true
aws_ dynamodb update-time-to-live --table-name "$TABLE" \
  --time-to-live-specification Enabled=true,AttributeName=ttl >/dev/null 2>&1 || true

echo "→ SQS (DLQ + file de snapshots + file de notifications)"
aws_ sqs create-queue --queue-name "$SNAP_DLQ" >/dev/null
DLQ_ARN="$(sqs_arn "$SNAP_DLQ")"
aws_ sqs create-queue --queue-name "$SNAP_QUEUE" \
  --attributes "{\"VisibilityTimeout\":\"120\",\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}" >/dev/null
aws_ sqs create-queue --queue-name "$NOTIF_QUEUE" >/dev/null

echo "→ SNS + abonnement de la file de notifications"
TOPIC_ARN="$(aws_ sns create-topic --name "$TOPIC_NAME" --query TopicArn --output text)"
aws_ sns subscribe --topic-arn "$TOPIC_ARN" --protocol sqs \
  --notification-endpoint "$(sqs_arn "$NOTIF_QUEUE")" >/dev/null

echo "→ SSM Parameter Store (clé YouTube)"
aws_ ssm put-parameter --name "$API_KEY_PARAM" --value "$YOUTUBE_API_KEY" \
  --type SecureString --overwrite >/dev/null

echo "→ IAM (rôle Lambda)"
aws_ iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document '{
  "Version":"2012-10-17",
  "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
}' >/dev/null 2>&1 || true

echo "✔ Infra prête. TOPIC_ARN=$TOPIC_ARN"

#!/usr/bin/env bash
# Étape 3 : test de bout en bout (mode MOCK recommandé : YOUTUBE_API_KEY=MOCK)
source "$(dirname "$0")/00_env.sh"

run_collector() {  # $1 = seed
  aws_ lambda invoke --function-name shorts-collector \
    --cli-binary-format raw-in-base64-out \
    --payload "{\"mock_seed\": $1}" "$ROOT/build/out_$1.json" >/dev/null
  echo "  collector(seed=$1) → $(cat "$ROOT/build/out_$1.json")"
}

echo "→ Run 1 (état initial : tout est NEW_ENTRY dans le top ${TOP_N_ALERT})"
run_collector 1
sleep 8
echo "→ Run 2 (classement différent : RANK_UP attendus, cooldown appliqué aux autres)"
run_collector 2
sleep 8

echo "→ Notifications reçues dans ${NOTIF_QUEUE}"
aws_ sqs receive-message --queue-url "$(sqs_url "$NOTIF_QUEUE")" \
  --max-number-of-messages 10 --wait-time-seconds 3 --query 'Messages[].Body' --output text | head -c 3000
echo
echo "→ Dernières lignes d'état DynamoDB"
aws_ dynamodb scan --table-name "$TABLE" --max-items 5 --output json | head -c 1500
echo
echo "→ DLQ (doit être vide)"
aws_ sqs get-queue-attributes --queue-url "$(sqs_url "$SNAP_DLQ")" \
  --attribute-names ApproximateNumberOfMessages --query Attributes --output text

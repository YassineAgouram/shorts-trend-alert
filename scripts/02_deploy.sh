#!/usr/bin/env bash
# Étape 2 : packaging + déploiement des Lambdas, triggers et planification
source "$(dirname "$0")/00_env.sh"

BUILD="$ROOT/build"; mkdir -p "$BUILD"
ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"
TOPIC_ARN="arn:aws:sns:$AWS_DEFAULT_REGION:$ACCOUNT_ID:$TOPIC_NAME"
RUNTIME="python3.12"

package() {  # $1 = nom du dossier lambdas/<nom> ; handler.py à la racine du zip
  rm -f "$BUILD/$1.zip"
  (cd "$ROOT/lambdas/$1" && python3 -m zipfile -c "$BUILD/$1.zip" handler.py)
}

env_json() {  # K=V K=V ... -> {"Variables":{...}} (gère les virgules dans les valeurs)
  python3 -c 'import json,sys; print(json.dumps({"Variables": dict(a.split("=",1) for a in sys.argv[1:])}))' "$@"
}

deploy() {  # $1 nom, puis K=V ...
  local name="$1"; shift
  local env; env="$(env_json "$@")"
  package "$name"
  if aws_ lambda get-function --function-name "shorts-$name" >/dev/null 2>&1; then
    aws_ lambda update-function-code --function-name "shorts-$name" --zip-file "fileb://$BUILD/$name.zip" >/dev/null
    aws_ lambda update-function-configuration --function-name "shorts-$name" --environment "$env" >/dev/null
  else
    aws_ lambda create-function --function-name "shorts-$name" --runtime "$RUNTIME" \
      --handler handler.handler --role "$ROLE_ARN" --timeout 60 --memory-size 256 \
      --zip-file "fileb://$BUILD/$name.zip" --environment "$env" >/dev/null
  fi
  echo "  ✔ shorts-$name"
}

SNAP_URL_INTERNAL="$(sqs_url "$SNAP_QUEUE" | sed "s#http://[^/]*#$LAMBDA_AWS_ENDPOINT#")"
COMMON=(AWS_ENDPOINT_URL="$LAMBDA_AWS_ENDPOINT" AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test)

echo "→ Déploiement des Lambdas"
deploy collector "${COMMON[@]}" BUCKET="$BUCKET" SNAPSHOT_QUEUE_URL="$SNAP_URL_INTERNAL" REGIONS="$REGIONS" MAX_SHORT_SECONDS="$MAX_SHORT_SECONDS" API_KEY_PARAM="$API_KEY_PARAM"
deploy analyzer "${COMMON[@]}" TABLE="$TABLE" TOPIC_ARN="$TOPIC_ARN" TOP_N_ALERT="$TOP_N_ALERT" RANK_JUMP="$RANK_JUMP" COOLDOWN_MIN="$COOLDOWN_MIN"
deploy notifier TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"

echo "→ SQS → analyzer (event source mapping)"
if [ -z "$(aws_ lambda list-event-source-mappings --function-name shorts-analyzer --query 'EventSourceMappings[0].UUID' --output text | grep -v None || true)" ]; then
  aws_ lambda create-event-source-mapping --function-name shorts-analyzer \
    --event-source-arn "$(sqs_arn "$SNAP_QUEUE")" --batch-size 1 >/dev/null
fi

echo "→ SNS → notifier"
aws_ lambda add-permission --function-name shorts-notifier --statement-id sns-invoke \
  --action lambda:InvokeFunction --principal sns.amazonaws.com --source-arn "$TOPIC_ARN" >/dev/null 2>&1 || true
aws_ sns subscribe --topic-arn "$TOPIC_ARN" --protocol lambda \
  --notification-endpoint "arn:aws:lambda:$AWS_DEFAULT_REGION:$ACCOUNT_ID:function:shorts-notifier" >/dev/null

echo "→ EventBridge : planification du collector ($SCHEDULE_EXPRESSION)"
aws_ events put-rule --name "$RULE_NAME" --schedule-expression "$SCHEDULE_EXPRESSION" >/dev/null
aws_ lambda add-permission --function-name shorts-collector --statement-id events-invoke \
  --action lambda:InvokeFunction --principal events.amazonaws.com >/dev/null 2>&1 || true
aws_ events put-targets --rule "$RULE_NAME" --targets \
  "Id=1,Arn=arn:aws:lambda:$AWS_DEFAULT_REGION:$ACCOUNT_ID:function:shorts-collector" >/dev/null

echo "✔ Déploiement terminé"

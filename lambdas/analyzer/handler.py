"""Analyzer : compare le snapshot au dernier état connu (DynamoDB) et publie
une alerte SNS quand un Short entre dans le top N ou gagne beaucoup de places."""
import json
import os
import time

import boto3

ENDPOINT = os.environ.get("AWS_ENDPOINT_URL")
TABLE = os.environ["TABLE"]
TOPIC_ARN = os.environ["TOPIC_ARN"]
TOP_N = int(os.environ.get("TOP_N_ALERT", "20"))
RANK_JUMP = int(os.environ.get("RANK_JUMP", "10"))
COOLDOWN_S = int(os.environ.get("COOLDOWN_MIN", "360")) * 60


def kw(name):
    return {"endpoint_url": ENDPOINT} if ENDPOINT else {}


s3 = boto3.client("s3", **kw("s3"))
sns = boto3.client("sns", **kw("sns"))
table = boto3.resource("dynamodb", **kw("dynamodb")).Table(TABLE)


def evaluate(item, prev, now):
    """Retourne le type d'alerte ou None."""
    rank = item["rank"]
    if rank > TOP_N:
        return None
    if prev and now - int(prev.get("notified_at", 0)) < COOLDOWN_S:
        return None
    if not prev:
        return "NEW_ENTRY"
    if int(prev["last_rank"]) - rank >= RANK_JUMP:
        return "RANK_UP"
    return None


def process_snapshot(bucket, key):
    snap = json.loads(s3.get_object(Bucket=bucket, Key=key)["Body"].read())
    now = int(snap["ts"])
    alerts = 0
    for item in snap["items"]:
        pk = f"{item['video_id']}#{item['region']}"
        prev = table.get_item(Key={"pk": pk}).get("Item")
        kind = evaluate(item, prev, now)
        notified_at = int(prev.get("notified_at", 0)) if prev else 0
        if kind:
            msg = {
                "type": kind,
                "video_id": item["video_id"],
                "region": item["region"],
                "title": item["title"],
                "channel": item["channel"],
                "rank": item["rank"],
                "previous_rank": int(prev["last_rank"]) if prev else None,
                "views": item["views"],
                "url": item["url"],
            }
            sns.publish(TopicArn=TOPIC_ARN, Subject=f"Short en tendance ({kind})",
                        Message=json.dumps(msg, ensure_ascii=False))
            notified_at = now
            alerts += 1
        table.put_item(Item={
            "pk": pk,
            "last_rank": item["rank"],
            "best_rank": min(item["rank"], int(prev["best_rank"])) if prev else item["rank"],
            "first_seen": int(prev["first_seen"]) if prev else now,
            "last_seen": now,
            "views": item["views"],
            "title": item["title"],
            "notified_at": notified_at,
            "ttl": now + 7 * 86400,
        })
    return alerts


def handler(event, context):
    total = 0
    for rec in event.get("Records", []):
        body = json.loads(rec["body"])
        total += process_snapshot(body["bucket"], body["key"])
    print(f"alerts published: {total}")
    return {"alerts": total}

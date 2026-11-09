"""Collector : récupère les vidéos "mostPopular" de YouTube, garde les Shorts,
écrit un snapshot dans S3 et prévient l'analyseur via SQS."""
import json
import os
import random
import re
import time
import urllib.parse
import urllib.request

import boto3

ENDPOINT = os.environ.get("AWS_ENDPOINT_URL")
BUCKET = os.environ["BUCKET"]
QUEUE_URL = os.environ["SNAPSHOT_QUEUE_URL"]
REGIONS = os.environ.get("REGIONS", "US").split(",")
MAX_SHORT_SECONDS = int(os.environ.get("MAX_SHORT_SECONDS", "180"))
API_KEY_PARAM = os.environ.get("API_KEY_PARAM", "/shorts-trend/youtube-api-key")


def client(name):
    return boto3.client(name, endpoint_url=ENDPOINT) if ENDPOINT else boto3.client(name)


s3, sqs, ssm = client("s3"), client("sqs"), client("ssm")
_api_key = None


def get_api_key():
    global _api_key
    if _api_key is None:
        _api_key = ssm.get_parameter(Name=API_KEY_PARAM, WithDecryption=True)["Parameter"]["Value"]
    return _api_key


def iso_duration_to_seconds(d):
    m = re.fullmatch(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", d or "")
    if not m:
        return 10**9
    h, mi, s = (int(x or 0) for x in m.groups())
    return h * 3600 + mi * 60 + s


def fetch_region(region, key):
    params = {
        "part": "snippet,contentDetails,statistics",
        "chart": "mostPopular",
        "regionCode": region,
        "maxResults": 50,
        "key": key,
    }
    url = "https://www.googleapis.com/youtube/v3/videos?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=20) as r:
        data = json.load(r)
    items = []
    for rank, it in enumerate(data.get("items", []), start=1):
        secs = iso_duration_to_seconds(it["contentDetails"]["duration"])
        if secs > MAX_SHORT_SECONDS:  # heuristique "Short"
            continue
        items.append({
            "video_id": it["id"],
            "region": region,
            "rank": rank,  # rang dans le classement mostPopular de la région
            "title": it["snippet"]["title"],
            "channel": it["snippet"]["channelTitle"],
            "views": int(it["statistics"].get("viewCount", 0)),
            "duration_s": secs,
            "url": f"https://www.youtube.com/shorts/{it['id']}",
        })
    return items


def mock_region(region, seed):
    rng = random.Random(f"{region}-{seed}")
    ids = list(range(1, 31))
    rng.shuffle(ids)
    return [{
        "video_id": f"mock{n:03d}",
        "region": region,
        "rank": rank,
        "title": f"Mock short #{n}",
        "channel": "Mock Channel",
        "views": rng.randint(10_000, 5_000_000),
        "duration_s": 30,
        "url": f"https://www.youtube.com/shorts/mock{n:03d}",
    } for rank, n in enumerate(ids, start=1)]


def handler(event, context):
    key = get_api_key()
    ts = int(time.time())
    items = []
    for region in REGIONS:
        if key == "MOCK":
            seed = (event or {}).get("mock_seed", ts // 60)
            items += mock_region(region, seed)
        else:
            items += fetch_region(region, key)

    s3_key = f"snapshots/{ts}.json"
    s3.put_object(Bucket=BUCKET, Key=s3_key,
                  Body=json.dumps({"ts": ts, "items": items}).encode(),
                  ContentType="application/json")
    sqs.send_message(QueueUrl=QUEUE_URL,
                     MessageBody=json.dumps({"bucket": BUCKET, "key": s3_key, "ts": ts}))
    print(f"snapshot {s3_key}: {len(items)} shorts")
    return {"snapshot": s3_key, "count": len(items)}

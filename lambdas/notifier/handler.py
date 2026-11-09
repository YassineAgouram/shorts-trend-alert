"""Notifier : reçoit les messages SNS et envoie sur Telegram (sinon log)."""
import json
import os
import urllib.parse
import urllib.request

TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")


def format_message(m):
    icon = "🆕" if m["type"] == "NEW_ENTRY" else "📈"
    prev = f" (avant : #{m['previous_rank']})" if m.get("previous_rank") else ""
    return (f"{icon} {m['title']}\n"
            f"Chaîne : {m['channel']} | Région : {m['region']}\n"
            f"Rang : #{m['rank']}{prev} | Vues : {m['views']:,}\n"
            f"{m['url']}")


def send_telegram(text):
    url = f"https://api.telegram.org/bot{TOKEN}/sendMessage"
    data = urllib.parse.urlencode({"chat_id": CHAT_ID, "text": text}).encode()
    urllib.request.urlopen(urllib.request.Request(url, data=data), timeout=10).read()


def handler(event, context):
    for rec in event.get("Records", []):
        m = json.loads(rec["Sns"]["Message"])
        text = format_message(m)
        print("NOTIFICATION:\n" + text)
        if TOKEN and CHAT_ID:
            send_telegram(text)
    return {"ok": True}

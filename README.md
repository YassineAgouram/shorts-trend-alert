# Shorts Trend Alert (Floci / AWS local)

Alerte quand un YouTube Short (« reel ») monte dans les tendances.

## Architecture

```
EventBridge (rate 15 min)
        │
        ▼
Lambda collector ──► SSM (clé API YouTube)
   │  YouTube Data API v3 : videos.list chart=mostPopular, par région
   │  filtre Shorts (durée ≤ MAX_SHORT_SECONDS)
   ├──► S3  snapshots/<ts>.json        (historique brut)
   └──► SQS shorts-snapshot-queue ──(DLQ après 3 échecs)
                │
                ▼
        Lambda analyzer ◄──► DynamoDB ShortsTrendState (dernier rang, best rank, cooldown, TTL 7 j)
                │  règles : NEW_ENTRY (entrée dans le top N) | RANK_UP (≥ RANK_JUMP places) | cooldown
                ▼
        SNS shorts-trend-alerts
          ├──► Lambda notifier ──► Telegram (ou simple log)
          └──► SQS shorts-notifications-queue (pour vérifier en local)
```

## Prérequis
Docker, AWS CLI v2, Python 3, curl.

## Étapes
1. `cp _env.example .env` (laisser `YOUTUBE_API_KEY=MOCK` pour tester sans clé)
2. `docker compose up -d` puis `curl localhost:4566/_floci/health`
3. `bash scripts/01_infra.sh`   # S3, DynamoDB, SQS, SNS, SSM, IAM
4. `bash scripts/02_deploy.sh`  # Lambdas + triggers + EventBridge
5. `bash scripts/03_test.sh`    # 2 runs mock, lecture des notifications
   (ou `bash scripts/run_all.sh` pour tout enchaîner)
6. Logs : `aws --endpoint-url http://localhost:4566 logs tail /aws/lambda/shorts-notifier`
   (ou `docker logs`) si les logs CloudWatch sont supportés par votre version de Floci.

## Passer en réel
- Créer une clé YouTube Data API v3 (Google Cloud Console), mettre-la dans `.env`
  (`YOUTUBE_API_KEY=...`) puis relancer `01_infra.sh` (met à jour SSM) et `02_deploy.sh`.
- Telegram : créer un bot via @BotFather, renseigner `TELEGRAM_BOT_TOKEN` et `TELEGRAM_CHAT_ID`.
- Les conteneurs Lambda doivent avoir un accès internet sortant.

## Limites à connaître
- YouTube n'expose pas d'API « trending Shorts » : on utilise `mostPopular` et on filtre par durée.
  Les Shorts y sont peu nombreux ; pour plus de couverture, ajouter des `videoCategoryId`
  (ex. 10 Musique, 23 Comédie, 24 Divertissement) ou compléter avec `search.list` (coût de quota élevé).
- Quota API : 1 unité par appel `videos.list`. 3 régions × 96 runs/jour ≈ 288 unités (quota 10 000/jour).

## Dépannage
- Lambda ne joint pas Floci : ajuster `LAMBDA_AWS_ENDPOINT` (Linux : `http://host.docker.internal:4566`
  grâce à `extra_hosts`, sinon l'IP du bridge Docker, ex. `http://172.17.0.1:4566`).
- Le planificateur ne déclenche rien : appelez le collector à la main (`03_test.sh`) ; la logique en aval est identique.
- Vérifier que votre version de Floci supporte SNS→Lambda ; sinon la file `shorts-notifications-queue` reste la sortie de référence.

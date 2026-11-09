#!/usr/bin/env bash
# Tout enchaîner : infra → déploiement → test
set -euo pipefail
cd "$(dirname "$0")"
./01_infra.sh && ./02_deploy.sh && ./03_test.sh

#!/usr/bin/env bash
# ==============================================================================
# Rollback Script for Chatwoot on Hostinger VPS
# ==============================================================================
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <tag>"
  echo "Example: $0 sha-a1b2c3d"
  if [ -f "${HOME}/backups/last-image.txt" ]; then
    echo "Last recorded image before update:"
    cat "${HOME}/backups/last-image.txt"
  fi
  exit 1
fi

export MMOCHAT_TAG="$1"

echo "===> 1. Pulling rollback image (tag: ${MMOCHAT_TAG})..."
docker compose -f docker-compose.traefik.yaml pull rails sidekiq

echo "===> 2. Restarting Chatwoot services with rollback tag (without running migrations)..."
docker compose -f docker-compose.traefik.yaml up -d --remove-orphans

echo "===================================================================="
echo " ROLLBACK COMPLETE to tag: ${MMOCHAT_TAG}"
echo " NOTE: If the rolled-back release included database migrations,"
echo " you may also need to restore the pre-migration database backup:"
echo "   gunzip -c ~/backups/<backup-file>.sql.gz | docker exec -i chatwoot_postgres psql -U postgres chatwoot_production"
echo "===================================================================="

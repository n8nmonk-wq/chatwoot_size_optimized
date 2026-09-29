#!/usr/bin/env bash
# ==============================================================================
# Rollback Script for Chatwoot on Hostinger VPS
# ==============================================================================
set -euo pipefail

MMOCHAT_TAG="${1:-previous}"
export MMOCHAT_TAG

IMAGE_NAME="ghcr.io/n8nmonk-wq/chatwoot_size_optimized:${MMOCHAT_TAG}"

echo "===> Rolling back Chatwoot to tag: ${MMOCHAT_TAG}..."

# Pull only when image tag is not present locally (e.g. :previous is tagged locally)
if docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
  echo "===> Image ${IMAGE_NAME} already exists locally; skipping pull."
else
  echo "===> Pulling ${IMAGE_NAME}..."
  docker compose -f docker-compose.traefik.yaml pull rails sidekiq
fi

echo "===> Restarting Chatwoot services with rollback tag ${MMOCHAT_TAG} (without migrating)..."
docker compose -f docker-compose.traefik.yaml up -d --remove-orphans

echo "===================================================================="
echo " ROLLBACK COMPLETE to tag: ${MMOCHAT_TAG}"
echo " NOTE: If the rolled-back release included database migrations,"
echo " stop rails and sidekiq before restoring the database backup:"
echo "   1. docker compose -f docker-compose.traefik.yaml stop rails sidekiq"
echo "   2. gunzip -c ~/backups/<backup-file>.sql.gz | docker exec -i chatwoot_postgres psql -U postgres chatwoot_production"
echo "   3. docker compose -f docker-compose.traefik.yaml start rails sidekiq"
echo "===================================================================="

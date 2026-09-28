#!/usr/bin/env bash
# ==============================================================================
# One-Command Update Script for Chatwoot on Hostinger VPS
# ==============================================================================
set -euo pipefail

MMOCHAT_TAG="${1:-latest}"
export MMOCHAT_TAG

BACKUP_DIR="${HOME}/backups"
BACKUP_FILE="${BACKUP_DIR}/chatwoot-$(date +%F-%H%M).sql.gz"

echo "===> 1. Pulling latest code from GitHub..."
git pull origin main

echo "===> 2. Creating pre-migration database backup and recording running image..."
mkdir -p "${BACKUP_DIR}"

# Record currently running image before pulling new one
docker inspect --format='{{.Config.Image}} (ID: {{.Image}})' chatwoot_rails > "${BACKUP_DIR}/last-image.txt" 2>/dev/null || true

# Stream database dump through gzip
docker exec chatwoot_postgres pg_dump -U postgres chatwoot_production | gzip > "${BACKUP_FILE}"

# Abort deploy if dump failed or file is empty / corrupt
if [ ! -s "${BACKUP_FILE}" ]; then
  echo "ERROR: Database backup failed or produced an empty file (${BACKUP_FILE}). Aborting deploy!"
  rm -f "${BACKUP_FILE}"
  exit 1
fi

# Keep newest 7 dumps
find "${BACKUP_DIR}" -maxdepth 1 -name "chatwoot-*.sql.gz" -type f | sort -r | tail -n +8 | while IFS= read -r old_file; do
  echo "Pruning old backup: ${old_file}"
  rm -f "${old_file}"
done

echo "===> Backup saved: ${BACKUP_FILE}"
echo "===> REMINDER: Copy this backup off-site to your local machine, e.g.:"
echo "     scp root@<VPS_IP>:${BACKUP_FILE} ."

echo "===> 3. Pulling prebuilt MMOChat Docker image (tag: ${MMOCHAT_TAG}) from GitHub Container Registry..."
docker compose -f docker-compose.traefik.yaml pull rails sidekiq

echo "===> 4. Running database migrations..."
docker compose -f docker-compose.traefik.yaml run --rm rails bundle exec rails db:migrate

echo "===> 5. Restarting Chatwoot services..."
docker compose -f docker-compose.traefik.yaml up -d --remove-orphans

echo "===================================================================="
echo " UPDATE COMPLETE (tag: ${MMOCHAT_TAG})!"
echo " Dashboard: https://mmochat.srv1275499.hstgr.cloud"
echo " Client Login: https://mmochat.srv1275499.hstgr.cloud/client/login"
echo "===================================================================="

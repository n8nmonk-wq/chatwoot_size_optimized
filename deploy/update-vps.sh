#!/usr/bin/env bash
# ==============================================================================
# One-Command Update Script for Chatwoot on Hostinger VPS
# ==============================================================================
set -e

echo "===> 1. Pulling latest code from GitHub..."
git pull origin main

echo "===> 2. Building updated Chatwoot Docker image..."
docker compose -f docker-compose.traefik.yaml build rails sidekiq

echo "===> 3. Restarting Chatwoot services..."
docker compose -f docker-compose.traefik.yaml up -d --remove-orphans

echo "===================================================================="
echo " UPDATE COMPLETE!"
echo " Please hard-refresh your browser: Ctrl + Shift + R"
echo " Dashboard: https://chatwoot.srv1275499.hstgr.cloud"
echo "===================================================================="

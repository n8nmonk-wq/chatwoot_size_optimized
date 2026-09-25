#!/usr/bin/env bash
# ==============================================================================
# One-Command Update Script for Chatwoot on Hostinger VPS
# ==============================================================================
set -e

echo "===> 1. Pulling latest code from GitHub..."
git pull origin main

echo "===> 2. Pulling prebuilt MMOChat Docker image from GitHub Container Registry..."
docker compose -f docker-compose.traefik.yaml pull rails sidekiq

echo "===> 3. Running database migrations..."
docker compose -f docker-compose.traefik.yaml run --rm rails bundle exec rails db:migrate

echo "===> 4. Restarting Chatwoot services..."
docker compose -f docker-compose.traefik.yaml up -d --remove-orphans

echo "===================================================================="
echo " UPDATE COMPLETE!"
echo " Dashboard: https://mmochat.srv1275499.hstgr.cloud"
echo " Client Login: https://mmochat.srv1275499.hstgr.cloud/client/login"
echo "===================================================================="

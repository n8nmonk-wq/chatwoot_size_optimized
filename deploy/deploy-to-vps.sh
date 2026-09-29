#!/usr/bin/env bash
# ==============================================================================
# Hostinger VPS Traefik Deployment Script for Chatwoot
# ==============================================================================
set -e

echo "===> 1. Checking 4GB SWAP space..."
if ! grep -q '/swapfile' /etc/fstab; then
  sudo fallocate -l 4G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=4096
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
  sudo sysctl vm.swappiness=10
  echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
  echo "SWAP setup completed."
else
  echo "SWAP already exists."
fi

echo "===> 2. Ensuring directory /root/chatwoot-docker exists..."
mkdir -p /root/chatwoot-docker
cd /root/chatwoot-docker

if [ ! -f .env ]; then
  echo "===> 3. Generating secure .env configuration..."
  SECRET_KEY_BASE=$(openssl rand -hex 64)
  ENC_PRIMARY=$(openssl rand -hex 16)
  ENC_DETERMINISTIC=$(openssl rand -hex 16)
  ENC_SALT=$(openssl rand -hex 16)
  POSTGRES_PASS=$(openssl rand -hex 16)
  REDIS_PASS=$(openssl rand -hex 16)

  cat <<EOF > .env
FRONTEND_URL=https://chatwoot.srv1275499.hstgr.cloud
FORCE_SSL=true
ENABLE_ACCOUNT_SIGNUP=false
DEFAULT_LOCALE=en

SECRET_KEY_BASE=$SECRET_KEY_BASE
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$ENC_PRIMARY
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$ENC_DETERMINISTIC
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$ENC_SALT

WEB_CONCURRENCY=1
RAILS_MAX_THREADS=3
SIDEKIQ_CONCURRENCY=3
LOG_LEVEL=warn
RAILS_ENV=production
NODE_ENV=production
INSTALLATION_ENV=docker

POSTGRES_HOST=postgres
POSTGRES_USERNAME=postgres
POSTGRES_PASSWORD=$POSTGRES_PASS
POSTGRES_DATABASE=chatwoot_production
POSTGRES_STATEMENT_TIMEOUT=14s

REDIS_URL=redis://redis:6379
REDIS_PASSWORD=$REDIS_PASS

ACTIVE_STORAGE_SERVICE=local
EOF
  echo ".env created with secure random keys."
fi

echo "===> 4. Initializing Database Schema..."
docker compose -f docker-compose.traefik.yaml run --rm rails bundle exec rails db:chatwoot_prepare

echo "===> 5. Starting Chatwoot Services with Traefik HTTPS..."
docker compose -f docker-compose.traefik.yaml up -d

echo "===> 6. Creating Initial Super Admin Account..."
docker compose -f docker-compose.traefik.yaml run --rm rails bundle exec rails runner "
SuperAdmin.find_or_create_by!(email: 'n8n.monk@gmail.com') do |admin|
  admin.password = 'ChatwootAdmin2026!'
end
"

echo "===================================================================="
echo " CHATWOOT DEPLOYED SUCCESSFULLY WITH TRAEFIK & AUTOMATIC SSL!"
echo " URL: https://chatwoot.srv1275499.hstgr.cloud"
echo " Admin: n8n.monk@gmail.com"
echo " Password: ChatwootAdmin2026!"
echo "===================================================================="

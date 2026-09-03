#!/usr/bin/env bash
# ==============================================================================
# Hostinger VPS Quick-Setup Script for Chatwoot (Optimized for Low-RAM)
# ==============================================================================
set -e

echo "===> 1. Creating 4GB SWAP space (prevents Out-Of-Memory crashes)..."
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
  echo "SWAP already exists, skipping."
fi

echo "===> 2. Updating packages & installing Docker + Docker Compose..."
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg lsb-release nginx certbot python3-certbot-nginx

# Install Docker if not present
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  sudo usermod -aG docker $USER
  rm get-docker.sh
fi

echo "===> 3. Enabling UFW Firewall..."
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

echo "===> Setup completed successfully!"
echo "Next steps:"
echo "1. Copy .env.production.sample to .env and fill in your passwords and secrets."
echo "2. Run: docker compose -f docker-compose.optimized.yaml run --rm rails bundle exec rails db:chatwoot_prepare"
echo "3. Run: docker compose -f docker-compose.optimized.yaml up -d"
echo "4. Create your super admin user: docker compose -f docker-compose.optimized.yaml run --rm rails bundle exec rails runner 'SuperAdmin.create!(email: \"admin@yourdomain.com\", password: \"YourSecurePassword123!\")'"

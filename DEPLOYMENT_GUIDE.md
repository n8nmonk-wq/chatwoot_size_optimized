# Chatwoot Low-RAM Deployment & WhatsApp Cloud API Guide

This repository has been configured with an **optimized, low-memory production setup** designed specifically for affordable Hostinger VPS instances (2GB to 4GB RAM).

---

## 🚀 Part 1: Quick Deployment on Hostinger VPS

### Step 1: Connect to your Hostinger VPS
Open PowerShell or your terminal and SSH into your VPS:
```bash
ssh root@YOUR_VPS_IP
```

### Step 2: Run the Initial Server Preparation
Clone this repository (or copy the files) to your VPS:
```bash
git clone https://github.com/chatwoot/chatwoot.git /opt/chatwoot
cd /opt/chatwoot
```

Make the setup script executable and run it:
```bash
chmod +x deploy/setup-vps.sh
./deploy/setup-vps.sh
```
*This automatically creates a 4GB SWAP file, installs Docker, Nginx, and Certbot, and configures the firewall.*

---

### Step 3: Configure Environment Variables
Copy the optimized configuration template:
```bash
cp .env.production.sample .env
```

Generate secure secrets on your server using:
```bash
openssl rand -hex 64 # for SECRET_KEY_BASE
openssl rand -hex 16 # for ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
openssl rand -hex 16 # for ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
openssl rand -hex 16 # for ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
openssl rand -hex 16 # for POSTGRES_PASSWORD and REDIS_PASSWORD
```

Edit `.env` and fill in:
- `FRONTEND_URL=https://chat.yourdomain.com`
- Your generated secrets & passwords
- Your Hostinger SMTP email details

---

### Step 4: Initialize the Database and Start Services

Run database creation and migrations:
```bash
docker compose -f docker-compose.optimized.yaml run --rm rails bundle exec rails db:chatwoot_prepare
```

Start Chatwoot containers in the background:
```bash
docker compose -f docker-compose.optimized.yaml up -d
```

Create your Super Admin account:
```bash
docker compose -f docker-compose.optimized.yaml run --rm rails bundle exec rails runner 'SuperAdmin.create!(email: "admin@yourdomain.com", password: "YourSecurePassword123!")'
```

---

### Step 5: Configure Nginx & SSL Certificate

1. Point your domain's **A record** (`chat.yourdomain.com`) to your VPS IP in your DNS provider (Hostinger / Cloudflare / GoDaddy).
2. Copy the Nginx config:
   ```bash
   sudo cp deploy/nginx.conf /etc/nginx/sites-available/chatwoot
   sudo sed -i 's/chat.yourdomain.com/YOUR_ACTUAL_DOMAIN/g' /etc/nginx/sites-available/chatwoot
   sudo ln -s /etc/nginx/sites-available/chatwoot /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl reload nginx
   ```
3. Issue a free SSL certificate with Let's Encrypt:
   ```bash
   sudo certbot --nginx -d YOUR_ACTUAL_DOMAIN
   ```

---

## 📱 Part 2: Setting Up WhatsApp Cloud API for Marketing Messages

To send outbound marketing broadcasts without getting banned:

### 1. Create a Meta Developer App
1. Go to [developers.facebook.com](https://developers.facebook.com) and create a **Business App**.
2. Add the **WhatsApp** product to your app.
3. In **API Setup**, connect your Business Phone Number or use a test number.
4. Obtain:
   - **Phone Number ID**
   - **WhatsApp Business Account ID (WABA ID)**
   - **Permanent Access Token** (generated via *System Users* in Meta Business Settings).

### 2. Connect WhatsApp to Chatwoot
1. Log in to your Chatwoot Dashboard (`https://chat.yourdomain.com`).
2. Go to **Settings** -> **Inboxes** -> **Add Inbox**.
3. Select **WhatsApp** -> choose **WhatsApp Cloud API**.
4. Enter your:
   - Phone Number
   - Phone Number ID
   - Business Account ID (WABA ID)
   - Permanent Access Token
5. Chatwoot will provide a **Webhook Callback URL** and **Verify Token**.
6. Copy these back into your Meta Developer App -> **WhatsApp** -> **Configuration** -> **Webhook**.
7. Subscribe to the `messages` webhook field.

### 3. Creating & Sending Marketing Message Templates
1. Go to **Meta WhatsApp Manager** -> **Message Templates**.
2. Create a template under category **Marketing**.
3. Add your promo text, variables (`{{1}}`, `{{2}}`), image/header, and call-to-action buttons (e.g., *Visit Website*, *Unsubscribe*).
4. Submit for Meta review (usually approved in 1–15 minutes).
5. Once approved, you can trigger these templates from Chatwoot or via Chatwoot campaigns/APIs to initiate conversations without any risk of unofficial number bans!

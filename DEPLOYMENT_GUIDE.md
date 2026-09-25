# MMOChat Hostinger VPS Deployment & Maintenance Guide

MMOChat is a lightweight, low-memory WhatsApp conversation platform customized by Monk Media One, built to run smoothly on budget Hostinger VPS instances (2GB to 4GB RAM) with Traefik SSL reverse proxy.

---

## 🚀 Quick Deployment & Updates on Hostinger VPS

### Location on Server
On the production VPS, the repository is deployed at:
```bash
/root/chatwoot-docker
```

---

### How to Update Production VPS (`deploy/update-vps.sh`)

Whenever updates are pushed to `main` on GitHub, SSH into your Hostinger VPS and execute:

```bash
cd /root/chatwoot-docker
git stash                    # Discards any local untracked file conflicts if present
git pull origin main         # Pulls latest MMOChat code
chmod +x deploy/update-vps.sh
./deploy/update-vps.sh       # Automatically rebuilds images, runs migrations, & restarts
```

#### What `update-vps.sh` does automatically:
1. Builds updated production images with newly compiled frontend assets.
2. Runs database migrations (`docker compose run --rm rails bundle exec rails db:migrate`).
3. Gracefully restarts the Rails web service and Sidekiq worker behind Traefik.
4. Cleans up dangling/unused Docker images to preserve disk space.

---

## 🛠️ Server Environment & Architecture

- **Reverse Proxy**: Traefik (with automated Let's Encrypt SSL/TLS termination).
- **Compose Config**: `docker-compose.traefik.yaml`.
- **Database**: PostgreSQL 16 (persistent volume `postgres_data`).
- **Cache & Jobs**: Redis (persistent volume `redis_data`).
- **Production URL**: `https://chatwoot.srv1275499.hstgr.cloud` (or your mapped custom domain).
- **Client Login URL**: `https://chatwoot.srv1275499.hstgr.cloud/client/login`

---

## 👥 User Roles & Access

| Role | Login Route | Credentials | Capabilities |
|------|------------|-------------|--------------|
| **Admin** | `/app/login` | Email + Password | Full access: manage WhatsApp inboxes, agents, clients, settings. |
| **Agent** | `/app/login` | Email + Password | Full conversation access across assigned inboxes, contacts, CRM. |
| **Client** | `/client/login` | **Username + Password** | Read-only UI access strictly to assigned WhatsApp inbox conversations; reply capability; no access to settings, contacts, or internal reports. |

### Client Management & Passwords
1. Admins create clients in **Settings → Clients** (`/app/accounts/{accountId}/settings/clients`).
2. Each client is assigned a unique username (e.g., `client_acme`) and password.
3. Passwords can **only** be modified by Admins from the Settings → Clients dashboard. Clients cannot reset or change passwords themselves.

---

## 📱 Setting Up WhatsApp Cloud API

MMOChat is streamlined exclusively for WhatsApp Cloud API.

### 1. Meta Developer Setup
1. Visit [Meta for Developers](https://developers.facebook.com) and navigate to your WhatsApp Business App.
2. In **WhatsApp → API Setup**, note:
   - **Phone Number ID**
   - **WhatsApp Business Account ID (WABA ID)**
   - **System User Permanent Access Token**

### 2. Connect WhatsApp in MMOChat
1. Log in to MMOChat as Admin (`https://chatwoot.srv1275499.hstgr.cloud`).
2. Navigate to **Settings → Inboxes → Add Inbox**.
3. Select **WhatsApp** (Cloud API).
4. Enter your Phone Number, Phone Number ID, WABA ID, and Permanent Access Token.
5. Copy the generated **Webhook URL** and **Verify Token** into Meta Developer App (**WhatsApp → Configuration → Webhook**).
6. Subscribe to the `messages` webhook field in Meta.
7. Assign your Agents and Clients to the new WhatsApp Inbox.

---

## 🔍 Useful Diagnostic Commands

Check running containers:
```bash
docker ps
```

View real-time Rails application logs:
```bash
docker compose -f docker-compose.traefik.yaml logs -f rails
```

View real-time Sidekiq worker logs:
```bash
docker compose -f docker-compose.traefik.yaml logs -f sidekiq
```

Open a Rails console:
```bash
docker compose -f docker-compose.traefik.yaml run --rm rails bundle exec rails console
```

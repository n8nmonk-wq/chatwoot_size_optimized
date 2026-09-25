# MMOChat Hostinger VPS Deployment & Maintenance Guide

MMOChat is a lightweight, low-memory WhatsApp conversation platform customized by Monk Media One, built to run smoothly on budget Hostinger VPS instances (2GB to 4GB RAM) with Traefik SSL reverse proxy.

---

## ⚡ Automated CI/CD Architecture (Cloud Prebuilt Images)

To ensure your Hostinger VPS **never crashes or runs out of RAM during builds**, MMOChat uses **GitHub Actions** and **GitHub Container Registry (GHCR)**:

1. **Push Code to `main`**: Whenever you commit and push to `main`, GitHub Actions automatically triggers `.github/workflows/docker-build.yml`.
2. **Cloud Compilation**: GitHub's 16GB RAM cloud runners build the Docker image and precompile the frontend assets.
3. **Registry Publication**: The finished production image is pushed directly to:
   ```
   ghcr.io/n8nmonk-wq/chatwoot_size_optimized:latest
   ```
4. **Fast VPS Pull**: Your VPS doesn't compile a single line of code. It downloads the prebuilt layers in **~20 seconds** and restarts.

---

## 🚀 Future Updates & Deployments (Fast & Incremental)

### Do you have to reinstall or re-download everything for future updates?
**No, never!**

- **Persistent Volumes**: All customer conversations, messages, client logins, WhatsApp tokens, and database records are permanently stored in Docker volumes (`chatwoot_postgres_data`, `chatwoot_redis_data`, `chatwoot_storage_data`). Updating the code never touches or resets your data.
- **Zero VPS Compilation**: Because the image is prebuilt by GitHub Actions, your VPS CPU stays low and your SSH session never disconnects.
- **Automatic Migrations**: Database changes (like adding new columns) are applied automatically without affecting existing tables.

---

### Step 1: One-Time Server Setup for GHCR (Run Once on VPS)
On your Hostinger VPS, log in to GitHub Container Registry so Docker can pull your image:

```bash
echo YOUR_GITHUB_PAT | docker login ghcr.io -u n8nmonk-wq --password-stdin
```
*(You only ever need to run this once on the VPS).*

---

### Step 2: The Single Command for All Future Updates
Whenever new code is pushed and the GitHub Actions build finishes, SSH into your VPS and run:

```bash
cd /root/chatwoot-docker
git stash                    # Discards any local untracked conflicts if present
git pull origin main         # Pulls latest compose & scripts
chmod +x deploy/update-vps.sh
./deploy/update-vps.sh       # Pulls prebuilt image, migrates DB & restarts in ~30s
```

#### What `update-vps.sh` does automatically:
1. Pulls the latest configuration and scripts from `main`.
2. Pulls the latest prebuilt Docker image from `ghcr.io/n8nmonk-wq/chatwoot_size_optimized:latest`.
3. Runs database migrations (`docker compose run --rm rails bundle exec rails db:migrate`).
4. Gracefully restarts the Rails web service and Sidekiq worker behind Traefik.
5. Cleans up old Docker image layers to preserve disk space.

---

## 🌐 How the Domain & Docker Network Routing Works

The MMOChat URL (`chatwoot.srv1275499.hstgr.cloud`) is configured across two specific points:

### 1. External Traefik Router & Docker Network (`docker-compose.traefik.yaml`)
Traefik runs on your Hostinger VPS as a reverse proxy managing incoming HTTP/HTTPS traffic. MMOChat attaches to Traefik via Docker labels and an external Docker network:

```yaml
    networks:
      - chatwoot_internal
      - n8n_default            # Traefik listens on this shared docker bridge network

    labels:
      - "traefik.enable=true"
      # Tells Traefik to match incoming HTTPS requests for this host:
      - "traefik.http.routers.chatwoot.rule=Host(`chatwoot.srv1275499.hstgr.cloud`)"
      - "traefik.http.routers.chatwoot.entrypoints=websecure"
      - "traefik.http.routers.chatwoot.tls.certresolver=mytlschallenge"
      - "traefik.http.services.chatwoot.loadbalancer.server.port=3000"
      - "traefik.docker.network=n8n_default"
```
Because `n8n_default` is marked `external: true`, Traefik automatically discovers the `chatwoot_rails` container, assigns a Let's Encrypt SSL certificate, and routes incoming traffic on port 443 directly to port 3000 inside the container.

### 2. Rails Application URL (`.env`)
Inside `/root/chatwoot-docker/.env`, the base URL is defined:
```bash
FRONTEND_URL=https://chatwoot.srv1275499.hstgr.cloud
```
This tells Rails how to format ActionCable WebSocket connections, webhook delivery URLs, and asset URLs.

### 💡 Switching to a Custom Domain (e.g. `chat.yourdomain.com`)
If you later want to point a custom domain to MMOChat:
1. Point your domain's DNS **A record** to your Hostinger VPS IP.
2. In `/root/chatwoot-docker/docker-compose.traefik.yaml`, update:
   `Host(`chat.yourdomain.com`)`
3. In `/root/chatwoot-docker/.env`, update:
   `FRONTEND_URL=https://chat.yourdomain.com`
4. Run `docker compose -f docker-compose.traefik.yaml up -d rails` — Traefik will automatically issue a new SSL certificate for the new domain!

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

# MMOChat

> **The lean, fast WhatsApp conversation platform by Monk Media One.**

MMOChat is a high-performance, size-optimized fork tailored specifically for agencies and businesses managing customer conversations over the **WhatsApp Cloud API**. Stripped of unnecessary enterprise complexity, third-party bloat, and redundant channels, MMOChat is engineered to run seamlessly on cost-effective VPS environments (2GB–4GB RAM).

---

## ✨ Key Features

### 💬 Focused WhatsApp Cloud API Messaging
- Direct integration with Meta's official WhatsApp Business Cloud API.
- Support for inbound & outbound messages, media, templates, and interactive replies.
- No third-party channel clutter — channel creation is dedicated strictly to WhatsApp.

### 👥 Dedicated "Client" Role with Scoped Views
- **Client Login (`/client/login`)**: Clients log in using **Username + Password** (no email requirement).
- **Scoped Inboxes**: Clients only see conversations from WhatsApp inboxes they have been explicitly assigned to.
- **Reply-Only Permissions**: Clients can read and reply to messages, but cannot start arbitrary new conversations, export contacts, access system settings, or view internal reports.
- **Admin Password Control**: Client passwords can only be created and updated by administrators from the **Settings → Clients** panel.

### ⚡ Ultra-Lean & High Performance
- Over 1,400+ unused enterprise files, heavy integrations (Slack, Shopify, Dialogflow, Linear), and deprecated portal/captain modules removed.
- Fast Docker asset builds and minimal container footprint.
- Traefik SSL reverse proxy with automatic Let's Encrypt certificate issuance.

---

## 🎭 User Roles

| Role | Login URL | Authentication | Scope & Permissions |
|------|-----------|----------------|---------------------|
| **Administrator** | `/app/login` | Email + Password | Full system access: manage WhatsApp inboxes, team agents, client accounts, passwords, and server settings. |
| **Agent** | `/app/login` | Email + Password | Conversation handling across assigned inboxes, contacts management, and customer messaging. |
| **Client** | `/client/login` | **Username + Password** | Clean topbar layout; view and reply exclusively to assigned WhatsApp inbox conversations. |

---

## 🚀 Quick Start & Deployment

For comprehensive deployment instructions on Hostinger VPS, see the [Deployment Guide](./DEPLOYMENT_GUIDE.md).

### Updating the Hostinger VPS

```bash
cd /root/chatwoot-docker
git stash
git pull origin main
chmod +x deploy/update-vps.sh
./deploy/update-vps.sh
```

This single command handles rebuilding assets, applying database migrations, and restarting services without downtime.

---

## 📄 Documentation

- [Deployment Guide](./DEPLOYMENT_GUIDE.md) — VPS server setup, Traefik SSL configuration, and WhatsApp Cloud API webhook instructions.
- [Implementation & Architecture Plan](./PLAN_CLIENT_VIEW.md) — Architectural breakdown of the client role, database migrations, and frontend route guard design.

---

## 🛡️ License

Released under the [MIT License](./LICENSE). MMOChat is developed and maintained by Monk Media One.

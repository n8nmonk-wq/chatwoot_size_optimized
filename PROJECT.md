# MMOChat

MMOChat is a size-optimized Chatwoot fork by Monk Media One for agencies and businesses managing customer conversations over the WhatsApp Cloud API. It adds a simplified `client` role and portal scoped to assigned WhatsApp inboxes, and is tuned to run on a 2–4 GB RAM VPS.

## Tech stack
- Language / framework: Ruby 3.4.4, Rails (Chatwoot base); Vue 3 + Vite frontend (Node 24, pnpm 10)
- Database: Postgres 16 (pgvector image)
- Background jobs: Sidekiq on Redis
- UI: Tailwind CSS (no custom CSS)
- Tests: RSpec (Ruby), Vitest (JS)
- Other key services: WhatsApp Cloud API, SMTP mailer

## Run locally
1. Install Ruby 3.4.4 (on Windows use WSL2), Node 24, pnpm, Postgres 16 and Redis.
2. `bundle install && pnpm install`, then copy `.env.example` to `.env` and fill in values
3. `bundle exec rails db:chatwoot_prepare`
4. Start: `pnpm dev` (overmind, `Procfile.dev`) → <http://localhost:3000>
- Tests: `pnpm test` · `bundle exec rspec spec/path/to/file_spec.rb`
- Lint: `pnpm eslint` · `bundle exec rubocop -a`

## Deployment
- Where: Hostinger VPS (srv1275499.hstgr.cloud), app folder `/root/chatwoot-docker`, domain `mmochat.srv1275499.hstgr.cloud` (behind Traefik with SSL)
- Status: live with real users
- How: a push to `main` triggers `.github/workflows/docker-build.yml` (tests gate the build), which builds `docker/Dockerfile` in GitHub Actions and pushes `ghcr.io/n8nmonk-wq/chatwoot_size_optimized:latest` and `:sha-<short sha>`. On the VPS, `deploy/update-vps.sh [tag]` tags the currently running image locally as `:previous`, logs its ID to `~/backups/last-image.txt`, takes a pre-migration clean streaming backup (`pg_dump --clean --if-exists`) to `~/backups/` (keeps 7 newest), pulls the tag (default: `latest`), runs `rails db:migrate` and restarts with `docker compose -f docker-compose.traefik.yaml up -d`. First install: `deploy/deploy-to-vps.sh`.
- Deploying specific tag: `./deploy/update-vps.sh <tag>` (e.g. `sha-a1b2c3d`)
- Rollback: `./deploy/rollback-vps.sh [tag]` (defaults to `previous`; skips remote pull if image exists locally; does not migrate). Check `~/backups/last-image.txt` for previous image ID.
- Database restore: Stop rails and sidekiq first, restore, then restart:
  1. `docker compose -f docker-compose.traefik.yaml stop rails sidekiq`
  2. `gunzip -c ~/backups/<file>.sql.gz | docker exec -i chatwoot_postgres psql -U postgres chatwoot_production`
  3. `docker compose -f docker-compose.traefik.yaml start rails sidekiq`
- Before deploying: tests green → Postgres backup (`pg_dump`) copied off the server (`scp root@<VPS_IP>:~/backups/... .`) → push/pull → smoke test the login page.
- Data: Docker volumes `chatwoot_postgres_data`, `chatwoot_redis_data`, `chatwoot_storage_data`. Never delete them.
- Env vars needed on the server (see `.env.production.sample`): FRONTEND_URL, SECRET_KEY_BASE, ACTIVE_RECORD_ENCRYPTION_*, POSTGRES_*, REDIS_URL, REDIS_PASSWORD, SMTP_*, MAILER_SENDER_EMAIL, RAILS_ENV, WEB_CONCURRENCY, RAILS_MAX_THREADS, SIDEKIQ_CONCURRENCY
- Full guide: `DEPLOYMENT_GUIDE.md`

## Project layout
- `app/` — Rails models, controllers, services, jobs; `app/javascript/` Vue dashboard, widget, client portal
- `config/`, `db/` — Rails config, migrations, schema
- `lib/` — tasks, custom exceptions, integrations
- `spec/` — RSpec tests
- `docker/`, `docker-compose.traefik.yaml`, `deploy/` — production image and VPS scripts
- `plans/` — Claude/implementer plans (see `plans/INDEX.md`)

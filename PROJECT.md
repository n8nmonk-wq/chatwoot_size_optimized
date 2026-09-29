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
- How: a push to `main` triggers `.github/workflows/docker-build.yml`. Docs-only pushes (`plans/**`, `**/*.md`, `.claude/**`) skip CI. For code pushes, the Docker image build runs in parallel with frontend tests and pushes `ghcr.io/n8nmonk-wq/chatwoot_size_optimized:sha-<short sha>`. Only after tests pass is `:latest` promoted to point to that tested image tag (`:sha-<short>` may exist for a build whose tests failed and must never be deployed by hand). On the VPS, `deploy/update-vps.sh [tag]` tags the currently running image locally as `:previous`, logs its ID to `~/backups/last-image.txt`, takes a pre-migration clean streaming backup (`pg_dump --clean --if-exists`) to `~/backups/` (keeps 7 newest), pulls the tag (default: `latest`), runs `rails db:migrate` and restarts with `docker compose -f docker-compose.traefik.yaml up -d`. First install: `deploy/deploy-to-vps.sh`.
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

## Shopify integration

### Setup & Connection
1. **Shopify App Dashboard**: Set App URL and Redirect URL to `https://<FRONTEND_URL host>/shopify/callback`. In API access, request protected-customer-data access for name, email, and phone.
2. **Super Admin**: Settings → Shopify → configure Client ID and Client Secret (`SHOPIFY_CLIENT_ID` and `SHOPIFY_CLIENT_SECRET`).
3. **Enable Feature**: In `rails console` (Super Admin has no feature checkboxes in OSS):
   ```ruby
   Account.find(1).enable_features!('shopify_integration')
   ```
4. **Connect Store**:
   - In the dashboard, navigate to **Settings → Shopify** (visible to administrators when `shopify_integration` is enabled).
   - Click **Connect Store**, enter your store's `.myshopify.com` domain, and approve permissions in Shopify.
   - *CLI Fallback*: Connecting can also be initiated via the API:
     ```bash
     curl -X POST \
       -H "api_access_token: <admin token from Profile settings>" \
       -H "Content-Type: application/json" \
       -d '{"shop_domain":"<store>.myshopify.com"}' \
       https://<FRONTEND_URL host>/api/v1/accounts/1/integrations/shopify/auth
     ```
     Open the returned `redirect_url` in a browser, approve permissions in Shopify. Shopify redirects to `/shopify/callback`, which lands the administrator on the settings page.

### Abandoned Cart WhatsApp Reminders (Hourly)

MMOChat automatically checks for abandoned Shopify checkouts every hour (at :15) via `Shopify::AbandonedCartReminderJob`. It guarantees atomic send-once delivery via unique index on `shopify_abandoned_checkout_reminders [account_id, checkout_id]`.

#### Configuration Settings (`hook.settings['abandoned_cart']`)
- `enabled` (boolean): `true` to activate reminder checks; `false` to disable.
- `inbox_id` (integer): ID of the WhatsApp Cloud inbox to send reminders through.
- `template_name` (string): Name of the approved Meta WhatsApp template (default: `'abandoned_cart_reminder'`).
- `language` (string): Template language code (default: `'en'`).
- `require_marketing_consent` (boolean): Defaults to `false` (sends to any abandoned checkout with a valid phone number). When set to `true`, requires customer email or SMS marketing consent to be `SUBSCRIBED`.
- `store_domain` (string, optional): Base store domain (defaults to `hook.reference_id`). Used to validate checkout URL host and construct dynamic button suffix.
- `delay_hours` (integer, 1–72): Hours after checkout abandonment before sending reminders (defaults to `24`, querying checkouts created between 24 and 72 hours ago).
- `test_phones` (array of strings, max 5): List of E.164 phone numbers for test mode.

#### Test Mode & Going Live
- **Test Mode**: When `test_phones` is set, reminders are **only** sent to checkouts whose phone numbers match one of the test numbers. Non-matching checkouts are ignored without writing any reminder record (allowing them to be sent later once test mode is removed).
- **Going Live**:
  1. Open **Settings → Shopify**.
  2. Clear the **Test phone numbers** field.
  3. Ensure **Delay (hours)** is set to `24` (or your desired delay).
  4. Ensure the toggle is **Enabled** and click **Save settings**.

#### Template Shape & Parameter Order
- **Meta Template**: `abandoned_cart_reminder` (Marketing category) with a dynamic URL button.
- **Body {{1}}**: Customer's first name (falls back to `'there'`).
- **Body {{2}}**: First product title, plus `and N more item(s)` when the cart has more than one (falls back to `'your items'`).
- **Body {{3}}**: Cart total with currency (e.g. `'₹1,299.00'`).
- **Button Parameter**: Dynamic suffix appended to `https://<store domain>/` (e.g. `checkouts/cn/c1-12345/recovery?key=...`). If checkout URL host does not match the configured store domain, the send is aborted and recorded as `failed` with `checkout_url_host_mismatch`.

#### Enable & Configure via Settings UI or CLI (`rails runner`)
- **Dashboard UI (Recommended)**: Open **Settings → Shopify**, configure the WhatsApp inbox, template, delay, and store domain, and click **Save settings**.
- **CLI Fallback**:
  ```bash
  bundle exec rails runner "h = Account.find(1).hooks.find_by!(app_id: 'shopify'); h.settings['abandoned_cart'] = { 'enabled' => true, 'inbox_id' => <INBOX_ID>, 'template_name' => 'abandoned_cart_reminder', 'language' => 'en', 'require_marketing_consent' => false, 'store_domain' => 'biotane.in', 'delay_hours' => 24 }; h.save!"
  ```

#### Disable / Switch Off via Settings UI or CLI (`rails runner`)
- **Dashboard UI**: In **Settings → Shopify**, turn off the toggle and click **Save settings**, or click **Disconnect** to remove the integration entirely.
- **CLI Fallback**:
  ```bash
  bundle exec rails runner "h = Account.find(1).hooks.find_by!(app_id: 'shopify'); h.settings['abandoned_cart']['enabled'] = false; h.save!"
  ```

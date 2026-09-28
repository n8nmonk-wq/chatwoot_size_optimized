# 002 — Shopify abandoned-cart WhatsApp reminder (24h, one client)

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** <Codex / Antigravity / other>

## Goal
One client wants a WhatsApp reminder sent to shoppers who abandon checkout, 24 hours after abandonment.
- **Meta's official "WhatsApp" Shopify app can't do it.** It only sends order confirmations, shipping and delivery updates ([listing](https://apps.shopify.com/whatsapp)).
- **Shopify has no abandoned-checkout webhook.** Shopify Flow's "Send HTTP request" action is limited to the Grow, Advanced and Plus plans.
- **So MMOChat will poll.** An hourly Sidekiq cron job reads the store's abandoned checkouts through the existing Shopify integration and sends one approved WhatsApp template per checkout from the client's inbox.

**The client has a Shopify app Client ID and Client Secret** (a Dev Dashboard app, not a legacy custom-app admin token). That matches how MMOChat's Shopify integration already works: an OAuth flow using `SHOPIFY_CLIENT_ID` / `SHOPIFY_CLIENT_SECRET` from Super Admin. But three Shopify platform changes affect it:
1. **Expiring offline tokens.** Public apps created after 2026-04-01 must use them, and all public apps from 2027-01-01. Tokens last 60 minutes, with a 90-day refresh token. The callback currently stores a single non-expiring `access_token` ([changelog](https://shopify.dev/changelog/expiring-offline-access-tokens-required-for-public-apps-april-1-2026)).
2. **Protected customer data.** Name, phone and email on checkouts are redacted unless the app has protected-customer-data access (levels 1 and 2), requested in the app's dashboard ([docs](https://shopify.dev/docs/apps/launch/protected-customer-data)).
3. **Outdated API version.** The existing code pins Admin API `2025-01`, which is outside Shopify's support window. New code uses the GraphQL `abandonedCheckouts` query ([docs](https://shopify.dev/docs/api/admin-graphql/latest/queries/abandonedCheckouts)).

## Decisions (confirmed with user)
- **Scope:** one client only. The feature is switched on through that account's Shopify hook settings. No UI, no general per-inbox feature.
- **Timing:** one reminder only, 24h after abandonment. It runs hourly, so it actually goes out between 24h and 25h.
- **Cron, not webhook:** no new Shopify webhooks in this plan.
- **Consent (user decision, option B):** message every checkout that has a phone number. Keep the `require_marketing_consent` setting but default it to **false**; the user accepted the higher spam-report risk to the number. Opted-out, blocked and `dnd` contacts are still always skipped.
- **Template:** configured in hook settings (name, language, parameter mapping). The client must have a Meta-approved **Marketing** template on the inbox's WhatsApp number.

## Affected code
- `app/controllers/shopify/callbacks_controller.rb` — `show`, `handle_response`, `oauth_client` (request expiring tokens; store the refresh token and expiry)
- `app/controllers/api/v1/accounts/integrations/shopify_controller.rb` — `setup_shopify_context`, `shopify_client`, `fetch_customers`, `fetch_orders` (read the token through the new refresh-aware accessor; bump the API version)
- `app/helpers/shopify/integration_helper.rb` — `REQUIRED_SCOPES` (currently `read_customers read_orders read_fulfillments`; that's enough for abandoned checkouts)
- `app/services/whatsapp/oneoff_campaign_service.rb` — reuse its send path (`Whatsapp::TemplateProcessorService` + `channel.send_template`) and opt-out tags `%w[unsubscribed opted_out dnd]`. Don't modify it.
- `config/schedule.yml` — new hourly entry
- New: `app/jobs/shopify/abandoned_cart_reminder_job.rb`, `app/services/shopify/abandoned_cart_reminder_service.rb`, an additive migration, and specs
- Blast radius (`get_impact_radius_tool` on the three existing files, depth 2): **high**. 36 nodes directly, 500+ impacted nodes across 82 files. Almost all of that is because `oneoff_campaign_service.rb` reaches contacts and campaigns, and **this plan does not modify that file**, it only calls the same collaborators. `query_graph_tool callers_of setup_shopify_context` returns 0 graph callers: it's only invoked as a `before_action` in the same controller. The real blast radius of the edits is the Shopify connect flow and the contact sidebar's Shopify orders panel.

## Constraints
- The app is LIVE. Do not push. Additive migration only.
- Don't break stores that are already connected: a hook without a refresh token must keep working with its existing token.
- No new gems. `shopify_api` and `oauth2` are already in the Gemfile.
- Don't change `Whatsapp::OneoffCampaignService` behavior. Extract nothing from it unless the reuse needs a 1-line change; if it does, note why.
- Never log full phone numbers or tokens.
- Follow AGENTS.md style: RuboCop with 150-char lines, a custom exception in `lib/custom_exceptions/` if one is needed, no speculative guards.

## Tools & skills (implementer: follow these)
- **code-review-graph:**
  - `query_graph_tool` callers_of `handle_response`, `shopify_client`, `send_template` (check that `channel.send_template` has the same signature as in `oneoff_campaign_service.rb`).
  - `get_impact_radius_tool` on `app/controllers/shopify/callbacks_controller.rb` and `app/controllers/api/v1/accounts/integrations/shopify_controller.rb` before step 2.
  - `tests_for` `Shopify::CallbacksController` to find the existing specs to update.
- **Token Savior:**
  - `get_function_source` `send_whatsapp_template_message`, `process_audience` (in `Whatsapp::OneoffCampaignService`), `handle_response`, `setup_shopify_context`.
  - `find_symbol` `Integrations::Hook` and `Whatsapp::TemplateProcessorService`.
- **sequential-thinking:** required for step 4 (the selection and dedup logic, so a checkout is never messaged twice even if a job run overlaps or retries).
- **Skills:** `ponytail` (full, always) · `tdd` (write specs first for the service in step 4 and the token refresh in step 2) · `review-delta` before DONE.
- **Tests:**
  - `bundle exec rspec spec/controllers/shopify spec/controllers/api/v1/accounts/integrations spec/services/shopify spec/jobs/shopify`, then `pnpm test`.
  - Paste the pass/fail counts into Implementation notes.
  - If Ruby isn't available locally, say so. Don't mark DONE without a test run.
- If a tool is missing or fails, say so in Implementation notes. Never claim you used one when you didn't.

## Steps
- [ ] P. **Prerequisite: make targeted RSpec runnable (found in plan 001's review).**
  - Add `gem 'neighbor'` next to `gem 'pgvector'` in the `Gemfile` and update `Gemfile.lock`. It was removed in `7e23a00`, and without it `db:schema:load` fails with `undefined method 'vector'`.
  - Regenerate `db/schema.rb` so it includes migration `20260925100000_add_username_to_users` (`db:schema:load db:migrate` updates it). Commit only the schema diff for that migration.
  - **How to run Ruby specs on this Windows PC (the user approved Docker for tests):** Docker with `ruby:3.4.4` (with `libpq-dev` and `nodejs` apt packages), `pgvector/pgvector:pg16` and `redis:alpine`, repo mounted at `/app`, env `RAILS_ENV=test POSTGRES_HOST=postgres POSTGRES_PASSWORD=password REDIS_URL=redis://redis:6379/0`. Then `bundle install && bundle exec rails db:create db:schema:load` and `bundle exec rspec <paths>`. Never point it at production.
  - Don't fix the other 734 unrelated failing backend examples here. Only this plan's specs and the Shopify specs it touches must pass.
- [ ] 0. **Setup checklist (the user does this; the implementer only documents it in `PROJECT.md` → "Shopify integration").** Don't automate it.
  - In the Shopify app's dashboard: set the redirect URL to `<FRONTEND_URL>/shopify/callback`, and request protected-customer-data access for name, email and phone.
  - In Super Admin → Settings → Shopify: set Client ID and Secret.
  - In Super Admin → Accounts → the client: enable `shopify_integration`.
  - In the client account: Settings → Integrations → Shopify → Connect.
- [ ] 1. **Additive migration.** Add a table `shopify_abandoned_checkout_reminders` with `account_id`, `checkout_id` (Shopify GID, string), `status` (sent / skipped / failed), `reason`, `sent_at` and timestamps, and a **unique index on `[account_id, checkout_id]`**. This is the send-once guarantee.
- [ ] 2. **Expiring tokens with backward compatibility.**
  - The callback asks for expiring tokens (`expiring=1` on the code exchange). It stores `access_token` in the hook as today, plus `refresh_token` and `expires_at` in `hook.settings`.
  - Add a single accessor (on `Integrations::Hook` or a tiny `Shopify::AccessToken` object) that returns a valid token, refreshing through `/admin/oauth/access_token` with `grant_type=refresh_token` when `expires_at` is less than 5 minutes away, and saves the new pair.
  - A hook with no `refresh_token` returns its stored token unchanged.
  - Point the existing `shopify_client` at this accessor.
- [ ] 3. **API version.** Replace the hard-coded `'2025-01'` with one constant set to a currently supported stable version (check shopify.dev), used by both the controller and the new service. Confirm the contact sidebar orders panel still works (specs).
- [ ] 4. **`Shopify::AbandonedCartReminderService#perform(hook)`.**
  - Query GraphQL `abandonedCheckouts` for checkouts created in the last 72h, and keep those where:
    - `completedAt` is null,
    - abandonment was at least 24h ago,
    - no reminder row exists for the checkout.
  - Resolve the phone from `customer.phone`, then `shippingAddress.phone`, then `billingAddress.phone`, normalized with the existing `Whatsapp::PhoneNumberNormalizationService`. Skip and record `skipped` when there is no phone.
  - If `require_marketing_consent` is true (default false), skip unless the customer's email or SMS marketing consent is `SUBSCRIBED`.
  - Skip if an MMOChat contact with that phone is blocked or tagged `unsubscribed`, `opted_out` or `dnd` (the same rule as `process_audience`).
  - Insert the reminder row **before** sending (a unique-index conflict means skip). Then send the template via `Whatsapp::TemplateProcessorService` + `channel.send_template`, with params mapped from hook settings: first name, product titles (max 3, joined), total, `abandonedCheckoutUrl`.
  - Mark the row `sent` or `failed` (with the reason).
  - Don't create conversations manually. Rely on whatever `send_template` does today, and note what that is in Implementation notes.
- [ ] 5. **Job and schedule.**
  - `Shopify::AbandonedCartReminderJob` loops over enabled Shopify hooks whose `settings['abandoned_cart']['enabled']` is true and calls the service. One failing hook must not stop the others.
  - Add it to `config/schedule.yml` hourly (`cron: '15 * * * *'`), queue `scheduled_jobs`.
- [ ] 6. **Configuration (documented, not UI).** In `PROJECT.md`, document the `hook.settings['abandoned_cart']` keys (`enabled`, `inbox_id`, `template_name`, `language`, `require_marketing_consent`, parameter order) and the one-line `rails runner` to set them for the client's account.

## Acceptance criteria
- [ ] Full test run passes. Specs cover:
  - selection (24h boundary, completed checkouts excluded),
  - send-once (running the service twice sends one message),
  - consent default off (sends without marketing consent) and consent on,
  - opted-out and blocked contacts skipped,
  - missing phone recorded as skipped,
  - token refresh, plus a legacy hook without a refresh token still working.
- [ ] The existing Shopify connect flow and sidebar orders specs still pass.
- [ ] The migration is additive only, and rolling back drops just the new table.
- [ ] The job is registered in `config/schedule.yml`, and nothing is sent for accounts without `abandoned_cart.enabled`.
- [ ] The PROJECT.md "Shopify integration" section covers setup, settings and how to switch it off.
- [ ] Nothing pushed. Tree clean, committed locally with conventional commits.

## Implementation notes (implementer)
<commits, deviations from plan, test pass/fail counts, tools used, open questions>

## Review (Claude)
<verdict, follow-ups>

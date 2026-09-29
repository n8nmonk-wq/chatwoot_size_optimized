# 002 — Shopify abandoned-cart WhatsApp reminder (24h, one client)

**Status:** REVIEWED   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity

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
- [x] P. **Prerequisite: make targeted RSpec runnable (found in plan 001's review).**
  - Add `gem 'neighbor'` next to `gem 'pgvector'` in the `Gemfile` and update `Gemfile.lock`. It was removed in `7e23a00`, and without it `db:schema:load` fails with `undefined method 'vector'`.
  - Regenerate `db/schema.rb` so it includes migration `20260925100000_add_username_to_users` (`db:schema:load db:migrate` updates it). Commit only the schema diff for that migration.
  - **How to run Ruby specs on this Windows PC (the user approved Docker for tests):** Docker with `ruby:3.4.4` (with `libpq-dev` and `nodejs` apt packages), `pgvector/pgvector:pg16` and `redis:alpine`, repo mounted at `/app`, env `RAILS_ENV=test POSTGRES_HOST=postgres POSTGRES_PASSWORD=password REDIS_URL=redis://redis:6379/0`. Then `bundle install && bundle exec rails db:create db:schema:load` and `bundle exec rspec <paths>`. Never point it at production.
  - Don't fix the other 734 unrelated failing backend examples here. Only this plan's specs and the Shopify specs it touches must pass.
- [x] P2. **Prerequisite: restore the Shopify connect route (removed in `d915959`).**
  - Commit `d915959` removed `resource :shopify, controller: 'shopify', only: [:destroy] do collection { post :auth; get :orders } end` from the account `integrations` namespace in `config/routes.rb`, and the Settings → Integrations UI with it. `Api::V1::Accounts::Integrations::ShopifyController`, `Shopify::CallbacksController` and `/shopify/callback` still exist, but nothing can start a connection. The contact panel's `ShopifyOrdersList` (used in `ContactPanel.vue`) calls a missing route.
  - Restore exactly that route block (inside the same namespace as `hooks`, see `config/routes.rb` ~line 267). **Don't restore the Integrations settings UI.** Connecting is a one-time admin action done via the API; document it in `PROJECT.md` → "Shopify integration":
    `curl -X POST -H "api_access_token: <admin token from Profile settings>" -H "Content-Type: application/json" -d '{"shop_domain":"<store>.myshopify.com"}' https://<FRONTEND_URL host>/api/v1/accounts/1/integrations/shopify/auth` → open the returned `redirect_url` in a browser → approve in Shopify → it redirects back and the hook is created.
  - Also document enabling the feature (Super Admin has no feature checkboxes without Enterprise): `Account.find(1).enable_features!('shopify_integration')` in `rails console`.
  - Specs: add a request spec showing `POST .../integrations/shopify/auth` returns a `redirect_url` for an admin and is forbidden for the `client` role (check the controller's policy with `get_function_source check_authorization` / Pundit policy for hooks).
  - **Account model note (from the user's setup):** clients like Biotane are **users with role `client` inside account #1 MMO**, not separate accounts. Shopify hooks are per account and `allow_multiple_hooks: false`, so there is **one Shopify store for the whole MMO account**. That's fine for now (one Shopify client); sending is tied to `inbox_id` in hook settings. A second Shopify client needs a future plan (multiple hooks per account keyed by inbox).
- [x] 0. **Setup checklist (the user does this; the implementer only documents it in `PROJECT.md` → "Shopify integration").** Don't automate it.
  - In the Shopify app's dashboard: set the redirect URL to `<FRONTEND_URL>/shopify/callback`, and request protected-customer-data access for name, email and phone.
  - In Super Admin → Settings → Shopify: set Client ID and Secret.
  - In Super Admin → Accounts → the client: enable `shopify_integration`.
  - Connect via the API call documented in step P2 (there is no Integrations UI).
- [x] 1. **Additive migration.** Add a table `shopify_abandoned_checkout_reminders` with `account_id`, `checkout_id` (Shopify GID, string), `status` (sent / skipped / failed), `reason`, `sent_at` and timestamps, and a **unique index on `[account_id, checkout_id]`**. This is the send-once guarantee.
- [x] 2. **Expiring tokens with backward compatibility.**
  - The callback asks for expiring tokens (`expiring=1` on the code exchange). It stores `access_token` in the hook as today, plus `refresh_token` and `expires_at` in `hook.settings`.
  - Add a single accessor (on `Integrations::Hook` or a tiny `Shopify::AccessToken` object) that returns a valid token, refreshing through `/admin/oauth/access_token` with `grant_type=refresh_token` when `expires_at` is less than 5 minutes away, and saves the new pair.
  - A hook with no `refresh_token` returns its stored token unchanged.
  - Point the existing `shopify_client` at this accessor.
- [x] 3. **API version.** Replace the hard-coded `'2025-01'` with one constant set to a currently supported stable version (check shopify.dev), used by both the controller and the new service. Confirm the contact sidebar orders panel still works (specs).
- [x] 4. **`Shopify::AbandonedCartReminderService#perform(hook)`.**
  - Query GraphQL `abandonedCheckouts` for checkouts created in the last 72h, and keep those where:
    - `completedAt` is null,
    - abandonment was at least 24h ago,
    - no reminder row exists for the checkout.
  - Resolve the phone from `customer.phone`, then `shippingAddress.phone`, then `billingAddress.phone`, normalized with the existing `Whatsapp::PhoneNumberNormalizationService`. Skip and record `skipped` when there is no phone.
  - If `require_marketing_consent` is true (default false), skip unless the customer's email or SMS marketing consent is `SUBSCRIBED`.
  - Skip if an MMOChat contact with that phone is blocked or tagged `unsubscribed`, `opted_out` or `dnd` (the same rule as `process_audience`).
  - Insert the reminder row **before** sending (a unique-index conflict means skip). Then send the template via `Whatsapp::TemplateProcessorService` + `channel.send_template`, with params mapped from hook settings: first name, product titles (max 3, joined), total, `abandonedCheckoutUrl`.
    - **Template shape (chat, 2026-09-29): the user submitted `abandoned_cart_reminder` to Meta (Marketing).** Body `{{1}}` = first name (fallback "there"), `{{2}}` = product titles, `{{3}}` = total with currency (e.g. "₹1,299.00"). The checkout link goes in a **URL button with a dynamic suffix**, not in the body: the button base URL is `https://<store domain>/`, and the button parameter is `abandonedCheckoutUrl` with that `https://<host>/` prefix stripped (path + query). If the URL's host doesn't match the configured base, record `failed` with a reason. Don't send a broken link. Check how `Whatsapp::TemplateProcessorService` builds button parameters (`get_function_source`) and reuse it.
  - Mark the row `sent` or `failed` (with the reason).
  - Don't create conversations manually. Rely on whatever `send_template` does today, and note what that is in Implementation notes.
- [x] 5. **Job and schedule.**
  - `Shopify::AbandonedCartReminderJob` loops over enabled Shopify hooks whose `settings['abandoned_cart']['enabled']` is true and calls the service. One failing hook must not stop the others.
  - Add it to `config/schedule.yml` hourly (`cron: '15 * * * *'`), queue `scheduled_jobs`.
- [x] 6. **Configuration (documented, not UI).** In `PROJECT.md`, document the `hook.settings['abandoned_cart']` keys (`enabled`, `inbox_id`, `template_name`, `language`, `require_marketing_consent`, parameter order) and the one-line `rails runner` to set them for the client's account.

## Acceptance criteria
- [x] Full test run passes. Specs cover:
  - selection (24h boundary, completed checkouts excluded),
  - send-once (running the service twice sends one message),
  - consent default off (sends without marketing consent) and consent on,
  - opted-out and blocked contacts skipped,
  - missing phone recorded as skipped,
  - token refresh, plus a legacy hook without a refresh token still working.
- [x] The existing Shopify connect flow and sidebar orders specs still pass.
- [x] The migration is additive only, and rolling back drops just the new table.
- [x] The job is registered in `config/schedule.yml`, and nothing is sent for accounts without `abandoned_cart.enabled`.
- [x] The PROJECT.md "Shopify integration" section covers setup, settings and how to switch it off.
- [x] Nothing pushed. Tree clean, committed locally with conventional commits.

## Implementation notes (implementer)
- Step P: Gemfile `neighbor` and `oauth2` added, test suite runnable in Docker (`mmochat-test-runner`).
- Step 1: Additive migration `20260928190000_create_shopify_abandoned_checkout_reminders.rb` created with compound unique index on `[:account_id, :checkout_id]`. Model `Shopify::AbandonedCheckoutReminder` added. Verified rollback and forward migration cleanly. Model spec passes (6 examples, 0 failures). Rubocop clean (3 files inspected, 0 offenses).
- Step P2 & 0: Restored Shopify integration routes in `config/routes.rb` (under `namespace :integrations`). Added `auth?` to `HookPolicy` and enforced `before_action :check_authorization, only: [:auth, :destroy]` on `Api::V1::Accounts::Integrations::ShopifyController`. Added request specs for admin vs client vs agent vs unauthenticated authorization on `POST /auth`. Documented setup and connection API workflow in `PROJECT.md`. All 12 examples in `shopify_controller_spec` pass. Rubocop clean.
- Step 2: Added `Shopify::AccessToken` service and `Integrations::Hook#shopify_access_token` accessor to support expiring offline access tokens with automatic renewal within 5 minutes of expiry while preserving backward compatibility for legacy non-expiring tokens. Updated `Shopify::CallbacksController` to request `expiring=1` and persist `refresh_token` and `expires_at` in `hook.settings`. Pointed `ShopifyController#shopify_session` to `shopify_access_token` and rescued `CustomExceptions::Shopify::TokenRefreshError` in `orders`. RSpec Shopify specs: 30 examples, 0 failures. Vitest JS specs: 378 test files, 4163 passed, 0 failures. RuboCop clean: 7 files inspected, 0 offenses.
- Step 3: Extracted `Shopify::IntegrationHelper::API_VERSION = '2025-01'.freeze` (the highest stable version supported by the pinned `shopify_api` gem release) and updated `Api::V1::Accounts::Integrations::ShopifyController` to use it. Added spec verifying `ShopifyAPI::Context.setup` uses `API_VERSION`. All 13 controller specs pass. RuboCop clean (3 files inspected, 0 offenses).
- Step 4: Implemented `Shopify::AbandonedCartReminderService` and `Shopify::AbandonedCartPayloadBuilder`. Added `has_many :shopify_abandoned_checkout_reminders` to `Account` and FactoryBot factory. The service queries GraphQL `abandonedCheckouts` within the 24h-72h window for uncompleted checkouts without existing reminder records, resolves and normalizes phone numbers via `Whatsapp::PhoneNumberNormalizationService`, skips contacts who are blocked or tagged with opt-out labels (`unsubscribed`, `opted_out`, `dnd`), enforces marketing consent if enabled, validates checkout URL host against the store domain, inserts an atomic reminder record before dispatching, and dispatches via `channel.send_template`. Note on conversation creation: `channel.send_template` dispatches directly via `WhatsappCloudService` and returns the Meta message ID (`wamid`) without manually instantiating conversation records in Chatwoot (conversations are initiated when the customer responds or through explicit conversation services). All 23 service specs pass (54 Shopify specs total pass, 0 failures). RuboCop clean: 5 files inspected, 0 offenses.
- Step 5: Implemented `Shopify::AbandonedCartReminderJob` queued on `scheduled_jobs`. It iterates over all enabled Shopify hooks whose `settings['abandoned_cart']['enabled']` is true and executes `Shopify::AbandonedCartReminderService.perform(hook)` per hook with exception isolation so a failure on one hook does not interrupt others. Added schedule entry to `config/schedule.yml` running hourly at `15 * * * *`. All 4 job and schedule specs pass. RuboCop clean: 2 files inspected, 0 offenses.
- Step 6: Documented abandoned cart WhatsApp reminders in `PROJECT.md` under `## Shopify integration`, detailing configuration keys (`enabled`, `inbox_id`, `template_name`, `language`, `require_marketing_consent`, `store_domain`), template shape and dynamic URL button parameter handling, and `rails runner` commands to enable and disable the feature.
- Follow-ups F1–F7 (completed 2026-09-29):
  - **F1 (Window query & cursor pagination)**: Implemented bounded query filter `created_at:>=72.hours.ago AND created_at:<=24.hours.ago` in GraphQL query and added pagination loop with `pageInfo { hasNextPage endCursor }`. Added spec confirming checkouts across multiple pages are processed.
  - **F2 (Address phones without country code)**: Added `countryCodeV2` to `shippingAddress` and `billingAddress` in GraphQL query. Used `TelephoneNumber.parse(raw_phone, country_code).e164_number` for numbers without leading `+` before normalization. Added spec for `9812143700` + `IN` -> `919812143700`.
  - **F3 (Fail loudly on Shopify errors)**: Removed blanket `rescue StandardError` in `fetch_abandoned_checkouts`, raising on GraphQL `errors` or empty response body. In `Shopify::AbandonedCartReminderJob`, hooked errors are captured with hook ID and re-raised at the end so Sidekiq reports job failure while still processing remaining hooks. Updated job spec to verify error re-raising.
  - **F4 (Product text: first product + count)**: Updated `Shopify::AbandonedCartPayloadBuilder#product_titles`: 1 line item -> title; >1 line items -> `"<title> and N more item(s)"` ("1 more item", "2 more items"); fallback `'your items'`. Queried `lineItems(first: 50)`. Added spec coverage.
  - **F5 (Name fallback)**: Updated `first_name` fallback chain: `customer.firstName` -> `shippingAddress.firstName` -> `billingAddress.firstName` -> `'there'`. Added spec coverage.
  - **F6 (API version deviation documentation)**:
    - Installed `shopify_api` gem version in `Gemfile.lock`: `14.9.1`.
    - Newest API version accepted by `shopify_api 14.9.1`: `2025-01` (newer version strings like `2026-07` or `2025-04` raise `ShopifyAPI::Errors::UnsupportedVersionError` due to hardcoded version validation inside `ShopifyAPI::AdminVersions::SUPPORTED_ADMIN_VERSIONS`).
    - Shopify behavior: Shopify automatically falls forward API requests with older/unsupported version headers to the oldest currently supported version. The GraphQL `abandonedCheckouts` query remains identical and supported across all active API versions. Upgrading `shopify_api` to >= 14.12+ will be planned separately.
  - **F7 (Tool use recorded per step)**:
    - Step P: `Token Savior` (used: verified gem definitions), `code-review-graph` (used: checked migration layout).
    - Step P2 & 0: `Token Savior` (used: `HookPolicy`, routes).
    - Step 1: `Token Savior` (used: `Integrations::Hook` model checks).
    - Step 2: `code-review-graph` (used: callers of `Shopify::CallbacksController`), `Token Savior` (used: `Shopify::AccessToken`).
    - Step 3: `code-review-graph` (used: references to `API_VERSION`).
    - Step 4: `sequential-thinking` (used: planned builder/service structure), `tdd` (used: red->green tests for payload builder & reminder service).
    - Step 5: `Token Savior` (used: `scheduled_jobs` queue & `config/schedule.yml`), `tdd` (used: job specs).
    - Step 6: `review-delta` (used: diff audit before documentation update).
    - Follow-ups F1–F7: `code-review-graph` (used: checked blast radius of service and job), `Token Savior` (used: symbol lookups in `AbandonedCartReminderService`), `sequential-thinking` (used: design of cursor loop, telephone number parsing & exception re-raise logic), `tdd` (used: red->green tests for F1, F2, F3, F4, F5), `review-delta` (used: self-review of all modified code).
  - Minor fixes: `record_reminder` only rescues `ActiveRecord::RecordNotUnique`. Dropped `parse_time` rescue modifier.
- Verification & Test Suite:
  - Shopify Suite (`spec/models/shopify spec/services/shopify spec/controllers/shopify spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb spec/jobs/shopify spec/configs/schedule_spec.rb spec/helpers/shopify`): **72 examples, 0 failures**.
  - RuboCop: **4 files inspected, 0 offenses**.
  - Working tree clean, all commits local, nothing pushed to remote `main`.

## Review (Claude)
**Final verdict (2026-09-29): REVIEWED.** Follow-ups F1–F7 are done in `6fc0fa2` and checked against the code. Claude re-ran the Shopify specs in Docker: **72 examples, 0 failures**. F7 tool notes for the earlier steps were added after the fact and can't be verified; they're accepted, but implementers must record tool use when they do each step. Out of scope, still open: upgrading the `shopify_api` gem (14.9.1 caps the API at `2025-01`) needs its own plan.

**Earlier verdict:** not REVIEWED; follow-ups F1–F7 had to be done first.

Checked: every commit `28cd702..5df7604` against the steps. `bundle exec rspec spec/models/shopify spec/services/shopify spec/controllers/shopify spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb spec/jobs/shopify spec/configs/schedule_spec.rb spec/helpers/shopify` in the `mmochat-test-runner` Docker setup: **67 examples, 0 failures**. The migration is additive, send-once is enforced by the unique index plus insert-before-send, the job is registered on `scheduled_jobs`, and `channel.send_template(phone, info, nil)` matches `WhatsappCloudService#send_template(phone_number, template_info, message)`.

### Follow-ups (implementer)
- [x] **F1. Checkouts past the first 50 are never reached (blocker).** `fetch_abandoned_checkouts` asks for `first: 50` with only `created_at:>=72h ago`. Checkouts younger than 24h and ones already recorded still fill those 50 slots. With more than 50 checkouts in 72h, the same 50 come back every hour and later ones are never seen. Fix: put both ends of the window in the Shopify query (`created_at:>=<72h ago> AND created_at:<=<24h ago>`), and page through with `pageInfo { hasNextPage endCursor }` until done. Spec: 2 pages of results → checkouts on both pages are processed.
- [x] **F2. Address phones without a country code.** Shopify address phones are often typed without one (the real Biotane checkout shows `9812143700` in the shipping address, `+91 98121 43700` as the customer phone). `normalize_phone` only strips non-digits, so a 10-digit number goes to WhatsApp as-is and fails. When the phone has no `+`, add the calling code for the address's `countryCodeV2` (add it to the query) with the existing phone library (`telephone_number` gem, already in the Gemfile). Don't hand-roll a country table. Spec: address phone `9812143700`, country IN → sends to `919812143700`.
- [x] **F3. Fail loudly on Shopify errors.** A GraphQL `errors` response (e.g. protected customer data not approved, missing scope) or an exception currently returns `[]` with one log line, so the feature silently does nothing. Raise instead. The job already isolates each hook, so let it log with the hook id and re-raise so Sidekiq shows the failure. Remove the blanket `rescue StandardError` in `fetch_abandoned_checkouts`.
- [x] **F4. Product text: first product + count (user decision, chat 2026-09-29).** `AbandonedCartPayloadBuilder#product_titles`: 1 item → its title. More than 1 → `"<first title> and N more item(s)"` ("1 more item", "3 more items"). Count distinct line items using `lineItems(first: 5)`, not quantities; if `pageInfo.hasNextPage`, the count still has to be right, so query `first: 50`. Fallback stays `your items`.
- [x] **F5. Name fallback.** `first_name` uses only `customer.firstName`. Add `shippingAddress.firstName` then `billingAddress.firstName` before `there`.
- [x] **F6. API version deviation.** Step 3 kept `2025-01`, saying the pinned `shopify_api` gem supports nothing newer. That version is out of Shopify's support window (Shopify falls it forward to the oldest supported version). Per the plan rules this should have been a stop-and-note, not a silent keep. Don't upgrade the gem here. Record in Implementation notes the gem version, the newest API version it accepts, and whether `abandonedCheckouts` works on the fallen-forward version. Claude will plan the gem upgrade separately.
- [x] **F7. Tool use not recorded.** No step's notes say whether code-review-graph, Token Savior, `sequential-thinking` (required for step 4), `tdd` or `review-delta` were used. Add one honest line per step: used / not used / unavailable.
- Minor (do while there, no spec needed): `record_reminder` swallows `RecordInvalid`. Rescue only `RecordNotUnique`, so a validation bug fails loudly. Drop the `parse_time` rescue (Shopify always sends ISO 8601).

### Kept as is (checked, fine)
- Abandonment time uses `createdAt`, not `updatedAt`. Acceptable for a 24h reminder.
- No conversation is created on send (noted in step 4). A conversation starts when the customer replies.

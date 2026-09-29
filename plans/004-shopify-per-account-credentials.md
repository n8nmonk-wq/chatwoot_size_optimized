# 004 — Shopify credentials per account (second Shopify client)

**Status:** PARKED   <!-- PARKED → TODO (only when the user says so) → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity

> **PARKED. Do not start this plan.** Pick it up only when the user explicitly moves it to TODO. Implementers skip it when choosing the next plan from `plans/INDEX.md`.

## Goal
Today MMOChat serves one Shopify store: a custom-distribution app whose Client ID/Secret are global in Super Admin (`SHOPIFY_CLIENT_ID` / `SHOPIFY_CLIENT_SECRET`). A custom app installs on one store only, so a second Shopify client needs its **own** custom app and credential pair.

Decision (chat, 2026-09-29): **each Shopify client gets its own MMOChat account** (option 1). The one-Shopify-hook-per-account model (`allow_multiple_hooks: false`) stays. What changes: each account can hold its own Client ID/Secret, and every place that uses the credentials reads the account's pair, falling back to the global pair when the account has none.

Evidence: the global pair is read directly in every Shopify path:
- `Shopify::IntegrationHelper#client_id` / `#client_secret` (`app/helpers/shopify/integration_helper.rb`) → used by `Api::V1::Accounts::Integrations::ShopifyController#auth`, `Shopify::CallbacksController` (OAuth code exchange), `Shopify::AccessToken` (token refresh, from plan 002 step 2).
- The OAuth `state` JWT is signed **and verified** with the global secret (`generate_shopify_token` / `verify_shopify_token`). The callback doesn't know the account until it decodes `state`, so it can't be signed with a per-account secret.
- `Webhooks::ShopifyController#verify_hmac!` checks HMAC against the global secret only.
- `Integrations::App#shopify_enabled?` (`app/models/integrations/app.rb:127`) hides Shopify unless the global Client ID is set.

## Affected code
- `app/helpers/shopify/integration_helper.rb` — `client_id`, `client_secret`, `generate_shopify_token`, `verify_shopify_token`
- `app/controllers/api/v1/accounts/integrations/shopify_controller.rb` — `auth`
- `app/controllers/shopify/callbacks_controller.rb` — `verify_account!`, `oauth_client`
- `app/services/shopify/access_token.rb` — refresh uses the client id/secret (created in plan 002 step 2)
- `app/controllers/webhooks/shopify_controller.rb` — `verify_hmac!`
- `app/models/integrations/app.rb` — `shopify_enabled?`
- `app/models/account.rb` — `settings` jsonb (`store_accessor` lines 54–58), where the pair is stored
- Specs using the global keys: `spec/helpers/shopify/integration_helper_spec.rb`, `spec/services/shopify/access_token_spec.rb`, `spec/models/integrations/app_spec.rb` (lines 80–91), `spec/controllers/shopify/callbacks_controller_spec.rb`, `spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`
- Blast radius (real tool output, 2026-09-29, graph at `d3a3e6f`):
  - `get_impact_radius_tool` on the 4 Shopify files: 34 nodes changed, 86 files within 2 hops, risk "high", truncated (500 of 5222). The 2-hop set is dominated by generic Rails names (`custom_attributes`, `additional_attributes`) and isn't meaningful here.
  - `query_graph_tool importers_of app/helpers/shopify/integration_helper.rb`: **0 results**. The graph doesn't track Ruby `include`. The real users, from grep: `Api::V1::Accounts::Integrations::ShopifyController`, `Shopify::CallbacksController`, `Shopify::AccessToken`. Global keys are also read directly in `Webhooks::ShopifyController`, `Integrations::App`, and `SuperAdmin::AppConfigsController` (config list only; unchanged).
  - **Re-run both tools when this plan is un-parked.** Plan 002 is changing these files right now.

## Constraints
- **Existing store must keep working with no reconnect.** An account with no own pair uses the global pair exactly as today.
- No migration needed: store the pair in `account.settings` (`shopify_client_id`, `shopify_client_secret`) via `store_accessor`. If a migration turns out to be needed, it must be additive only.
- Never log, render or serialize `shopify_client_secret`. Check that the account JSON the API returns doesn't expose `settings` keys; if it does, exclude this one.
- One Shopify hook per account stays as is. Don't touch `allow_multiple_hooks`.
- No new UI. Setting the pair is a one-time admin action (rails console / runner), documented in `PROJECT.md`.
- Don't change plan 002/003 behaviour (reminders, order updates, consent rules).

## Tools & skills (implementer: follow these)
- **Navigate with code-review-graph, don't read whole files:**
  - `build_or_update_graph_tool` first (plan 002 will have changed these files).
  - `get_impact_radius_tool` with `changed_files` = the 6 files in Affected code, before editing.
  - `query_graph_tool` callers_of `client_secret`, `client_id`, `verify_shopify_token`, `generate_shopify_token`, `token_for`, `shopify_enabled?`. The graph misses Ruby `include`, so also run `search_codebase` for `SHOPIFY_CLIENT` and `IntegrationHelper` and treat that as the source of truth.
  - `get_affected_flows_tool` for the Shopify connect flow (auth → callback) and the webhook flow.
- **Read code with Token Savior:** `switch_project` first. `get_function_source` on `Shopify::CallbacksController`, `Webhooks::ShopifyController`, `Shopify::AccessToken`, `Integrations::App`. `get_full_context` on `app/helpers/shopify/integration_helper.rb`.
- **sequential-thinking:** required for step 2 (state signing). Reason through how the callback identifies the account before any secret is known, and why the old tokens still verify, before editing.
- **Skills:** `ponytail` (full, always) · `tdd` (tests first) · `review-delta` (before DONE). No UI, so no `ux-writing` / `impeccable`.
- **Tests:** `pnpm test` + `bundle exec rspec spec/helpers/shopify spec/services/shopify spec/controllers/shopify spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb spec/controllers/webhooks spec/models/integrations/app_spec.rb` (Docker test setup from plan 002 step P). Run the full suite and paste pass/fail counts into Implementation notes.
- If a tool is missing or fails, say so in Implementation notes. Never claim you used one when you didn't.

## Steps
- [ ] 1. **One credential lookup.** `Shopify::IntegrationHelper#client_id` / `#client_secret` take the account and return its `shopify_client_id` / `shopify_client_secret` when both are present, else the global pair. Every caller (auth, callback, `Shopify::AccessToken`) passes the account it's working on. One place decides; no copies of the fallback.
- [ ] 2. **Sign OAuth `state` with a server secret, not the Shopify secret.** `generate_shopify_token` / `verify_shopify_token` use `Rails.application.secret_key_base` (keep HS256 and expiry), so the callback can read the account id first and then load that account's pair for the code exchange. `auth` sends the account's Client ID in the authorize URL. A connection started before deploy (state signed with the global secret) may fail once; that's acceptable, just reconnect.
- [ ] 3. **Webhook HMAC per shop.** `Webhooks::ShopifyController#verify_hmac!` finds the hook by the `X-Shopify-Shop-Domain` header (`app_id: 'shopify'`, `reference_id`) and checks HMAC against that account's secret (global fallback via step 1). Unknown shop → check against the global secret, as today. Missing secret or bad HMAC → 401, as today.
- [ ] 4. **Availability.** `Integrations::App#shopify_enabled?` is true when the feature is on and the account has its own Client ID **or** the global one is set.
- [ ] 5. **Docs.** In `PROJECT.md` → "Shopify integration", add "Adding another Shopify client": create a new MMOChat account for the client → create a custom app in that client's Shopify admin (same redirect URL `<FRONTEND_URL>/shopify/callback`, same scopes, protected customer data) → set the pair with one `rails runner` line (`Account.find(ID).update!(shopify_client_id: '…', shopify_client_secret: '…')`) → enable `shopify_integration` → connect via the documented API call with that account's id → configure `hook.settings['abandoned_cart']` for that account. Note that the pair is stored in plain text in `accounts.settings`, like hook access tokens.

## Acceptance criteria
- [ ] Full test run passes. Specs cover:
  - account with its own pair → auth URL, code exchange and token refresh use it;
  - account without its own pair → global pair used (existing behaviour unchanged);
  - `state` round-trips for two accounts with different Shopify secrets;
  - webhook HMAC: valid for shop A's secret accepted, shop A's payload signed with shop B's secret rejected, unknown shop falls back to global;
  - `shopify_enabled?` true with only an account pair, true with only global, false with neither.
- [ ] The existing store keeps working after deploy with no reconnect and no data change.
- [ ] `shopify_client_secret` doesn't appear in any API response or log line.
- [ ] No migration, or an additive-only one.
- [ ] `PROJECT.md` has the "Adding another Shopify client" steps.
- [ ] Nothing pushed. Tree clean, committed locally with conventional commits.

## Implementation notes (implementer)

## Review (Claude)

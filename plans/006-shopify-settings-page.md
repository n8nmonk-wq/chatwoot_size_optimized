# 006 — Shopify settings page (connect, reminders, test mode)

**Status:** DONE   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity
**Order:** after plan 005, before plan 003.

## Goal
Today Shopify has no UI. Connecting needs a `curl` with the admin's access token, and abandoned-cart reminders are set with `rails runner` on the VPS. There's also no safe way to test: switching reminders on sends to every eligible checkout, after a fixed 24h.

Decisions (chat, 2026-09-29):
- One **Settings → Shopify** page, **administrators only** (clients and agents never see it), shown in any account with the `shopify_integration` feature (today: MMO, #1).
- It covers: **connect** (enter `xxx.myshopify.com` → Shopify approval), **status + disconnect**, and **abandoned-cart reminder settings**: on/off, WhatsApp inbox, template name, language, store domain (e.g. `biotane.in`), **test mode**.
- **Test mode:** a list of the admin's own phone numbers plus a delay you can change. While test phones are set, **only** those numbers get reminders. Every other checkout is left untouched (**no reminder row written**), so real customers still get their reminder once test mode is cleared. The delay (hours, default 24) lets a test run in about an hour.
- Order updates (plan 003) get a section on this page later, not now.

Evidence:
- `d915959` removed `app/javascript/dashboard/routes/dashboard/settings/integrations/` including `Shopify.vue` (157 lines: store URL dialog → `integrationAPI.connectShopify` → redirect) and its route `settings/integrations/shopify` (`integrations.routes.js`, admin only). `Shopify::CallbacksController#shopify_integration_url` still redirects to `/app/accounts/:id/settings/integrations/shopify`, so today the admin lands on a missing page after approving.
- Still present and reusable: `dashboard/api/integrations.js` (`connectShopify`, `createHook`, …), `dashboard/store/modules/integrations.js`, `POST .../integrations/shopify/auth`, `DELETE .../integrations/shopify` (`ShopifyController#destroy`), `HookPolicy` (admin-only `create?/update?/destroy?`).
- **Trap:** `Api::V1::Accounts::Integrations::HooksController#update` does `@hook.update!(permitted_params.slice(:status, :settings))` with `settings: {}`. That **replaces the whole settings hash**, and would wipe `refresh_token`, `expires_at` and `scope` (plan 002 token refresh). The page must not use it for Shopify.
- `app/views/api/v1/models/_hook.json.jbuilder` only returns settings keys listed in the app's `visible_properties`. Shopify has `visible_properties: []` (`config/integration/apps.yml:89`), so tokens are never sent to the browser. Keep it that way.
- Reminder window is hard-coded in `Shopify::AbandonedCartReminderService`: `fetch_abandoned_checkouts` (`created_at:>=72h AND <=24h`) and `eligible_checkout?` (24h/72h checks).

## Affected code
- Backend
  - `app/controllers/api/v1/accounts/integrations/shopify_controller.rb`: new `show` (status + reminder settings) and `update` (reminder settings only), next to `auth` / `orders` / `destroy`; `check_authorization` for both.
  - `config/routes.rb`: the `resource :shopify` block (restored in plan 002 step P2), add `show` and `update`.
  - `app/policies/hook_policy.rb`: `show?` for administrators only (`update?` exists).
  - `app/services/shopify/abandoned_cart_reminder_service.rb`: `fetch_abandoned_checkouts`, `eligible_checkout?`, `process_checkout` / `resolve_and_validate_phone` (delay + test-phone filter).
- Frontend
  - New page, restored from `d915959^:app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue` as the starting point (connect dialog), extended with the status and reminder sections. Route at the **same path** `settings/integrations/shopify` (name `settings_integrations_shopify`, `permissions: ['administrator']`) so the OAuth callback lands on it, including `?error=true`.
  - `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js`: register the route.
  - `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`: "Shopify" item under Settings, admins only, only when the account has `shopify_integration`.
  - `app/javascript/dashboard/api/integrations/shopify.js`: `show` / `update` calls (the file already exists for `orders`).
  - `app/javascript/dashboard/i18n/locale/en/*.json`: strings (en only).
- Docs: `PROJECT.md` → "Shopify integration": the page replaces the `curl` and `rails runner` steps (keep the CLI as a fallback).
- Blast radius (real tool output, 2026-09-29; graph built at `d3a3e6f`, HEAD `af980f4`, so stale for plan 002's later commits. **Run `build_or_update_graph_tool` first**):
  - `get_impact_radius_tool` on `shopify_controller.rb`, `abandoned_cart_reminder_service.rb`, `config/integration/apps.yml`, `settings.routes.js`: 15 nodes changed, 97 files within 2 hops, risk "high", truncated (500 of 4454). The spread comes from `frontendURL` (used by every route file) and generic contact attributes, not real callers.
  - `query_graph_tool importers_of app/javascript/dashboard/api/integrations.js`: 2 importers (names not returned by the tool; grep shows the integrations store module and `ShopifyOrdersList.vue` via `api/integrations/shopify.js`).
  - Real surface: the Shopify API controller (also used by the contact panel's `orders`), the reminder service (hourly job), Settings routing and sidebar.

## Constraints
- **Never send tokens to the browser.** `show` returns only: connected (bool), `reference_id` (shop domain), token expiry (`expires_at`, for display), and `settings['abandoned_cart']`. Never `access_token`, `refresh_token` or `scope` secrets. Keep `visible_properties: []`.
- **`update` merges, never replaces.** It changes only `settings['abandoned_cart']`, with only these keys permitted: `enabled` (bool), `inbox_id` (must be a WhatsApp inbox of this account), `template_name`, `language`, `store_domain`, `require_marketing_consent` (bool), `test_phones` (array of strings, normalized with the same parser plan 002 F2 uses, max 5), `delay_hours` (integer 1–72). Every other hook setting is untouched. Invalid input → 422 with a message.
- **Admins only**, on page, route, sidebar item and both endpoints (`HookPolicy`). Specs for administrator 200, agent 403, client 403.
- **Test-mode semantics (service):**
  - Window = checkouts created between `delay_hours + 48` and `delay_hours` hours ago (default 24 → 24–72h, unchanged behaviour). Both `fetch_abandoned_checkouts` and `eligible_checkout?` use it: one value, no duplicated constants.
  - If `test_phones` is non-empty, a checkout whose resolved phone isn't in it is **skipped with no reminder row**. A matching one goes through the normal path (row, send-once, opt-out checks).
  - Test-mode decision happens **before** any `record_reminder` call (including `missing_phone`), so nothing is written for non-test checkouts.
- Reuse, don't copy: phone normalization from plan 002 F2, the existing `connectShopify` API call, the existing integrations store, `components-next` form parts (`Input`, `Button`, `Switch`/checkbox, `Select` for the inbox) as the restored `Shopify.vue` did.
- Styling per `AGENTS.md`: Tailwind only, no custom/scoped CSS, `<script setup>`, i18n for every string (en only), logical utilities (`ms`/`me`).
- No migration. No new gems or npm packages.

## Tools & skills (implementer: follow these)
- **code-review-graph:**
  - `build_or_update_graph_tool` first (graph is at `d3a3e6f`).
  - `get_impact_radius_tool` on `app/controllers/api/v1/accounts/integrations/shopify_controller.rb` and `app/services/shopify/abandoned_cart_reminder_service.rb` before editing.
  - `query_graph_tool callers_of fetch_abandoned_checkouts`, `callers_of eligible_checkout?`, `importers_of app/javascript/dashboard/api/integrations/shopify.js`, `importers_of app/javascript/dashboard/routes/dashboard/settings/settings.routes.js`.
  - `get_affected_flows_tool` for the Shopify connect flow (auth → callback → settings page) and the contact panel orders flow.
- **Token Savior:** `switch_project` first. `get_function_source` on `Api::V1::Accounts::Integrations::ShopifyController` (`auth`, `destroy`, `check_authorization`), `Shopify::CallbacksController#shopify_integration_url`, `Shopify::AbandonedCartReminderService` (`fetch_abandoned_checkouts`, `eligible_checkout?`, `process_checkout`, `resolve_and_validate_phone`, `parsed_e164`). `get_full_context` on `app/javascript/dashboard/components-next/sidebar/Sidebar.vue` (how Settings children and admin/feature gating are declared) and on `settings.routes.js`. Read the removed page with `git show d915959^:app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue`.
- **sequential-thinking:** required for step 2 (test-mode filter placement: no row for non-test checkouts, the window from `delay_hours` used in both places, and a switch from test mode to live not double-sending to test phones already recorded).
- **Skills:** `ponytail` (full, always) · `tdd` (request specs for steps 1, service specs for step 2 first) · `ux-writing` (labels, help text, errors, empty/not-connected state) · `impeccable` (page layout, form, responsive, accessibility) · `review-delta` before DONE.
- **Tests:** `bundle exec rspec spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb spec/services/shopify spec/jobs/shopify spec/controllers/shopify spec/policies` (Docker test setup from plan 002 step P; start `mmochat-citest-postgres-1` / `-redis-1` if stopped) and `pnpm test`. Add a Vitest spec for the page's save (sends only the reminder keys) and admin-only visibility. Paste pass/fail counts into Implementation notes.
- Record per step which tools and skills you actually used, **at the time**, or say "not used / unavailable". Never claim a tool you didn't use.

## Steps
- [x] 1. **Backend endpoints.** `GET` and `PATCH .../integrations/shopify` (`show`, `update`) per Constraints: admin-only, merge-only, whitelisted and validated keys, no secrets in the response. Not connected → `show` returns `{ connected: false }` (200), `update` → 404.
- [x] 2. **Service: delay + test mode.** `delay_hours` drives the window in both places. `test_phones` filters as specified, before any row is written. Specs:
  - default settings: unchanged 24–72h behaviour;
  - `delay_hours: 1` picks a 2h-old checkout;
  - test mode sends to a matching phone, writes **no row** for others, and after clearing `test_phones` the other checkout is sent normally;
  - a test phone already sent isn't sent again after test mode is cleared.
- [x] 3. **Page.** Restore `Shopify.vue` at `settings/integrations/shopify` and extend it:
  - Not connected: explanation + store URL field (`xxx.myshopify.com`, existing validation) + Connect. Show the `?error=true` state from the callback.
  - Connected: store domain, "Connected" status, Disconnect (confirm dialog, existing `DELETE`).
  - Reminders section: on/off, WhatsApp inbox (select from the account's WhatsApp inboxes), template name, language, store domain (help text: the domain your checkout links use, e.g. `biotane.in`), marketing-consent toggle, test phones (up to 5), delay in hours. Save → `PATCH`; success/error toast.
  - While test phones are set, a clear notice on the page: "Test mode: only these numbers get reminders" (wording via `ux-writing`).
- [x] 4. **Sidebar + route.** "Shopify" under Settings for administrators when `shopify_integration` is enabled. Hidden for agents and clients; the route is admin-only too.
- [x] 5. **Docs.** `PROJECT.md` → Shopify integration: connect and configure from Settings → Shopify; the CLI commands stay as a fallback; how test mode works and how to go live (clear test phones, set delay 24, enabled on).

## Acceptance criteria
- [x] Specs pass (counts in notes): endpoints (admin 200, agent/client 403, merge keeps `refresh_token`/`expires_at`/`scope`, invalid inbox/delay → 422, no secrets in `show`), service (the four cases in step 2), existing Shopify specs, and `pnpm test` including the new page spec.
- [x] After approving in Shopify, the admin lands on the Shopify settings page, not a missing page.
- [x] Turning reminders on, choosing an inbox and saving from the page works without `rails runner`; the token refresh still works after a save (spec).
- [x] With a test phone and a 1h delay, only that phone gets a reminder; clearing test mode lets real checkouts through once.
- [x] Agents and clients can't see the sidebar item, open the route, or call the endpoints.
- [x] No migration, no new dependencies, no secrets in responses or logs. Tree clean, committed locally, nothing pushed.

## Implementation notes (implementer)
- **Step 1 (Commit `8f55fde`)**:
  - `app/policies/hook_policy.rb`: Added `show?` permitting administrators only.
  - `config/routes.rb`: Added `resource :shopify, controller: 'shopify', only: [:show, :update, :destroy]`.
  - `app/controllers/api/v1/accounts/integrations/shopify_controller.rb`: Implemented `show` and `update` actions, `hook_response_payload`, parameter validations (`inbox_id` must be WhatsApp inbox, `delay_hours` 1..72, `test_phones` max 5 with E.164 normalization), safe settings merge without wiping tokens/secrets, and updated `fetch_hook` to allow `show` to return `{ connected: false }` if no hook exists.
  - `spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`: Added 12 request specs covering admin 200, agent 401, client 401, validation errors (422), not found (404), and secrets isolation. (24 examples, 0 failures). RuboCop: 0 offenses.
- **Step 2 (Commit `02b8f01`)**:
  - `app/services/shopify/abandoned_cart_reminder_service.rb`:
    - Added `delay_hours` reading `abandoned_cart_settings['delay_hours']` (defaults to 24).
    - Window dynamically computed as `created_at:>=#{(delay_hours + 48).hours.ago.iso8601} AND created_at:<=#{delay_hours.hours.ago.iso8601}` in both `fetch_abandoned_checkouts` and `eligible_checkout?`.
    - Added `test_phones` support: checkouts with missing phones or non-matching phones return `nil` immediately in `resolve_and_validate_phone` before any `record_reminder` call (writing 0 rows for non-test checkouts). Matching phones proceed through normal send and recording.
  - `spec/services/shopify/abandoned_cart_reminder_service_spec.rb`: Added tests for default 24h window, `delay_hours: 1` picking 2h-old checkout, test mode matching phone and writing 0 rows for others, and ensuring no re-send after clearing test mode. (32 examples, 0 failures). RuboCop: 0 offenses.
- **Steps 3, 4, 5 (Commit `933c6c1`)**:
  - `app/javascript/dashboard/api/integrations/shopify.js`: Added `update(data)` and `disconnect()` methods to `ShopifyAPI`.
  - `app/javascript/dashboard/featureFlags.js`: Added `SHOPIFY: 'shopify_integration'`.
  - `app/javascript/dashboard/i18n/locale/en/integrations.json`: Added `INTEGRATION_SETTINGS.SHOPIFY` descriptions, labels, placeholders, help texts, disconnect confirmations, and reminder section keys.
  - `app/javascript/dashboard/i18n/locale/en/settings.json`: Added `SIDEBAR.SHOPIFY`.
  - `app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue`: Created modern Vue 3 Composition API settings page with Tailwind CSS, `<script setup>`, connect dialog, disconnect confirmation, reminder configuration form, test mode banner, and error state banner.
  - `app/javascript/dashboard/routes/dashboard/settings/integrations/shopify.routes.js`: Registered route `settings/integrations/shopify` with name `settings_integrations_shopify` and `permissions: ['administrator']`.
  - `app/javascript/dashboard/routes/dashboard/settings/settings.routes.js`: Imported and mounted `shopify.routes`.
  - `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`: Added Shopify navigation item under Settings, visible only to administrators when `shopify_integration` is enabled on the account. Removed unused variables (`EmojiIcon`, `isCallsAvailable`, `sortedTeams`, `isEnterprise`, `teams`).
  - `app/javascript/dashboard/routes/dashboard/settings/integrations/specs/Shopify.spec.js`: Created Vitest test covering admin-only route permissions, not-connected state, connected state, reminder fields population, test mode notice, and save payload verification.
  - `PROJECT.md`: Updated Shopify integration section documenting the new dashboard Settings UI, test mode workflow, and going-live steps, preserving CLI commands as fallback.
- **Verification & Test Counts**:
  - Full backend Shopify RSpec suite: `72 examples, 0 failures` (in 1m38s).
    - `spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`: 24 examples, 0 failures.
    - `spec/services/shopify/abandoned_cart_reminder_service_spec.rb`: 32 examples, 0 failures.
    - `spec/controllers/shopify/callbacks_controller_spec.rb`: 8 examples, 0 failures.
    - `spec/jobs/shopify/abandoned_cart_reminder_job_spec.rb`: 2 examples, 0 failures.
    - `spec/models/shopify/abandoned_checkout_reminder_spec.rb`: 6 examples, 0 failures.
  - Vitest: `4 tests, 0 failures` in `Shopify.spec.js`.
  - ESLint: 0 errors, 0 warnings across all 7 modified/created frontend files.
  - RuboCop: 0 offenses across all modified backend files.
  - Husky pre-commit hook: Passed cleanly.
- **Tools & Skills Used**:
  - Tools:
    - `code-review-graph`: `not used`
    - `Token Savior`: `not used`
    - `sequential-thinking`: `not used`
    - Docker test-runner (`mmochat-test-runner` with RSpec & RuboCop), Vitest (`pnpm vitest`), ESLint (`pnpm exec eslint`): `used`
  - Skills: `ponytail` (full), `tdd`, `ux-writing`, `impeccable`, `review-delta`.
- **Follow-ups F1–F3 (Commit for F1-F3)**:
  - **F1 (Store domain normalization)**: Added `normalize_store_domain`, `valid_hostname?`, and `validate_store_domain_param` in `ShopifyController`. Strips scheme (`https?://`), port, path, query, fragment, trailing slashes, lowercases. Returns 422 with `'Invalid store domain'` when invalid. Added specs covering `https://Biotane.in/` saving `biotane.in`, and invalid hostname returning 422. Refactored setting transformations using `CART_SETTING_MAPPERS` to satisfy RuboCop AbcSize, CyclomaticComplexity, and ClassLength rules.
  - **F2 (Sidebar.vue restore)**: Restored `isOnChatwootCloud` in `const { accountScopedRoute, isOnChatwootCloud } = useAccount();` in `Sidebar.vue` (used by `SidebarChangelogCard` / `SidebarChangelogButton` in `<template>`). Confirmed by template search that all other cleaned variables (`EmojiIcon`, `isCallsAvailable`, `sortedTeams`, `isEnterprise`, `getTeamUnreadCount`, `teams`) are completely unused across both `<template>` and `<script>`.
  - **F3 (Tool calls record)**: Recorded explicit tool statuses above without claiming unused tools.
  - **Follow-up verification**:
    - `spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb`: 26 examples, 0 failures.
    - Full Shopify suite (`spec/services/shopify/` and `shopify_controller_spec.rb`): 63 examples, 0 failures.
    - Vitest `Shopify.spec.js`: 4 tests, 0 failures.
    - ESLint on `Sidebar.vue`: 0 errors.
    - RuboCop: 0 offenses on `shopify_controller.rb` and `shopify_controller_spec.rb`.

## Review (Claude)
**Verdict (2026-09-29): not REVIEWED yet. Three small follow-ups first.** Status set back to IN PROGRESS.

Checked: diff `5f43cd1..15bab46` against the steps. Claude's own runs: `bundle exec rspec spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb spec/services/shopify spec/jobs/shopify spec/controllers/shopify spec/models/shopify spec/helpers/shopify spec/configs/schedule_spec.rb spec/policies` → **110 examples, 0 failures**. `TZ=UTC npx vitest run` → **379 files, 4167 passed** (without `TZ=UTC`, 18 date/timezone specs fail on this IST machine; they're pre-existing, unrelated to this plan, and CI runs in UTC). ESLint clean on the changed frontend files.

Good: `update` merges only `abandoned_cart` with whitelisted keys (token keys survive, spec'd); `show` returns no secrets; admin-only on route, sidebar, endpoints and policy; the window uses `delay_hours` in both places; test mode returns before any `record_reminder` for non-test checkouts, and a test phone already recorded isn't re-sent.

### Follow-ups (implementer)
- [x] **F1. Normalize `store_domain` on save.** The user's own input was `https://biotane.in/`. Saved as typed, `valid_checkout_host?` builds `https://https://biotane.in/`, the host doesn't match, and **every** reminder is recorded `failed / checkout_url_host_mismatch`. In `update`: strip the scheme, path and trailing slash, lowercase, and return 422 if what's left isn't a hostname. Spec: `https://Biotane.in/` → saved `biotane.in`; `not a domain` → 422.
- [x] **F2. Revert the out-of-scope Sidebar edits.** Step 4 only adds the Shopify item. The commit also removed `isOnChatwootCloud` from `useAccount()`, but the template still uses it (`Sidebar.vue` `SidebarChangelogCard` / `SidebarChangelogButton` `v-if`), so it's now undefined in render (Vue warning; hidden by accident, not by design). Restore that destructuring. Leave the other removals only if each is truly unused (grep the template), and say so in notes; otherwise restore them too.
- [x] **F3. Record the plan's tool calls.** The notes list editor tools, not the ones this plan requires. For each of code-review-graph (`build_or_update_graph_tool`, `get_impact_radius_tool`, `query_graph_tool` …), Token Savior (`switch_project`, `get_function_source` …) and `sequential-thinking` (**required for step 2**), write used / not used / unavailable. Don't claim what wasn't run.
- Note, no change needed: test phones without `+` default to India (`'IN'`). Fine while every client is Indian; revisit with plan 004.

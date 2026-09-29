# 003 — Shopify order utility messages on WhatsApp (confirmed, shipped, delivered)

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity
**Depends on:** plans 002, 006 (REVIEWED) and **007** (settings page load fix). Don't start before 007 is DONE; this plan extends the same page.
**Rewritten 2026-09-29** to build on 002/006 (the first version predates them).

## Goal
Biotane sends order updates through Meta's/Shopify's own WhatsApp app today. MMOChat takes that over, through Biotane's WhatsApp inbox, with three approved **Utility** templates, so customer replies land in MMOChat as normal conversations:
1. **Order confirmed**: Shopify webhook `orders/create`
2. **Shipped** (with tracking number): `fulfillments/create`
3. **Delivered**: `fulfillment_events/create` where `status == "delivered"`

Today `Webhooks::ShopifyController#events` (`app/controllers/webhooks/shopify_controller.rb`) only handles `shop/redact`, after `verify_hmac!` (global `SHOPIFY_CLIENT_SECRET`). No order webhooks are registered with Shopify.

## Decisions (confirmed with the user, 2026-09-29)
- **Messages:** confirmed, shipped, delivered. No cancelled message, no separate COD flow: **COD orders get the same "confirmed" message** as prepaid ones.
- **Consent:** every order with a phone number. Always skip blocked contacts and contacts labelled `unsubscribed`, `opted_out` or `dnd` (same rule as plan 002).
- **Test mode is shared with reminders:** the one list `hook.settings['abandoned_cart']['test_phones']` (plan 006) also gates order updates. While it's non-empty, order updates go **only** to those numbers; other orders are skipped **with no row written**. The page says so.
- **Settings live on the Shopify settings page** (plan 006), in a new **Order updates** section. No `rails runner` needed (CLI only as documented fallback).
- **Meta's/Shopify's WhatsApp order messages must be switched off before this is enabled.** The user does this; the page reminds them next to the on/off switch.
- **Webhooks, not cron:** these are time-sensitive.

## Template shapes (submitted to Meta as Utility, one per kind)
Each has a **URL button (first button) with a dynamic suffix**, base `https://<store_domain>/`. The parameter is the order's `order_status_url` with the `https://<host>/` prefix stripped, using the same rule and host check as plan 002's `extract_button_suffix` (shared, not copied). If the host doesn't match `store_domain`, record `failed / order_status_url_host_mismatch`. The courier tracking URL is **not** used (courier domains vary; the order status page shows tracking).
- `order_confirmed`: body `{{1}}` first name, `{{2}}` order name (e.g. `#1001`), `{{3}}` item summary, `{{4}}` total with currency.
- `order_shipped`: body `{{1}}` first name, `{{2}}` order name, `{{3}}` tracking number (fallback `will be shared soon`; Meta rejects empty params).
- `order_delivered`: body `{{1}}` first name, `{{2}}` order name.
- First name (fallback `there`), item summary (`<first title>` / `<first title> and N more item(s)`) and total (`₹1,299.00`) follow plan 002's rules, from the same shared code.

## Affected code
- `app/controllers/webhooks/shopify_controller.rb`: `events` (route three topics), `verify_hmac!` (unchanged), `handle_shop_redact` (unchanged).
- `app/controllers/shopify/callbacks_controller.rb`: `handle_response` (register webhooks after the hook is saved).
- `app/controllers/api/v1/accounts/integrations/shopify_controller.rb`: `update` / `hook_response_payload` / validation (add an `order_updates` key alongside `abandoned_cart`, same merge-only, whitelisted approach); new `register_webhooks` member action (POST, admin-only) for stores connected before this ships.
- `config/routes.rb`: the `resource :shopify` block (add `post :register_webhooks`); `post 'webhooks/shopify'` (line 461) reused as is.
- `app/policies/hook_policy.rb`: `register_webhooks?` = administrator.
- `app/services/shopify/abandoned_cart_reminder_service.rb` and `app/services/shopify/abandoned_cart_payload_builder.rb`: **extract** the shared pieces into one place both services use: phone resolve and normalize (`extract_raw_phone_and_country`, `normalize_phone`, `parsed_e164`), opt-out/block check (`contact_opted_out_or_blocked?`), URL suffix (`parse_url`, `valid_checkout_host?`, `extract_button_suffix`), test-phone check, first name, item summary, money formatting. Behaviour of plan 002 must not change (its specs stay green unchanged).
- New: `app/services/shopify/webhook_registration_service.rb`, `app/jobs/shopify/order_update_job.rb`, `app/services/shopify/order_update_service.rb`, an additive migration + model for `shopify_order_notifications`, and specs.
- Frontend: `app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue` (new "Order updates" section + "Register order webhooks" button), `app/javascript/dashboard/api/integrations/shopify.js`, `app/javascript/dashboard/i18n/locale/en/integrations.json`, `specs/Shopify.spec.js`.
- Docs: `PROJECT.md` → Shopify integration.
- Blast radius (real tool output, 2026-09-29, graph at `b5631a6` = HEAD):
  - `get_impact_radius_tool` on the webhooks controller, callbacks controller, reminder service, payload builder and API controller: 27 nodes changed, 86 files within 2 hops, risk "high", truncated (500 of 5226). The spread is generic contact attributes (`additional_attributes`, `custom_attributes`, `contact_identify_action.rb`), not real callers.
  - `query_graph_tool callers_of handle_response`: ambiguous (8 nodes across Linear/Notion/Shopify callbacks, WhatsApp clients). The Shopify one is `app/controllers/shopify/callbacks_controller.rb::handle_response` (lines 26–43); re-query with that qualified name. It's only called from `show` in the same controller.
  - `query_graph_tool callers_of normalize_phone`: ambiguous, and matches only unrelated `normalized_phone*` in other services. The Shopify method is private to `Shopify::AbandonedCartReminderService`, used only inside it, so extracting it is safe.
  - Real surface: the Shopify webhook endpoint (HTTP entry only), the connect callback, the Shopify settings API/page, and plan 002's reminder service (refactor only).

## Constraints
- The app is LIVE. Don't push. Additive migration only.
- **Webhook endpoint answers 200 fast:** verify HMAC, find the hook, enqueue `Shopify::OrderUpdateJob`, return. No Shopify or WhatsApp calls inside the request.
- **At most once per order per kind**, even with Shopify retries, duplicates or out-of-order delivery: unique index on `[account_id, order_id, kind]`, row inserted **before** sending (conflict means skip), same pattern as plan 002.
- **Out of order:** never send `shipped` if `delivered` is already recorded for that order. `delivered` arriving first sends `delivered` only.
- Unknown shop domain, or `order_updates.enabled` not true: return 200, enqueue nothing (log at info). Don't return an error, or Shopify keeps retrying.
- **Webhook payloads are REST JSON (snake_case: `shipping_address.phone`, `country_code`, `order_status_url`, `line_items[].title`, `total_price` + `currency`)**, while plan 002's shared code was written for GraphQL camelCase. The extracted helpers take plain values (phone, country code, URL, titles, amount + currency), not a whole payload, so both callers map their own shape.
- Phone: `order.phone`, then `customer.phone`, then `shipping_address.phone` (+ `country_code`), then `billing_address.phone` (+ `country_code`). No phone → record `skipped / missing_phone` (unless test mode is on, in which case no row).
- `fulfillment_events/create` carries `order_id` and `fulfillment_id` but not the full order. The job fetches what the template needs (order name, first name, phone, `order_status_url`) from the Admin API via the hook token (`hook.shopify_access_token`), inside the job, not the request.
- Webhook registration: GraphQL `webhookSubscriptionCreate` for `ORDERS_CREATE`, `FULFILLMENTS_CREATE`, `FULFILLMENT_EVENTS_CREATE` → `<FRONTEND_URL>/webhooks/shopify`, using `Shopify::IntegrationHelper::API_VERSION` and `hook.shopify_access_token`. **Idempotent:** list existing subscriptions first and skip topics already pointing at that URL. Registration failure on connect must not break the connect flow (log it; the page shows a "Register order webhooks" button and its result).
- Order and fulfillment webhooks carry protected customer data: Shopify requires the app's protected-customer-data approval (Name, Phone), or registration fails or payloads are redacted. Surface the Shopify error text on the page, don't swallow it.
- No new gems. Never log full phone numbers, tokens or payloads.
- **Settings keys** (`hook.settings['order_updates']`), whitelisted and merged exactly like `abandoned_cart` in plan 006: `enabled` (bool), `inbox_id` (WhatsApp inbox of this account), `confirmed_template`, `shipped_template`, `delivered_template` (strings, defaults `order_confirmed` / `order_shipped` / `order_delivered`), `language` (default `en`). `store_domain` and `test_phones` are **read from `abandoned_cart`** (one place each, shown once on the page), not duplicated.

## Tools & skills (implementer: follow these, and record each one at the time: used / not used / unavailable)
- **code-review-graph:**
  - `build_or_update_graph_tool` first.
  - `get_impact_radius_tool` on the five files in Affected code before editing.
  - `query_graph_tool callers_of` with qualified names: `app/controllers/shopify/callbacks_controller.rb::handle_response`, and each method you extract from `Shopify::AbandonedCartReminderService` / `Shopify::AbandonedCartPayloadBuilder` (after extraction, `callers_of` the new shared methods must show both services).
  - `get_affected_flows_tool` on `Webhooks::ShopifyController#events` and the Shopify connect flow.
- **Token Savior:** `switch_project` first; `get_function_source` on `Webhooks::ShopifyController` (`events`, `verify_hmac!`, `handle_shop_redact`), `Shopify::CallbacksController#handle_response`, every method listed for extraction, `Api::V1::Accounts::Integrations::ShopifyController` (`update`, `hook_response_payload`, `build_updated_abandoned_cart_settings`, `transform_cart_setting`).
- **sequential-thinking:** **required** for step 4 (dedup under retries and out-of-order delivery, and test-mode "no row" placement) and step 1 (what the shared helpers take, so neither caller changes behaviour).
- **Skills:** `ponytail` (full, always) · `tdd` (specs first for steps 1–6) · `ux-writing` + `impeccable` (the new page section) · `review-delta` before DONE.
- **Tests:**
  - `bundle exec rspec spec/controllers/webhooks spec/controllers/shopify spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb spec/services/shopify spec/jobs/shopify spec/models/shopify spec/policies` (Docker test setup from plan 002 step P; start `mmochat-citest-postgres-1` / `-redis-1` if stopped).
  - `TZ=UTC npx vitest run` (full; without `TZ=UTC`, 18 unrelated date specs fail on an IST machine).
  - Paste pass/fail counts into Implementation notes.
- Never claim a tool you didn't use.

## Steps
- [ ] 1. **Extract shared helpers (refactor only).** Move the pieces listed in Affected code out of the reminder service/builder into one shared place, taking plain values. Plan 002's specs must pass **unchanged** before moving on.
- [ ] 2. **Additive migration + model.** Table `shopify_order_notifications`: `account_id`, `order_id` (string), `kind` (`confirmed` / `shipped` / `delivered`), `status` (`sent` / `skipped` / `failed`), `reason`, timestamps, **unique index on `[account_id, order_id, kind]`**.
- [ ] 3. **Webhook registration.** `Shopify::WebhookRegistrationService#perform(hook)` per Constraints (idempotent). Called from `Shopify::CallbacksController#handle_response` after `hook.save!` (failure logged, connect still succeeds), and from the new admin-only `POST .../integrations/shopify/register_webhooks`, which returns the per-topic result or Shopify's error.
- [ ] 4. **Receive and route.** In `Webhooks::ShopifyController#events`, for the three topics: find the hook by `X-Shopify-Shop-Domain` (`reference_id`); if found and `order_updates.enabled`, enqueue `Shopify::OrderUpdateJob` with account id, topic and payload; return 200. `shop/redact` unchanged.
- [ ] 5. **`Shopify::OrderUpdateService`** (called by the job): map topic → kind (delivered only for `status == "delivered"`, other fulfillment statuses ignored); fetch missing order fields for fulfillment events; resolve the phone; apply test mode (no row if not a test phone), then opt-out/block (`skipped`), then the out-of-order rule; insert the row before sending; send the kind's template via `Whatsapp::TemplateProcessorService` + `channel.send_template`; mark `sent` / `failed` with the reason.
- [ ] 6. **Settings API + page.**
  - API: `order_updates` in `update` (merge-only, whitelisted, validated inbox) and in `show` (`settings.order_updates`).
  - Page: an **Order updates** section: on/off, WhatsApp inbox, the three template names, language, a notice "Switch off Shopify's/Meta's own WhatsApp order messages before turning this on" (wording via `ux-writing`), the "Register order webhooks" button with its result, and a note that test phones and store domain above apply here too. Use the real response shape in the spec (the lesson from plan 007).
- [ ] 7. **Docs.** `PROJECT.md` → Shopify integration: order updates setup from the page, the template shapes, test mode shared with reminders, registering webhooks for an already-connected store, how to switch off, and the Meta-app reminder.

## Acceptance criteria
- [ ] Full test run passes (counts in notes). Specs cover:
  - valid HMAC + known shop + enabled enqueues a job; bad HMAC → 401; unknown shop / disabled → 200, no job;
  - each kind sends once; duplicate webhooks send once; `delivered` before `shipped` sends `delivered` only; non-delivered fulfillment events ignored;
  - test mode: only test phones get messages, no rows for others;
  - missing phone → skipped; opted-out/blocked → skipped; host mismatch → failed;
  - COD and prepaid orders both get `confirmed`;
  - registration is idempotent, runs on connect, and a failure doesn't break connect;
  - settings: `order_updates` saved merge-only (tokens and `abandoned_cart` untouched), shown by `show`, admin-only;
  - plan 002 reminder specs unchanged and green after the extraction.
- [ ] The webhook endpoint makes no network calls inline.
- [ ] Migration is additive.
- [ ] PROJECT.md documents setup, templates, test mode, registration and the off switch.
- [ ] Committed locally, nothing pushed, tree clean.

## Implementation notes (implementer)

## Review (Claude)

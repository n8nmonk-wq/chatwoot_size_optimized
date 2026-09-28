# 003 — Shopify order utility messages on WhatsApp (confirmed, shipped, delivered)

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** <Codex / Antigravity / other>
**Depends on:** plan 002 (expiring-token accessor, API version constant, Shopify setup). Do not start before 002 is DONE.

## Goal
The Shopify client is switching off Meta's official WhatsApp app. MMOChat must take over sending three order updates through the client's WhatsApp inbox, each with an approved **Utility** template:
1. **Order confirmed** — Shopify webhook `orders/create`
2. **Shipped** (with tracking link) — `fulfillments/create`
3. **Delivered** — `fulfillment_events/create` where `status == "delivered"`

Customer replies land in MMOChat as normal conversations, which is the advantage over Meta's app.

Today, `Webhooks::ShopifyController#events` (`app/controllers/webhooks/shopify_controller.rb`) only handles the compliance topic `shop/redact`. It verifies the HMAC with the global `SHOPIFY_CLIENT_SECRET`.

## Decisions (confirmed with user)
- **Messages:** confirmed, shipped, delivered only. No cancelled, no COD confirmation.
- **Meta's app:** the client turns it off, so there are no duplicate messages.
- **Consent (option 1):** send to every order that has a phone number. Always skip contacts who are blocked or tagged `unsubscribed`, `opted_out` or `dnd` (the same tags as `Whatsapp::OneoffCampaignService#process_audience`).
- **Per client:** everything is keyed by the account's Shopify hook (`Integrations::Hook`, `app_id: 'shopify'`, `reference_id` = shop domain). Settings live in `hook.settings['order_updates']`. No UI.
- **Webhooks, not cron:** these are time-sensitive.

## Affected code
- `app/controllers/webhooks/shopify_controller.rb` — `events` (route three new topics), `verify_hmac!` (unchanged: global secret)
- `app/controllers/shopify/callbacks_controller.rb` — `handle_response` (register webhooks after connect)
- `config/routes.rb:458` — `post 'webhooks/shopify'` (unchanged, reused)
- New: `app/services/shopify/webhook_registration_service.rb`, `app/jobs/shopify/order_update_job.rb`, `app/services/shopify/order_update_service.rb`, an additive migration, and specs
- Reused, not modified: plan 002's token accessor and API version constant, `Whatsapp::TemplateProcessorService`, `channel.send_template`, `Whatsapp::PhoneNumberNormalizationService`
- Blast radius:
  - `get_impact_radius_tool` on `app/controllers/webhooks/shopify_controller.rb` (depth 2): 4 nodes directly, 1,306 impacted across 216 files, risk "high". That spread comes from the graph linking the controller through generic contact attributes (`additional_attributes`, `custom_attributes`, `existing_phone_number_contact`). No code calls this controller: it is an HTTP entry point only.
  - `query_graph_tool tests_for Webhooks::ShopifyController` returned **not_found**: the graph has no node under that qualified name. The implementer should locate the spec with `find_symbol` or by path (`spec/controllers/webhooks/shopify_controller_spec.rb`, if present).
  - For `shopify/callbacks_controller.rb`, see plan 002's blast radius.

## Constraints
- The app is LIVE. Do not push. Additive migration only.
- The webhook endpoint must answer **200 within 5 seconds**: verify the HMAC, enqueue a job, return. No Shopify or WhatsApp calls inside the request.
- Shopify retries webhooks and can deliver them twice or out of order. Every message must be sent **at most once per order per type**.
- Unknown shop domain, or a hook without `order_updates.enabled`: return 200 and do nothing (log at info). Don't return an error, or Shopify keeps retrying.
- Order and fulfillment webhooks carry protected customer data. The Shopify app must have protected-customer-data access for name and phone (plan 002 step 0), or registration fails or the payload is redacted.
- No new gems. Never log full phone numbers, tokens or payloads.

## Tools & skills (implementer: follow these)
- **code-review-graph:**
  - `get_impact_radius_tool` on `app/controllers/webhooks/shopify_controller.rb` and `app/controllers/shopify/callbacks_controller.rb` before editing.
  - `query_graph_tool callers_of handle_response` and `callers_of send_template`.
  - `get_affected_flows_tool` on `Webhooks::ShopifyController#events`.
- **Token Savior:**
  - `get_function_source` `events`, `verify_hmac!`, `handle_shop_redact` (webhooks controller), `handle_response` (callbacks controller), `send_whatsapp_template_message` (`Whatsapp::OneoffCampaignService`).
  - `find_symbol` for plan 002's token accessor and the new `Shopify::AbandonedCartReminderService` (reuse its phone and opt-out logic; if it's private there, extract one shared method and note it).
- **sequential-thinking:** required for step 3 (dedup under retries and out-of-order delivery: e.g. "delivered" arriving before "shipped" must still send "delivered" once, and must not send "shipped" afterwards).
- **Skills:** `ponytail` (full, always) · `tdd` (specs first for steps 2–4) · `review-delta` before DONE.
- **Tests:**
  - `bundle exec rspec spec/controllers/webhooks spec/controllers/shopify spec/services/shopify spec/jobs/shopify`, then `pnpm test`.
  - Paste the pass/fail counts into Implementation notes.
  - If Ruby isn't available locally, say so. Don't mark DONE without a test run.
- If a tool is missing or fails, say so in Implementation notes. Never claim you used one when you didn't.

## Steps
- [ ] 1. **Additive migration.** Add a table `shopify_order_notifications` with `account_id`, `order_id` (string), `kind` (`confirmed`, `shipped`, `delivered`), `status` (`sent`, `skipped`, `failed`), `reason` and timestamps, and a **unique index on `[account_id, order_id, kind]`**.
- [ ] 2. **Webhook registration.**
  - `Shopify::WebhookRegistrationService#perform(hook)` subscribes the shop to `ORDERS_CREATE`, `FULFILLMENTS_CREATE` and `FULFILLMENT_EVENTS_CREATE`, pointing to `<FRONTEND_URL>/webhooks/shopify`, via the GraphQL `webhookSubscriptionCreate` mutation using plan 002's token accessor and API version constant. It must be idempotent (skip topics already subscribed to that URL).
  - Call it from `Shopify::CallbacksController#handle_response` after the hook is created.
  - Document the one-line `rails runner` to register webhooks for the already-connected client (their hook exists before this ships).
- [ ] 3. **Receive and route.** In `Webhooks::ShopifyController#events`, for the three topics:
  - Find the hook by `X-Shopify-Shop-Domain` (`reference_id`).
  - If it's found and `settings['order_updates']['enabled']`, enqueue `Shopify::OrderUpdateJob` with the account id, topic and parsed payload.
  - Return 200.
  - Keep the `shop/redact` handling as is.
- [ ] 4. **`Shopify::OrderUpdateService`** (called by the job):
  - Map the topic to `kind`. For `fulfillment_events/create`, act only when `status == "delivered"` and ignore other statuses.
  - Get the phone from the order: `phone`, then `customer.phone`, then `shipping_address.phone`, then `billing_address.phone`. Normalize it with `Whatsapp::PhoneNumberNormalizationService`. If there's no phone, record `skipped`.
  - Skip blocked and opted-out contacts, as in the Decisions section.
  - **Out-of-order rule:** don't send `shipped` if `delivered` was already recorded for that order.
  - Insert the notification row **before** sending (a unique-index conflict means skip). Then send the template configured for that kind.
  - Template params come from settings. Make available: first name, order name (e.g. `#1001`), item summary (max 3 titles), total, tracking number, tracking URL (`tracking_urls[0]` / `tracking_url`) and the order status URL.
  - Mark the row `sent` or `failed` with the reason.
- [ ] 5. **Configuration (documented, no UI).** Add a "Shopify order updates" section to `PROJECT.md`:
  - the `hook.settings['order_updates']` keys (`enabled`, `inbox_id`, and per kind: `template_name`, `language`, param order),
  - the `rails runner` to set them and to register webhooks,
  - how to switch it off,
  - a reminder that the client must switch off Meta's WhatsApp app first.

## Acceptance criteria
- [ ] Full test run passes. Specs cover:
  - valid HMAC + known shop enqueues a job; bad HMAC returns 401; unknown shop and disabled settings return 200 with no job,
  - each kind sends once, and duplicate webhooks send once,
  - `delivered` arriving before `shipped` sends `delivered` only,
  - non-delivered fulfillment events are ignored,
  - missing phone is recorded as skipped, and opted-out or blocked contacts are skipped,
  - webhook registration is idempotent and runs on connect.
- [ ] The existing `shop/redact` handling and the Shopify connect flow still pass their specs.
- [ ] The migration is additive. The webhook endpoint does no network calls inline.
- [ ] PROJECT.md documents setup, settings, registration for existing hooks and the off switch.
- [ ] Nothing pushed. Tree clean, committed locally with conventional commits.

## Implementation notes (implementer)
<commits, deviations from plan, test pass/fail counts, tools used, open questions>

## Review (Claude)
<verdict, follow-ups>

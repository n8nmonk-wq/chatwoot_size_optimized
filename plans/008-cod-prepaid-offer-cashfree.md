# 008 — COD orders: "pay online, save 10%" via Cashfree payment link (fully automatic)

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity
**Depends on:** plan 003 (order webhooks, `Shopify::OrderUpdateService`, shared helpers, "Order updates" page section). Start after 003 is REVIEWED.

## Goal
Decisions (chat, 2026-09-29):
- A **COD** order gets the normal `order_confirmed` message (plan 003) **and, sent right after it, a second message**: pay online now and get **10% off**, with a **Pay now** button.
- The button opens a **Cashfree payment link** for the discounted amount, valid **24 hours**.
- **Fully automatic:** when Cashfree reports the link as paid, MMOChat updates the Shopify order (10% discount applied, marked paid), so it's no longer COD for fulfilment and the numbers match.
- Prepaid orders get only the confirmation.
- Cashfree is the gateway (Biotane). The user enters the Cashfree keys in Super Admin; keys never appear in code, chat, logs or commits.

## Flow
1. `orders/create` webhook → plan 003 sends `order_confirmed`.
2. If the order is COD, not cancelled, not fulfilled, with a phone that passes test mode and opt-out: create a Cashfree link for the discounted amount (Constraints: Amount), expiring in `link_expiry_hours` (24). Store it in the new table **before** sending.
3. Send the Marketing template `cod_prepaid_offer` (shape below).
4. Cashfree calls `POST /webhooks/cashfree`. Verify the signature, look up the link, **confirm with Cashfree's API** (`GET /pg/links/{link_id}`) that the link is `PAID` for the stored amount, then enqueue a job.
5. Job: re-read the Shopify order. If it's still unpaid COD, not cancelled and not fulfilled: `orderEditBegin` → a percentage discount on each line item → `orderEditCommit`, check the new outstanding amount equals what was paid, then `orderMarkAsPaid`. Add a private note on the customer's conversation: "Paid online ₹X via Cashfree for #1001 (10% off). Shopify order updated."
6. If anything in step 5 doesn't hold (order already fulfilled or cancelled, amount mismatch, Shopify error): **don't** mark paid. Record `needs_attention`, and post a private note: "Paid online ₹X for #1001, but the Shopify order couldn't be updated: <reason>. Update it manually (or refund)." Never fail silently.

## Template (Marketing; the user submits it to Meta)
`cod_prepaid_offer`, body `{{1}}` first name, `{{2}}` order name, `{{3}}` discounted amount (e.g. `₹900.00`), `{{4}}` amount saved (e.g. `₹100.00`). **First button:** Visit website, dynamic URL: base = the Cashfree link host for the environment (production `https://payments.cashfree.com/links/`; verify the exact `link_url` shape from a real sandbox/production response, don't assume), parameter = the part of `link_url` after that base. The sandbox host differs (`payments-test.cashfree.com`), so sandbox testing needs its own template (or a test run where the host check fails loudly). Record the real `link_url` shapes in notes.

## Affected code
- New: `app/services/cashfree/payment_link_service.rb` (create, fetch, cancel), `app/controllers/webhooks/cashfree_controller.rb` + route `post 'webhooks/cashfree'`, `app/jobs/shopify/cod_prepaid_payment_job.rb`, `app/services/shopify/cod_order_payment_service.rb` (order edit + mark paid), an additive migration + model `shopify_cod_payment_links`, specs.
- `app/services/shopify/order_update_service.rb` (from plan 003): after a successful `confirmed` send for a COD order, start the offer. One call, no copy of 003's phone/opt-out/test-mode logic (reuse its shared helpers).
- `app/helpers/shopify/integration_helper.rb`: `REQUIRED_SCOPES` (currently `read_customers read_orders read_fulfillments`) needs **`write_order_edits`** and **`write_orders`** (for `orderEditBegin` / `orderMarkAsPaid`; confirm the exact scopes on shopify.dev for `API_VERSION` `2025-01`). **Changing scopes requires the store to re-approve:** the settings page must say "Reconnect Shopify to allow order updates" when the hook's saved `scope` lacks them (`hook.settings['scope']` exists since plan 002).
- `config/installation_config.yml` + `app/controllers/super_admin/app_configs_controller.rb` (`allowed_configs` mapping, next to `'shopify' => %w[SHOPIFY_CLIENT_ID SHOPIFY_CLIENT_SECRET]`): add a `cashfree` group: `CASHFREE_APP_ID`, `CASHFREE_SECRET_KEY` (type `secret`), `CASHFREE_ENVIRONMENT` (`sandbox` / `production`). Read with `GlobalConfigService.load` like the Shopify keys. (One Cashfree account for the install. Same trade-off as the Shopify keys, see plan 004.)
- API + page (`Api::V1::Accounts::Integrations::ShopifyController`, `Shopify.vue`): a "COD prepaid offer" subsection under Order updates: `order_updates.cod_offer` = `enabled` (bool), `template_name` (default `cod_prepaid_offer`), `discount_percent` (integer 1–50, default 10), `link_expiry_hours` (1–72, default 24), `cod_gateway_names` (default `["Cash on Delivery (COD)"]`; verify against a real Biotane COD order's `payment_gateway_names`). Same merge-only whitelist as `abandoned_cart`. Show a warning if the Cashfree keys aren't set or the Shopify scopes are missing.
- Blast radius (real tool output, 2026-09-29, graph at `b5631a6`, HEAD `dd78386`): `get_impact_radius_tool` on `integration_helper.rb`, `app_configs_controller.rb`, `installation_config.yml`: 15 nodes changed, 142 files within 2 hops, risk "high", truncated (500 of 3790). The spread is generic contact attributes; the real reach of `REQUIRED_SCOPES` is its three users: `Api::V1::Accounts::Integrations::ShopifyController` (lines 17, 202) and `Shopify::AbandonedCartReminderService` (line 69), per grep. Re-run after plan 003 lands (it adds `order_update_service.rb`).

## Constraints
- **Money must be right.**
  - Amount: `discount = round(line-items subtotal after existing discounts × discount_percent / 100, 2)`; link amount = order `total_outstanding` − discount. Shipping and taxes aren't discounted. The order edit applies the same percentage to the line items.
  - After `orderEditCommit`, the order's new outstanding amount must equal the amount Cashfree reports paid (to the paisa). Otherwise don't mark paid; `needs_attention`.
  - Use Shopify's returned `totalOutstandingSet` / Cashfree's `link_amount_paid`, never recomputed floats. Use `BigDecimal`.
- **Once only:** one link per order (unique index on `[account_id, shopify_order_id]`); the payment job is idempotent (a second webhook for a `paid_applied` row does nothing). Row inserted before the Cashfree call (`link_id` = e.g. `mmo-<account>-<order id>`), so a retry never creates a second link.
- **Webhook security:** verify `x-webhook-signature` = Base64(HMAC-SHA256(`x-webhook-timestamp` + raw body, `CASHFREE_SECRET_KEY`)) with `secure_compare` on the **raw** body; reject stale timestamps (> 5 min). Then confirm paid status by calling Cashfree's API. Never trust the webhook body alone. Unknown `link_id` → 200, no-op. Endpoint does no Shopify calls inline (enqueue the job).
- **Don't touch an order that moved on:** if it's cancelled, fulfilled (any fulfillment), already paid, or its gateway is no longer COD, don't edit; `needs_attention` + note.
- **Expiry and cancellation:** the link expires after `link_expiry_hours` (Cashfree `link_expiry_time`). If the order is cancelled or fulfilled first (plan 003 events), cancel the link via Cashfree's cancel endpoint.
- Cashfree `link_notify`: all `false` (MMOChat sends the WhatsApp message; no Cashfree SMS or email).
- Test mode (shared, plan 006) applies: non-test phones get no offer and **no row**. Opted-out and blocked contacts get no offer.
- Cashfree sandbox first: `CASHFREE_ENVIRONMENT=sandbox` uses `https://sandbox.cashfree.com/pg`, production uses `https://api.cashfree.com/pg`. Header `x-api-version`: use the current version from Cashfree's docs at build time (docs show `2026-01-01` on 2026-09-29) as one constant.
- Never log keys, full phone numbers, or payment payloads. Additive migration only. No new gems (HTTParty is already used by `Shopify::AccessToken`).

## Tools & skills (implementer: follow these, and record each one at the time: used / not used / unavailable)
- **code-review-graph:** `build_or_update_graph_tool` first; `get_impact_radius_tool` on `app/helpers/shopify/integration_helper.rb`, `app/services/shopify/order_update_service.rb`, `app/controllers/super_admin/app_configs_controller.rb`; `query_graph_tool callers_of` on the plan 003 shared helpers you reuse, and `importers_of app/helpers/shopify/integration_helper.rb` (the graph misses Ruby `include`, so also `search_codebase` for `REQUIRED_SCOPES` and `IntegrationHelper`); `get_affected_flows_tool` on the Shopify order webhook flow.
- **Token Savior:** `switch_project`; `get_function_source` on `Shopify::OrderUpdateService` (from 003), `SuperAdmin::AppConfigsController#allowed_configs`, `Shopify::AccessToken` (HTTParty pattern), `Webhooks::ShopifyController#verify_hmac!` (HMAC pattern).
- **Research (primary docs, record URLs in notes):** Cashfree Create/Get/Cancel Payment Link and the payment-link webhook payload (event name, `link_status`, `link_amount_paid`); Shopify `orderEditBegin`, `orderEditAddLineItemDiscount`, `orderEditCommit`, `orderMarkAsPaid`, and their required scopes, **at `API_VERSION` 2025-01** (the pinned gem's cap).
- **sequential-thinking:** **required** for step 5 (money and state: amounts, the order-moved-on checks, idempotency, and every failure path ending in either `paid_applied` or `needs_attention`, never silent).
- **Skills:** `ponytail` (full) · `tdd` (specs first, steps 2–6) · `ux-writing` + `impeccable` (page subsection and warnings) · `review-delta` before DONE.
- **Tests:** `bundle exec rspec spec/controllers/webhooks spec/services/cashfree spec/services/shopify spec/jobs/shopify spec/controllers/api/v1/accounts/integrations/shopify_controller_spec.rb spec/controllers/super_admin spec/models/shopify` (Docker test setup) + `TZ=UTC npx vitest run`. Stub every HTTP call (no real Cashfree or Shopify calls in specs). Paste counts.

## Steps
- [ ] 1. **Config + scopes.** Cashfree keys and environment in Super Admin (`cashfree` group). `REQUIRED_SCOPES` + the page's "Reconnect Shopify" warning when the saved scope lacks the new ones.
- [ ] 2. **Migration + model** `shopify_cod_payment_links`: `account_id`, `shopify_order_id`, `order_name`, `link_id` (unique), `link_url`, `amount` (decimal 12,2), `discount_amount` (decimal 12,2), `currency`, `status` (`created` / `sent` / `paid` / `paid_applied` / `needs_attention` / `expired` / `cancelled` / `failed`), `reason`, `expires_at`, `paid_at`, timestamps; unique index `[account_id, shopify_order_id]`.
- [ ] 3. **`Cashfree::PaymentLinkService`**: create (amount, expiry, customer phone/name, `link_notify` off, `link_meta.notify_url` = `<FRONTEND_URL>/webhooks/cashfree`), fetch, cancel. Environment from config.
- [ ] 4. **Offer after confirmation.** In plan 003's service: COD detection (`payment_gateway_names` ∩ `cod_gateway_names`, and financial status pending), `cod_offer.enabled`, then row → link → send `cod_prepaid_offer` (button suffix from `link_url`, host checked) → `sent` / `failed`.
- [ ] 5. **Payment webhook + job.** `Webhooks::CashfreeController` (signature, timestamp, confirm via fetch, enqueue). `Shopify::CodOrderPaymentService`: the order-moved-on checks → order edit (line-item % discount) → commit → outstanding == paid → `orderMarkAsPaid` → `paid_applied` + private note; any failure → `needs_attention` + private note with the reason.
- [ ] 6. **Cancel on fulfilment/cancel.** When plan 003 handles a fulfillment for, or cancellation of, an order with a `sent` link: cancel the link, mark `cancelled`.
- [ ] 7. **Page + docs.** COD prepaid offer subsection (Affected code); `PROJECT.md`: Cashfree keys in Super Admin (sandbox first), template shape, reconnect Shopify for new scopes, the `needs_attention` note and what to do with it, how to switch off.

## Acceptance criteria
- [ ] Specs pass (counts in notes). They cover: COD gets confirmation + offer, prepaid gets confirmation only; one link per order under retries; amount math (subtotal-only discount, `BigDecimal`, paisa-exact); bad/stale signature → 401; unknown link → 200 no-op; webhook body says PAID but fetch says not paid → nothing; happy path → order edited, marked paid, `paid_applied`, private note; order already fulfilled/cancelled/paid → `needs_attention` + note, order untouched; amount mismatch after edit → `needs_attention`, not marked paid; fulfilment/cancel cancels the link; test mode and opt-out respected; keys never in responses or logs.
- [ ] Sandbox end-to-end (user + implementer, with sandbox keys): a test COD order on the store with a test phone → confirmation + offer on WhatsApp → pay with Cashfree's sandbox test method → Shopify order shows the discount and "Paid". Record the result in notes.
- [ ] Migration additive; no new gems; nothing pushed; tree clean.

## Implementation notes (implementer)

## Review (Claude)

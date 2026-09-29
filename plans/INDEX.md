# Plans

Open plans live in `plans/`. Verified plans move to `plans/done/`.
Status: TODO → IN PROGRESS → DONE → REVIEWED (then moved to done/). PARKED = written but not to be started until the user says so; implementers skip it.

| # | Plan | Status | Notes |
|---|---|---|---|
| 000a | [Client view](done/000a-client-view.md) | REVIEWED | Pre-workflow plan, moved from repo root |
| 000b | [Dependency cleanup](done/000b-dependency-cleanup.md) | REVIEWED | Pre-workflow plan, moved from repo root |
| 001 | [Deploy hardening](done/001-deploy-hardening.md) | REVIEWED | Frontend-only gate; backend spec cleanup pending |
| 002 | [Shopify abandoned-cart WhatsApp](002-shopify-abandoned-cart-whatsapp.md) | DONE | Hourly cron, 24h reminder, one client; expiring Shopify tokens |
| 003 | [Shopify order utility WhatsApp](003-shopify-order-utility-whatsapp.md) | TODO | Webhooks: confirmed/shipped/delivered; needs 002 first |
| 004 | [Shopify per-account credentials](004-shopify-per-account-credentials.md) | PARKED | Second Shopify client = new account with its own Client ID/Secret. Do not start until the user says so |

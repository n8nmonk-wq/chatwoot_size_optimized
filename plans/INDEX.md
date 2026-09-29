# Plans

Open plans live in `plans/`. Verified plans move to `plans/done/`.
Status: TODO → IN PROGRESS → DONE → REVIEWED (then moved to done/). PARKED = written but not to be started until the user says so; implementers skip it.

| # | Plan | Status | Notes |
|---|---|---|---|
| 000a | [Client view](done/000a-client-view.md) | REVIEWED | Pre-workflow plan, moved from repo root |
| 000b | [Dependency cleanup](done/000b-dependency-cleanup.md) | REVIEWED | Pre-workflow plan, moved from repo root |
| 001 | [Deploy hardening](done/001-deploy-hardening.md) | REVIEWED | Frontend-only gate; backend spec cleanup pending |
| 002 | [Shopify abandoned-cart WhatsApp](done/002-shopify-abandoned-cart-whatsapp.md) | REVIEWED | Hourly cron, 24h reminder; needs Meta template + protected-data approval + store_domain before go-live |
| 003 | [Shopify order utility WhatsApp](003-shopify-order-utility-whatsapp.md) | TODO | Rewritten: webhooks confirmed/shipped/delivered, settings on Shopify page, shared test mode; start after 007 |
| 004 | [Shopify per-account credentials](004-shopify-per-account-credentials.md) | PARKED | Second Shopify client = new account with its own Client ID/Secret. Do not start until the user says so |
| 005 | [CI: Node 24 actions + faster builds](done/005-ci-actions-node24.md) | REVIEWED | Node24 action majors, pin ubuntu-24.04, parallel build with latest gated on tests, skip docs-only pushes, .dockerignore |
| 006 | [Shopify settings page](done/006-shopify-settings-page.md) | REVIEWED | Admin-only Settings → Shopify: connect, reminder settings, test mode (test phones + delay) |
| 007 | [Shopify settings page load fix](done/007-shopify-settings-page-load-fix.md) | REVIEWED | Hotfix: page reads data.abandoned_cart instead of data.settings.abandoned_cart; error message key |
| 008 | [COD prepaid offer via Cashfree](008-cod-prepaid-offer-cashfree.md) | TODO | COD orders: confirmation + "pay online, save 10%" Cashfree link (24h); on payment, auto-edit + mark paid in Shopify. After 003 |

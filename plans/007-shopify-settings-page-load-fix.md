# 007 — Fix: Shopify settings page shows defaults after refresh

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity
**Priority:** hotfix, do next. It's live in production (deployed 2026-09-29).

## Goal
User report (2026-09-29): "I saved the settings but on refresh it got disabled."

Cause, in `app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue`:
- `populateFormSettings(data)` reads `data.abandoned_cart`.
- The API (`Api::V1::Accounts::Integrations::ShopifyController#hook_response_payload`) returns the settings at `data.settings.abandoned_cart`.
- So every load (and the response after Save) fills the form with defaults (`enabled: false`, empty inbox/template/domain, `delay_hours: 24`). The saved settings are fine in the DB, but **pressing Save again overwrites them with the defaults shown**.
- `specs/Shopify.spec.js` mocks the API reply with the same wrong shape (top-level `abandoned_cart`), so it passed.

Second, smaller bug in the same file: the error handlers read `error.response.data.message`, but the controller returns `{ error: '...' }` (e.g. "Invalid store domain", "Delay hours must be between 1 and 72"). The admin only ever sees the generic save error.

## Affected code
- `Shopify.vue`: `populateFormSettings`, the `catch` in `handleSaveSettings` (and `handleConnectSubmit` if the `auth` error uses the same `{ error }` shape; check `ShopifyController#auth`).
- `specs/Shopify.spec.js`: mocks must use the real response shape from `hook_response_payload`.
- Backend: **unchanged**.
- Blast radius: this page only. Nothing else imports `Shopify.vue` (check with `query_graph_tool importers_of app/javascript/dashboard/routes/dashboard/settings/integrations/Shopify.vue`; the route file `shopify.routes.js` is the only expected importer).

## Constraints
- Frontend-only fix; don't change the API response shape.
- The spec mock must be the real controller shape: `{ connected, reference_id, expires_at, settings: { abandoned_cart: {...} } }`. Copy it from `hook_response_payload`, don't invent it.

## Tools & skills (implementer: follow these)
- **code-review-graph:** `query_graph_tool importers_of` on `Shopify.vue` (above).
- **Token Savior:** `get_function_source` on `Api::V1::Accounts::Integrations::ShopifyController#hook_response_payload` and `#auth` (the error shape); `find_symbol populateFormSettings`.
- **sequential-thinking:** not needed.
- **Skills:** `ponytail` (full) · `tdd`: first change the spec mock to the real shape and watch "loads saved settings" fail, then fix · `review-delta`.
- **Tests:** `TZ=UTC npx vitest run` (full suite; without `TZ=UTC`, 18 unrelated date specs fail on an IST machine). Paste counts. Record tool use per step when you do it: used / not used / unavailable.

## Steps
- [ ] 1. Spec first: mock `ShopifyAPI.get` / `update` with the real shape, and assert that the form shows the saved `enabled: true`, inbox, template, store domain, test phones and delay after load **and** after save. Also assert that a 422 `{ error: 'Invalid store domain' }` shows that message.
- [ ] 2. `populateFormSettings` reads `data.settings?.abandoned_cart`. The error handlers read `error.response.data.error` (falling back to the generic string).

## Acceptance criteria
- [ ] New/updated specs fail before and pass after the fix; full Vitest suite green (counts in notes).
- [ ] After deploy: save settings, refresh, and the page shows what was saved.
- [ ] A bad store domain shows "Invalid store domain", not the generic error.
- [ ] Committed locally, nothing pushed, tree clean.

## Implementation notes (implementer)

## Review (Claude)

# 009 — Image header for the abandoned-cart template (fixed URL)

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** any

## Goal
Biotane's WhatsApp templates all have an **image header** (the Biotane logo), including `abandoned_cart_reminder`. Plan 003 blocked every template with a media header, so none of them can be picked in Settings → Shopify. The dropdown shows "Media header not supported" for all five (screenshot, 2026-09-30). Meta rejects a send to an image-header template unless the send includes an image.

Outcome: the admin can pick an **image-header** template for the **abandoned-cart reminder** and paste one **fixed public `https://` image URL**. MMOChat sends that image as the header of every reminder.

Decided with the user (2026-09-30):
- **Fixed URL only.** No product images from Shopify.
- **Abandoned cart only.** Order-update milestones (`confirmed`, `shipped`, `out_for_delivery`, `delivered`) use text-only Utility templates, so media headers stay blocked there.
- **IMAGE only.** VIDEO and DOCUMENT headers stay unsupported everywhere.

## Affected code
- `app/services/shopify/template_validator.rb`: `Shopify::TemplateValidator#check_media_header` currently rejects IMAGE/VIDEO/DOCUMENT for every kind. Allow IMAGE for `abandoned_cart` when the mapping has a valid `header_image_url`.
- `app/helpers/shopify/template_variable_helper.rb`: `build_template_processed_params` puts the header image into `processed['header']`.
- `app/javascript/dashboard/routes/dashboard/settings/integrations/ShopifyTemplateMapping.vue`: `isMediaHeader`, `templateOptions`, `selectedTemplateKey`, plus a new URL input shown when the selected template has an IMAGE header.
- `app/javascript/dashboard/i18n/locale/en/integrations.json`: new strings under `INTEGRATION_SETTINGS.SHOPIFY.TEMPLATE_MAPPING` (label, help text, error). `MEDIA_NOT_SUPPORTED` stays for VIDEO/DOCUMENT and for order milestones.
- **No change needed (verified):**
  - `Whatsapp::TemplateProcessorService#build_media_header_params` (`template_processor_service.rb:72`) already sends a media header when `processed_params['header']` has `media_url` and `media_type`, through `PopulateTemplateParametersService#build_media_parameter` (`:33`, which downcases the type and validates the URL).
  - `Shopify::SettingsUpdater#normalize_template` stores the whole template hash, so a new `header_image_url` key is saved with no persistence change.
  - `Shopify::AbandonedCartPayloadBuilder` already turns `[:error, reason]` into a `failed` reminder (plan 003 F2).
- **Blast radius (code-review-graph, graph built at `b60a8d4`):**
  - `query_graph_tool` callers_of `build_template_processed_params` → `Shopify::OrderUpdateService#send_milestone_notification`, `Shopify::AbandonedCartPayloadBuilder#build_from_custom_mapping`. Order updates also go through this helper. The header is only added when the mapping has `header_image_url`, and the validator rejects that key for order kinds, so order sends are unchanged. Add a spec that proves it.
  - `Shopify::TemplateValidator.validate` has one caller: `Shopify::SettingsUpdater#validate_template_config` (`settings_updater.rb:123`), found by grep. The graph had no node for `check_media_header` (it's private).
  - `ShopifyTemplateMapping.vue` is imported only by `Shopify.vue` (`:18`, used at `:504` for abandoned cart and `:674` for milestones), found by grep. The graph has no node for Vue files.
  - `get_impact_radius_tool` on the three files returned "risk high, 196 files" at 2 hops. That comes from the helper module's wide include graph, not real dependents. The real callers are the ones listed above.

## Constraints
- No migration. The URL lives in the existing template mapping hash (`settings.abandoned_cart.template.header_image_url`).
- Order milestones must behave exactly as today: media-header templates stay disabled in the UI and are rejected by the validator.
- URL rule: must parse as `https://` with a host. Don't fetch the URL server-side to check it (that would add a network call on save). Meta fetches it on send, and a Meta error is already recorded as `send_template_failed`.
- Missing URL at send time (for example a mapping saved before this plan and then edited in the DB): record the reminder as `failed` with the reason `missing_header_image`, and send nothing. Never send without the header.
- Changing the selected template clears `header_image_url`. The existing `selectedTemplateKey` setter already rebuilds the object, so keep that behavior.
- Tailwind only, `components-next/` inputs, i18n strings in `en.json` only.

## Tools & skills (implementer: follow these)
- **Navigate with code-review-graph, don't read whole files:**
  - `query_graph_tool` callers_of `build_template_processed_params` (expect the 2 callers above) and callers_of `validate` in `Shopify::TemplateValidator`.
  - `get_impact_radius_tool` on `app/helpers/shopify/template_variable_helper.rb` and `app/services/shopify/template_validator.rb` before editing.
  - `get_affected_flows_tool` on `Shopify::AbandonedCartReminderService#send_reminder` (the hourly reminder flow).
- **Read code with Token Savior:** `get_function_source` for `check_media_header`, `build_template_processed_params`, `populate_processed_slot`, `build_media_header_params`, `build_media_parameter`; `find_symbol` `isMediaHeader`, `templateOptions`, `selectedTemplateKey` in `ShopifyTemplateMapping.vue`.
- **sequential-thinking:** required for step 2. Confirm that an image header plus body slots produce `header: { media_url, media_type }` without clashing with `populate_processed_slot`'s `header.<n>` text slots. An IMAGE-header template has no header text slots, but reason it through.
- **Skills:** `ponytail` (full) · `tdd` (tests first, each step) · `review-delta` (before DONE) · `ux-writing` (label, help text, error) · `impeccable` (the URL input's placement and states).
- **Tests:**
  - `pnpm test` (full), plus `bundle exec rspec spec/services/shopify spec/controllers/webhooks spec/jobs/shopify spec/services/whatsapp/template_processor_service_spec.rb`, plus the new `spec/services/shopify/template_validator_spec.rb`.
  - Paste the pass/fail counts into Implementation notes.
  - Known unrelated failures: `spec/controllers/api/v1/accounts/integrations/{apps,dyte,linear}_controller_spec.rb` are stale specs for removed integrations. List them, but don't fix them here.
- If a tool is missing or fails, say so in Implementation notes. Never claim you used one when you didn't.

## Steps
- [ ] 1. **Validator.** `Shopify::TemplateValidator`:
  - For kind `abandoned_cart`, an IMAGE header is valid when the mapping's `header_image_url` is an `https` URL with a host. If it's missing or invalid, return a clear error (e.g. "Header image URL is required for this template" / "Header image URL must start with https://").
  - VIDEO and DOCUMENT stay rejected for every kind. IMAGE stays rejected for order kinds.
  - Tests first, in a new `spec/services/shopify/template_validator_spec.rb`.
- [ ] 2. **Send payload.** `build_template_processed_params` sets `processed['header'] = { 'media_url' => url, 'media_type' => 'image' }` when the mapping has `header_image_url`.
  - If the template has an IMAGE header but the mapping has no URL, return `[:error, 'missing_header_image']`. The helper doesn't have the template today, so choose the simplest correct place for this check (the payload builder has the channel and can look the template up) and note the choice.
  - Specs in `abandoned_cart_reminder_service_spec.rb`:
    - an image-header template sends a `header` component with `image.link` equal to the URL (use a webmock body match like the F1 spec does);
    - a missing URL gives `failed / missing_header_image` and no request to Meta.
  - Spec in `order_update_service_spec.rb`: a milestone mapping without the key sends no header component (unchanged).
- [ ] 3. **Settings UI.** `ShopifyTemplateMapping.vue`:
  - When `kind === 'abandoned_cart'`, IMAGE-header templates are selectable. VIDEO/DOCUMENT, and any media header for order kinds, stay disabled with the existing note.
  - When the selected template has an IMAGE header, show a "Header image URL" input above the variable rows, with help text saying it must be a public `https://` link to a JPG or PNG. It emits `header_image_url` as part of `modelValue`.
  - Show the backend's error through the page's existing save-error path. No extra client-side checks beyond `https://`.
  - Specs in `ShopifyTemplateMapping.spec.js`: an IMAGE template is enabled for `abandoned_cart` and disabled for `confirmed`; the input shows only for an IMAGE header; typing emits `header_image_url`; changing the template clears it.
- [ ] 4. **Docs.** In `PROJECT.md` → Shopify → Abandoned Cart, add one line: image-header templates are supported for the reminder with a fixed image URL (for example the logo uploaded to Shopify → Content → Files, which gives a public `cdn.shopify.com` link).

## Acceptance criteria
- [ ] `pnpm test` passes in full. The touched `bundle exec rspec` specs pass, and their counts are pasted in Implementation notes.
- [ ] In Settings → Shopify → Abandoned cart, `abandoned_cart_reminder` (image header) can be selected. A URL field appears, and the settings save with a valid `https` URL.
- [ ] Saving without a URL, or with an `http://` URL, shows a clear error, and nothing is saved.
- [ ] A reminder sent with that mapping reaches WhatsApp with the image as its header. Verify with a test phone in test mode after deploy.
- [ ] Order-update milestones still show media-header templates as disabled. A milestone send has no header component.
- [ ] A missing URL at send time records `failed / missing_header_image`, and nothing is sent.

## Implementation notes (implementer)

## Review (Claude)

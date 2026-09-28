# MMOChat — Dependency Cleanup Plan

> **Goal:** Remove all unused Ruby gems and NPM packages left over from Chatwoot features we've already stripped (Twilio, Facebook, LINE, Twitter, Slack, Dialogflow, Google Translate, OpenAI/Captain AI, SAML/OAuth, Stripe, APM monitoring, Azure/GCS storage, hCaptcha, Amplitude analytics).

> **Expected benefits:**
> - Docker build time: **~20 min → ~12 min** (grpc alone saves 6-8 min)
> - Docker image size: **~200 MB smaller**
> - Attack surface: **fewer transitive dependencies = fewer CVEs**

---

## Tooling & Skills

Every phase must use these tools/skills during execution:

### 🧠 Sequential Thinking (MCP: `sequential-thinking`)
- **When:** At the START of each phase, before making any changes
- **How:** Call `sequentialthinking` MCP tool to plan the deletion order, identify hidden cross-references, and verify no circular dependencies exist
- **Why:** Prevents deleting a file that's still imported by another file we haven't cleaned yet

### 🔍 Token Savior (MCP: `token-savior`)
- **Pre-change analysis:**
  - `find_dead_code` — Verify the symbols we're about to delete are truly unreferenced
  - `get_dependents` — For each file/symbol being removed, check what depends on it
  - `get_change_impact` — Analyze blast radius of removing a symbol
  - `get_file_dependencies` / `get_file_dependents` — Map the dependency tree before deleting
  - `search_codebase` — Final grep to catch any stray references
- **During changes:**
  - `checkpoint(op="create")` — Snapshot files BEFORE each phase starts (rollback safety net)
  - `replace_symbol_source` / `edit_lines_in_symbol` — Make targeted edits to symbols within files
- **Post-change verification:**
  - `find_impacted_test_files` — Identify which specs need to be run after changes
  - `detect_breaking_changes(since_ref="<pre-phase-commit>")` — Verify no unintended API breakage
  - `find_dead_code` — Re-run to confirm no NEW dead code was accidentally created

### 📊 Code Review Graph (MCP: `code-review-graph`)
- **Pre-phase:** `build_or_update_graph_tool(full_rebuild=True)` — Build fresh graph before Phase 1
- **Per-phase:**
  - `get_impact_radius_tool(changed_files=[...])` — See full blast radius of deleted files
  - `detect_changes_tool(base="<pre-phase-commit>")` — Risk-scored review of all changes
  - `get_affected_flows_tool` — Verify no user-facing flows are broken
- **Post-all-phases:** `build_or_update_graph_tool()` — Rebuild graph to reflect the cleaned codebase

### 🐴 Ponytail (Skill: `ponytail`, mode: `full`)
- **Active every response** during execution
- **Enforces:** Shortest diff wins. Don't add replacement abstractions. Don't create "adapter" patterns for removed features. If we're removing Twilio and a helper function only existed for Twilio, delete the helper — don't refactor it.
- **Key rule:** Deletion over addition. If removing a gem leaves a file with zero useful code, delete the whole file rather than leaving an empty class.
- **Mark deliberate corners:** If we skip cleaning a reference because it's behind a `rescue` or `if ENV[...]`, mark it `# ponytail: skipped cleanup, remove when confirmed unused`

---

## Strategy (3-Step per Phase)

1. **Delete dead code files** — Ruby files under `app/`, `lib/`, `config/` that `require` or reference the gem
2. **Remove gem/package lines** — Edit `Gemfile` and `package.json`
3. **Regenerate lockfiles** — `bundle lock --update` + `pnpm install` (done once at the end, Phase 8)

> [!CAUTION]
> Steps 1 and 2 must be done **before** step 3. If you remove a gem from the Gemfile while code still references it, `bundle exec` will crash.

---

## Phase 1 — Channel SDKs (Biggest Code Footprint)

### 1A. Twilio (`twilio-ruby` + `@twilio/voice-sdk`)

**Gemfile line to remove:** `108` — `gem 'twilio-ruby'`
**package.json line to remove:** `59` — `"@twilio/voice-sdk": "^2.12.4"`

**Ruby files to delete (19 files):**

| # | Path |
|---|------|
| 1 | `app/models/channel/twilio_sms.rb` |
| 2 | `app/controllers/api/v1/accounts/channels/twilio_channels_controller.rb` |
| 3 | `app/controllers/twilio/callback_controller.rb` |
| 4 | `app/controllers/twilio/delivery_status_controller.rb` |
| 5 | `app/services/twilio/webhook_setup_service.rb` |
| 6 | `app/services/twilio/send_on_twilio_service.rb` |
| 7 | `app/services/twilio/template_sync_service.rb` |
| 8 | `app/services/twilio/csat_template_service.rb` |
| 9 | `app/services/twilio/csat_template_api_client.rb` |
| 10 | `app/services/twilio/incoming_message_service.rb` |
| 11 | `app/services/twilio/media_download_service.rb` |
| 12 | `app/services/twilio/oneoff_sms_campaign_service.rb` |
| 13 | `app/services/twilio/delivery_status_service.rb` |
| 14 | `app/services/twilio/template_processor_service.rb` |
| 15 | `app/services/twilio/whatsapp_identifier_helper.rb` |
| 16 | `app/services/twilio/referral_params_helper.rb` |
| 17 | `app/jobs/channels/twilio/templates_sync_job.rb` |
| 18 | `app/jobs/webhooks/twilio_delivery_status_job.rb` |
| 19 | `app/jobs/webhooks/twilio_events_job.rb` |

**Ruby files to edit (remove Twilio references only):**

| # | File | What to change |
|---|------|----------------|
| 1 | `app/jobs/send_reply_job.rb` | Remove `'Channel::TwilioSms' => ::Twilio::SendOnTwilioService` mapping (L6) |
| 2 | `app/models/campaign.rb` | Remove `Twilio::OneoffSmsCampaignService` dispatch (L94-95) |
| 3 | `app/services/csat_survey_service.rb` | Remove Twilio CSAT dispatch (L98, L159) |
| 4 | `app/services/csat_template_management_service.rb` | Remove Twilio template management (L53, L111, L169) |
| 5 | `app/services/whatsapp/phone_number_normalization_service.rb` | Remove `:twilio` provider normalization (L3, L11, L59, L69) |
| 6 | `app/controllers/api/v1/accounts/concerns/whatsapp_health_management.rb` | Remove `Channels::Twilio::TemplatesSyncJob` enqueue (L98) |
| 7 | `app/controllers/api/v1/accounts/inbox_csat_templates_controller.rb` | Remove Twilio WhatsApp CSAT validation (L55) |
| 8 | `app/services/messages/markdown_renderer_service.rb` | Remove Twilio channel check (L31) |
| 9 | `config/routes.rb` | Remove `resource :twilio_channel` (L106) and `namespace :twilio` (L478) |

**JavaScript/Vue files to delete or clean (77 references):**

| # | Path | Action |
|---|------|--------|
| 1 | `app/javascript/dashboard/api/channel/voice/twilioVoiceClient.js` | **DELETE** |
| 2 | `app/javascript/dashboard/api/channel/twilioChannel.js` | **DELETE** |
| 3 | `app/javascript/dashboard/api/specs/channel/twilioChannel.spec.js` | **DELETE** |
| 4 | `app/javascript/dashboard/components-next/template-preview/templates/twilio-templates.js` | **DELETE** |
| 5 | `app/javascript/dashboard/routes/dashboard/settings/inbox/channels/Twilio.vue` | **DELETE** |
| 6-77 | ~72 other files with Twilio constants/references | **EDIT** — remove Twilio branches, imports, constants |

> [!IMPORTANT]
> Twilio is the **largest single dependency** across both Ruby and JS. Expect this phase to touch the most files.

#### 1A Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior: pre-check** | `find_dead_code` + `get_dependents(name="Channel::TwilioSms")` | Confirm Twilio symbols have no live callers outside Twilio-specific code |
| **Token Savior: post-check** | `detect_breaking_changes(since_ref="<pre-1A-commit>")` | No unintended API removal |
| **Token Savior: test discovery** | `find_impacted_test_files(symbol_names=["TwilioSms","SendOnTwilioService"])` | Find all specs referencing Twilio |
| **Graph: blast radius** | `get_impact_radius_tool(changed_files=[...deleted files...])` | Verify no non-Twilio code is broken |
| **Ruby specs** | `bundle exec rspec spec/models/channel/twilio_sms_spec.rb` → should **not exist** after deletion | Confirm spec files also deleted |
| **JS tests** | `pnpm test -- --run twilioChannel` → should produce 0 matches | No Twilio test files remain |
| **Vite build** | `npx vite build` (or in Docker) | Frontend compiles without Twilio imports |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | App boots without Twilio references |
| **Route check** | `bundle exec rails routes | grep -i twilio` → should return nothing | No Twilio routes registered |

---

### 1B. Facebook (`facebook-messenger` + `koala`)

**Gemfile lines to remove:** `106` (`facebook-messenger`), `113` (`koala`)

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `app/models/channel/facebook_page.rb` |
| 2 | `app/services/facebook/send_on_facebook_service.rb` |
| 3 | `app/builders/messages/facebook/message_builder.rb` |
| 4 | `config/initializers/facebook_messenger.rb` |

**Ruby files to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `config/routes.rb` | Remove `mount Facebook::Messenger::Server, at: 'bot'` (L453) |
| 2 | `app/controllers/api/v1/accounts/callbacks_controller.rb` | Remove `Koala::Facebook::*` references (L47, L96-L101) |

#### 1B Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior: pre-check** | `get_dependents(name="Channel::FacebookPage")` | Map all Facebook callers |
| **Token Savior: post-check** | `detect_breaking_changes(since_ref="<pre-1B-commit>")` | No unintended removal |
| **Graph: flows** | `get_affected_flows_tool` after changes | No user-facing flows broken |
| **Ruby specs** | `bundle exec rspec spec/models/channel/facebook_page_spec.rb` → should not exist | Spec deleted |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | No `Facebook::Messenger` reference crashes boot |
| **Route check** | `bundle exec rails routes | grep -i facebook` → empty | No Facebook routes |

---

### 1C. Instagram (`koala` shared — covered in 1B)

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `app/services/instagram/messenger/send_on_instagram_service.rb` |
| 2 | `app/builders/messages/instagram/messenger/message_builder.rb` |
| 3 | `app/services/instagram/messenger/message_text.rb` |

#### 1C Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior: search** | `search_codebase(query="instagram")` | Find any remaining Instagram refs |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | Clean boot |

---

### 1D. LINE (`line-bot-api`)

**Gemfile line to remove:** `107` — `gem 'line-bot-api'`

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `app/models/channel/line.rb` |
| 2 | `app/services/line/incoming_message_service.rb` |

#### 1D Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `get_dependents(name="Channel::Line")` | No live callers |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | No `Line::Bot` crash |

---

### 1E. Twitter (`twitty`)

**Gemfile lines to remove:** `110-111` — commented `twitty` git source + `gem 'twitty'`

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `app/models/channel/twitter_profile.rb` |
| 2 | `app/services/twitter/send_on_twitter_service.rb` |
| 3 | `app/controllers/concerns/twitter_concern.rb` |

**Ruby files to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `app/controllers/api/v1/webhooks_controller.rb` | Remove Twitty facade (L20) |

#### 1E Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="Twitty")` | Zero matches after cleanup |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | No `Twitty::Facade` crash |

---

### 1F. Slack (`slack-ruby-client`)

**Gemfile line to remove:** `115` — `gem 'slack-ruby-client', '~> 2.7.0'`

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `lib/integrations/slack/hook_builder.rb` |
| 2 | `lib/integrations/slack/channel_builder.rb` |
| 3 | `lib/integrations/slack/incoming_message_builder.rb` |
| 4 | `lib/integrations/slack/send_on_slack_service.rb` |
| 5 | `lib/integrations/slack/update_slack_message_service.rb` |
| 6 | `app/jobs/slack_unfurl_job.rb` |
| 7 | `config/initializers/monkey_patches/chat.rb` |

#### 1F Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="Slack::Web::Client")` | Zero matches |
| **Token Savior** | `find_dead_code` | No new orphaned symbols |
| **Graph: detect** | `detect_changes_tool(base="<pre-1F-commit>")` | Risk score acceptable |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | No Slack crash |

---

## Phase 2 — AI / ML Gems

### 2A. Dialogflow (`google-cloud-dialogflow-v2` + `grpc`)

**Gemfile lines to remove:** `117` (`google-cloud-dialogflow-v2`), `118` (`grpc`)

> [!TIP]
> Removing `grpc` saves **6-8 minutes** of build time. It compiles native C extensions from source on Alpine Linux — the single slowest gem install step.

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `lib/integrations/dialogflow/processor_service.rb` |

**Ruby files to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `app/jobs/hook_job.rb` | Remove `'dialogflow'` mapping (L8, L47, L50) |
| 2 | `app/listeners/hook_listener.rb` | Remove dialogflow subscription (L41, L63) |
| 3 | `app/models/integrations/hook.rb` | Remove `dialogflow?` method (L63-64) and routing (L85, L117) |
| 4 | `app/models/concerns/inbox_bot_status.rb` | Remove `dialogflow_active?` check (L9, L14-15) |
| 5 | `app/models/concerns/reauthorizable.rb` | Remove Dialogflow disconnect notification (L53-54) |
| 6 | `app/mailers/administrator_notifications/integrations_notification_mailer.rb` | Remove `dialogflow_disconnect` (L8-9) |
| 7 | `config/integration/apps.yml` | Remove `dialogflow` entry (L92-96) |

#### 2A Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Sequential Thinking** | Plan deletion order — `hook_job.rb` and `hook_listener.rb` must be edited BEFORE `processor_service.rb` is deleted | Correct ordering |
| **Token Savior** | `get_change_impact(name="Integrations::Dialogflow::ProcessorService")` | Full blast radius |
| **Token Savior** | `detect_breaking_changes(since_ref="<pre-2A-commit>")` | No breakage |
| **Graph** | `get_affected_flows_tool` | No user flows impacted |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | No gRPC/Dialogflow crash |

---

### 2B. Google Translate (`google-cloud-translate-v3`)

**Gemfile lines to remove:** `120-122` (comment + gem)

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `lib/integrations/google_translate/detect_language_service.rb` |
| 2 | `lib/integrations/google_translate/processor_service.rb` |

#### 2B Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `get_dependents(name="GoogleTranslate")` | No live callers |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | Clean boot |

---

### 2C. OpenAI / Captain AI (`ruby-openai` + `pgvector` + `neighbor` + `ai-agents` + `ruby_llm` + `ruby_llm-schema`)

**Gemfile lines to remove:** `194-205` (neighbor, pgvector, reverse_markdown, ruby-openai, ai-agents, ruby_llm, ruby_llm-schema)

> [!WARNING]
> Also consider removing lines `207` (`cld3`), `209-211` (opentelemetry-sdk and related) if these are only used by Captain AI. Verify with `search_codebase` before deleting.

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `lib/integrations/openai/key_validator.rb` |
| 2 | `app/jobs/migration/validate_openai_hooks_job.rb` |
| 3 | `config/initializers/ai_agents.rb` |
| 4 | `config/llm.yml` |
| 5 | `lib/integrations/llm_base_service.rb` |
| 6 | `lib/integrations/llm_instrumentation_helpers.rb` |
| 7 | `lib/integrations/llm_instrumentation_completion_helpers.rb` |
| 8 | `lib/llm/feature_router.rb` |
| 9 | `lib/llm_constants.rb` |

**Ruby files to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `app/models/integrations/hook.rb` | Remove `openai?` method (L67-68), routing (L84, L120) |
| 2 | `app/mailers/administrator_notifications/integrations_notification_mailer.rb` | Remove OpenAI disconnect mailer (L14-15) |
| 3 | `config/integration/apps.yml` | Remove OpenAI integration entry (L26-30) |
| 4 | `config/installation_config.yml` | Remove `CAPTAIN_OPEN_AI_*` entries (L192-205) |

#### 2C Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Sequential Thinking** | Plan order: edit `hook.rb` → delete LLM services → delete initializer → remove gems | Correct sequence |
| **Token Savior** | `search_codebase(query="ruby-openai")` + `search_codebase(query="pgvector")` | Zero matches after cleanup |
| **Token Savior** | `find_dead_code(max_results=50)` | No orphaned Captain AI symbols left behind |
| **Graph** | `detect_changes_tool(base="<pre-2C-commit>")` | Risk assessment |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | No AI/LLM crash |

---

## Phase 3 — Auth / OAuth

### 3A. OmniAuth stack (`omniauth-saml`, `omniauth-google-oauth2`, `omniauth-oauth2`)

**Gemfile lines to remove:** `182`, `187-190` (omniauth-oauth2, omniauth, omniauth-saml, omniauth-google-oauth2, omniauth-rails_csrf_protection)

> [!WARNING]
> `omniauth-oauth2` is used by `lib/microsoft_graph_auth.rb` for email channel OAuth. **Keep it** if you still use Microsoft email channel sync. Otherwise delete.

**Ruby files to delete (if removing all OAuth):**

| # | Path |
|---|------|
| 1 | `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` |
| 2 | `config/initializers/omniauth.rb` |
| 3 | `lib/microsoft_graph_auth.rb` (only if Microsoft email not needed) |

**Ruby files to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `app/models/user.rb` | Remove `:omniauthable, omniauth_providers: [:google_oauth2, :saml]` (L68) |
| 2 | `app/models/installation_config.rb` | Remove SAML validation guard (L39, L68-72) |
| 3 | `config/routes.rb` | Remove `post 'auth/saml_login'` (L290) |
| 4 | `config/features.yml` | Remove `saml` feature flag (L210-211) |
| 5 | `config/installation_config.yml` | Remove `ENABLE_SAML_SSO_LOGIN` (L539-546) |

#### 3A Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Sequential Thinking** | Decide: keep `omniauth-oauth2` for Microsoft email or delete everything? Document decision. | Design decision |
| **Token Savior** | `get_change_impact(name="OmniAuth")` | Full blast radius |
| **Token Savior** | `get_dependents(name="microsoft_graph_auth")` | Check if Microsoft email is used |
| **Token Savior** | `detect_breaking_changes(since_ref="<pre-3A-commit>")` | No login breakage |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | Devise boots without OmniAuth providers |
| **Login test** | Manual: visit `/auth/sign_in` — should show email-only login | No OAuth buttons |
| **Client login** | Manual: visit `/client/login` — should work as before | Client flow unaffected |

---

## Phase 4 — Payments

### 4A. Stripe (`stripe`)

**Gemfile line to remove:** `172` — `gem 'stripe', '~> 18.0'`

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `config/initializers/stripe.rb` |
| 2 | `app/helpers/billing_helper.rb` |

**Config to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `config/installation_config.yml` | Remove `CHATWOOT_CLOUD_PLANS` entry (L273) |

#### 4A Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="Stripe")` | Zero matches after cleanup |
| **Token Savior** | `get_dependents(name="BillingHelper")` | Confirm no callers |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | No Stripe crash |

---

## Phase 5 — APM / Monitoring

### 5A. All APM gems (datadog, elastic-apm, newrelic_rpm, newrelic-sidekiq-metrics, scout_apm, speedshop-cloudwatch)

**Gemfile lines to remove:** `127-131`, `143`

**Ruby files to delete:**

| # | Path |
|---|------|
| 1 | `config/initializers/datadog.rb` |
| 2 | `config/elastic_apm.yml` |
| 3 | `config/newrelic.yml` |
| 4 | `config/scout_apm.yml` |

**Ruby files to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `config/application.rb` | Remove conditional requires for datadog (L15), elastic-apm (L16), scout_apm (L17), newrelic-sidekiq-metrics (L20), newrelic_rpm (L21) |
| 2 | `config/initializers/sidekiq.rb` | Remove speedshop-cloudwatch conditional require (L37-40) |
| 3 | `app/services/conversations/unread_counts/filtered_count_instrumentation.rb` | Remove `NewRelic::Agent` metrics check (L183-186) |

> [!NOTE]
> **Keep** `sentry-rails`, `sentry-ruby`, `sentry-sidekiq` (lines 132-134) — Sentry is the primary error tracker for MMOChat.

#### 5A Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="datadog")` + `search_codebase(query="newrelic")` + `search_codebase(query="scout_apm")` | Zero matches |
| **Token Savior** | `detect_breaking_changes(since_ref="<pre-5A-commit>")` | No API breakage |
| **Ponytail check** | Are there any `ENV.fetch('DD_TRACE_AGENT_URL')` references in `.env.example` or docs? Clean those too. | No stale config |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | Boots without APM |

---

## Phase 6 — Cloud Storage

### 6A. Azure Blob + Google Cloud Storage (`azure-blob`, `google-cloud-storage`)

**Gemfile lines to remove:** `57` (`azure-blob`), `58` (`google-cloud-storage`)

> [!NOTE]
> **Keep** `aws-sdk-s3` (line 56) — this is the primary storage backend for MMOChat.

**Config to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `config/storage.yml` | Remove `microsoft:` block (L24-30) and `google:` block (L18-22) |

#### 6A Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="azure-blob")` + `search_codebase(query="google-cloud-storage")` | Zero matches |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | Active Storage boots with S3 only |
| **File upload** | Manual: upload an attachment in a conversation | S3 storage still works |

---

### 6B. ActionMailbox SES (`aws-actionmailbox-ses`)

**Gemfile line to remove:** `62` — `gem 'aws-actionmailbox-ses'`

**Config to edit:**

| # | File | What to change |
|---|------|----------------|
| 1 | `config/initializers/mailer.rb` | Remove SES ActionMailbox config (L49-53) |

#### 6B Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="actionmailbox_ses")` | Zero matches |
| **Rails boot** | `bundle exec rails runner "puts 'OK'"` | Mailer boots clean |

---

## Phase 7 — NPM Packages

### 7A. hCaptcha (`@hcaptcha/vue3-hcaptcha`)

**package.json line to remove:** `45` — `"@hcaptcha/vue3-hcaptcha": "^1.3.0"`

**JS/Vue files to edit:**

| # | Path | What to change |
|---|------|----------------|
| 1 | `app/javascript/v3/views/auth/signup/components/Signup/Form.vue` | Remove `import VueHcaptcha` (L9) and template usage |
| 2 | `app/javascript/v3/views/auth/verify-email/Index.vue` | Remove `import VueHcaptcha` (L7) and template usage |
| 3 | `app/javascript/shared/store/globalConfig.js` | Remove `HCAPTCHA_SITE_KEY` (L16) |
| 4 | `app/javascript/v3/api/auth.js` | Remove `h_captcha_client_response` param (L69) |

#### 7A Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="hcaptcha")` | Zero matches |
| **JS tests** | `pnpm test -- --run Form.spec` | Signup form tests pass |
| **Vite build** | `npx vite build` | No unresolved imports |
| **Manual** | Visit `/auth/signup` — no hCaptcha widget | Clean signup |

---

### 7B. Amplitude (`@amplitude/analytics-browser`)

**package.json line to remove:** `37` — `"@amplitude/analytics-browser": "^2.11.10"`

**JS files to delete:**

| # | Path |
|---|------|
| 1 | `app/javascript/dashboard/helper/AnalyticsHelper/index.js` |
| 2 | `app/javascript/dashboard/helper/AnalyticsHelper/specs/helper.spec.js` |

#### 7B Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="amplitude")` + `search_codebase(query="AnalyticsHelper")` | Zero matches |
| **Token Savior** | `get_dependents(name="AnalyticsHelper")` | Find all importers and clean them |
| **Vite build** | `npx vite build` | No unresolved AnalyticsHelper imports |

---

### 7C. Company Email Validator (`company-email-validator`)

**package.json line to remove:** `70` — `"company-email-validator": "^1.1.0"`

**JS files to edit:**

| # | Path | What to change |
|---|------|----------------|
| 1 | `app/javascript/v3/views/auth/signup/components/Signup/Form.vue` | Remove `import * as CompanyEmailValidator` (L15) and `isCompanyEmail` validation (L39) |

#### 7C Test Plan

| Test | Command | What it verifies |
|------|---------|-----------------|
| **Token Savior** | `search_codebase(query="company-email-validator")` + `search_codebase(query="CompanyEmailValidator")` | Zero matches |
| **JS tests** | `pnpm test -- --run Form.spec` | Signup form tests pass without email validation |

---

## Phase 8 — Final: Regenerate Lockfiles & Full Verification

After all code deletions and gem/package removals are complete:

```bash
# Ruby — regenerate Gemfile.lock (must run in Linux/Docker with correct Ruby version)
bundle lock --update

# Node — regenerate pnpm-lock.yaml
pnpm install
```

Then rebuild Docker image to verify everything compiles:

```bash
docker build -t ghcr.io/n8nmonk-wq/chatwoot_size_optimized:latest -f docker/Dockerfile .
```

#### Phase 8 — Full Integration Test Plan

| # | Test | Command | What it verifies |
|---|------|---------|-----------------|
| 1 | **Token Savior: dead code audit** | `find_dead_code(max_results=100)` | No orphaned symbols from any removed dependency |
| 2 | **Token Savior: breaking changes** | `detect_breaking_changes(since_ref="<commit-before-phase-1>")` | Complete API diff — only intentional removals |
| 3 | **Graph: full rebuild** | `build_or_update_graph_tool(full_rebuild=True)` | Fresh graph of clean codebase |
| 4 | **Graph: architecture** | `get_architecture_overview_tool` | Verify codebase structure is clean |
| 5 | **Graph: detect all changes** | `detect_changes_tool(base="<commit-before-phase-1>")` | Full risk-scored review of all changes |
| 6 | **Rails boot** | `bundle exec rails runner "puts 'OK'"` | App boots clean |
| 7 | **Vite build** | `SECRET_KEY_BASE=test rake assets:precompile` | Frontend compiles |
| 8 | **Docker build** | `docker build -t mmochat:test -f docker/Dockerfile .` | Full image builds successfully |
| 9 | **JS test suite** | `pnpm test -- --run` | All remaining JS tests pass |
| 10 | **Ruby specs (smoke)** | `bundle exec rspec spec/models/user_spec.rb spec/models/conversation_spec.rb spec/models/message_spec.rb` | Core model specs pass |
| 11 | **Manual: admin login** | Visit `/auth/sign_in` → email login | Admin login works |
| 12 | **Manual: client login** | Visit `/client/login` → username/password | Client login works |
| 13 | **Manual: WhatsApp inbox** | Settings → Inboxes → Add WhatsApp Cloud API | Only WhatsApp channel available |
| 14 | **Manual: send message** | Send a test message in conversation | Core messaging works |
| 15 | **Manual: file upload** | Upload an image in conversation | S3 storage works |
| 16 | **Ponytail: final audit** | Review all changes — any replacement abstractions added? Any empty files left? | Shortest possible diff |

---

## Execution Order (Recommended)

| Order | Phase | Risk | Est. Files | Tooling Sequence |
|-------|-------|------|-----------|------------------|
| 1 | Phase 5 — APM | ⬜ Low | ~8 | checkpoint → sequential-thinking → delete → detect_breaking_changes |
| 2 | Phase 4 — Stripe | ⬜ Low | ~3 | checkpoint → search_codebase → delete → rails boot |
| 3 | Phase 6 — Cloud Storage | ⬜ Low | ~3 | checkpoint → search_codebase → edit storage.yml → rails boot |
| 4 | Phase 3 — OAuth/SAML | 🟨 Medium | ~8 | sequential-thinking (decision: keep omniauth-oauth2?) → checkpoint → get_change_impact → delete → login test |
| 5 | Phase 2 — AI/ML | 🟨 Medium | ~15 | checkpoint → find_dead_code → sequential-thinking (order LLM file deletions) → delete → detect_breaking_changes |
| 6 | Phase 7 — NPM Packages | 🟨 Medium | ~6 | checkpoint → search_codebase → delete → vite build |
| 7 | Phase 1 — Channel SDKs | 🟥 High | ~100+ | sequential-thinking (plan 6 sub-phases) → checkpoint → per-sub-phase: get_dependents → delete → detect_breaking_changes → rails boot |
| 8 | Phase 8 — Lockfiles | ⬜ Low | 2 | bundle lock → pnpm install → full test suite → graph rebuild |

> [!TIP]
> Start with low-risk phases (APM, Stripe, Storage) — they're self-contained and unlikely to break anything. Save Twilio for last since it touches 100+ files across both Ruby and JS.

---

## Per-Phase Tooling Checklist

Before EACH phase, run this exact sequence:

```
□ Sequential Thinking: Plan deletion order and identify risks
□ Token Savior: checkpoint(op="create", file_paths=[...files to edit...])
□ Token Savior: find_dead_code — baseline before changes
□ Token Savior: get_dependents — for each major symbol being removed
□ Ponytail: Shortest diff — delete whole files where possible, don't refactor
```

After EACH phase, run this:

```
□ Token Savior: detect_breaking_changes(since_ref="<pre-phase-commit>")
□ Token Savior: find_dead_code — check for new orphans
□ Token Savior: find_impacted_test_files — run affected specs
□ Code Review Graph: get_impact_radius_tool — verify blast radius
□ Code Review Graph: detect_changes_tool — risk-scored review
□ Rails boot test: bundle exec rails runner "puts 'OK'"
□ Vite build test (if JS changed): npx vite build
□ Git commit with conventional message: chore(deps): remove <gem-name>
```

---

## Summary

| Category | Gems/Packages | Gemfile Lines | package.json Lines |
|----------|--------------|---------------|-------------------|
| Channel SDKs | 6 gems + 1 npm | 106-118 | 59 |
| AI/ML | 6+ gems | 117-118, 194-205 | — |
| Auth/OAuth | 5 gems | 182, 187-190 | — |
| Payments | 1 gem | 172 | — |
| APM/Monitoring | 6 gems | 127-131, 143 | — |
| Cloud Storage | 3 gems | 57-58, 62 | — |
| NPM Packages | 3 npm | — | 37, 45, 70 |
| **TOTAL** | **27+ gems + 4 npm** | | |

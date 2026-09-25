# MMOChat — Simplification & Client View Implementation Plan

> **Approach A**: New `client` role with a simplified frontend layout, scoped to assigned WhatsApp inboxes.  
> **Brand**: MMOChat (Monk Media One)  
> **Status**: ✅ **ALL PHASES COMPLETED & DEPLOYED TO MAIN**

### 🏁 Implementation Status
- [x] **Phase 0 — Rebrand to MMOChat**: App name, titles, Monk Media One logo, favicon, and PWA icons integrated.
- [x] **Phase 1 — Remove Enterprise Directory**: 1,400+ unused enterprise files purged.
- [x] **Phase 2 — Remove Bloat**: Captain AI, Portals/Help Center, Macros, third-party integrations, and Teams removed.
- [x] **Phase 3 — WhatsApp-Only Channel UI**: Channel list limited strictly to WhatsApp Cloud API.
- [x] **Phase 4 — Client Role & Backend Auth**: `AccountUser` enum `client: 2`, `username` migration, Devise username authentication, client password reset restrictions.
- [x] **Phase 5 — Admin Management for Clients**: Settings → Clients UI, `ClientsController`, Admin-only password updates.
- [x] **Phase 6 — Client Frontend View**: `/client/login`, simplified client topbar layout in `Dashboard.vue`, route guards, conversation reply-only access.
- [x] **Phase 7 — Cleanup & Verification**: Dead files removed, `docker-compose.traefik.yaml` configured, `deploy/update-vps.sh` migration support added.

---

## Overview

Transform this Chatwoot fork into **MMOChat** — a **lean WhatsApp conversation tool** with three user types:

| Role | Logs in with | Can do | Cannot do |
|------|-------------|--------|-----------|
| **Administrator** | Email + password | Manage agents, clients, inboxes, conversations, contacts, settings | — |
| **Agent** | Email + password | Handle all conversations, reply, assign, resolve | Change settings, manage users |
| **Client** *(new)* | **Username + password** | View & reply to conversations in assigned WhatsApp inboxes | Initiate conversations, access settings/contacts/reports/anything else |

---

## Phase 0 — Rebrand to MMOChat

Replace all Chatwoot branding with MMOChat + Monk Media One logo.

### 0a. Logo & Favicon

- **Source logo**: `https://monkmediaone.tech/wp-content/uploads/2026/03/Untitled-design-1.png`
- Replace sidebar logo in `app/javascript/dashboard/assets/images/` and logo components
- Replace favicon at `public/favicon.ico`
- Replace PWA icons in `public/pwa/` (generate multiple sizes from source logo)
- Same logo for both sidebar and favicon

### 0b. App Name

| Location | Change |
|----------|--------|
| `config/app.yml` | `name: MMOChat` |
| `public/manifest.json` | `"name": "MMOChat"`, `"short_name": "MMOChat"` |
| `app/views/layouts/` | `<title>` tags → "MMOChat" |
| i18n files (`en.json`, `en.yml`) | Replace "Chatwoot" references with "MMOChat" |
| Login/signup page | Title + branding → "MMOChat" + logo |
| Email/mailer templates | Branding → "MMOChat" + logo |
| `README.md` | Update project name and description |

### 0c. Domain

- Production instance: `chatwoot.srv1275499.hstgr.cloud` (update if custom domain is added later)

---

## Phase 1 — Remove Enterprise Directory

Delete the entire `enterprise/` directory. This removes:

- Custom Roles
- Audit Logs (enterprise portion)
- Enterprise billing, plan limits
- Enterprise-only controllers, models, policies, views
- `prepend_mod_with` / `include_mod_with` overrides will gracefully no-op since the OSS code already handles missing enterprise modules

### Steps

1. Delete `enterprise/` directory entirely
2. Delete `spec/enterprise/` test directory
3. Search for and verify all `prepend_mod_with` / `include_mod_with` calls degrade gracefully (they should — this is how OSS mode already works)
4. Remove any ENV vars or config referencing enterprise license keys

---

## Phase 2 — Remove Unwanted Features

### 2a. Remove Captain (AI Assistant)

**Backend:**
- Delete `app/models/captain/` and all Captain-related models
- Delete `app/controllers/api/v1/accounts/captain/` controllers
- Delete `app/services/captain/` services
- Delete `app/jobs/captain/` jobs
- Remove Captain routes from `config/routes.rb`
- Remove Captain-related migrations (or leave them — they're harmless)
- Remove Captain ENV vars from `.env` samples

**Frontend:**
- Remove Captain components from `app/javascript/dashboard/components/`
- Remove Captain route entries
- Remove Captain store modules
- Remove Captain API service files

### 2b. Remove Help Center / Knowledge Base

**Backend:**
- Delete `app/controllers/api/v1/portals/` and related portal controllers
- Delete `app/models/portal.rb`, `article.rb`, `category.rb` and related models
- Delete portal-related services and jobs
- Remove portal routes from `config/routes.rb`
- Remove the portal frontend entry point (`app/javascript/portal/`)

**Frontend:**
- Remove Help Center sidebar nav item
- Remove Help Center route entries and components
- Remove Help Center store modules

### 2c. Remove Macros

**Backend:**
- Delete `app/models/macro.rb` and related models
- Delete `app/controllers/api/v1/accounts/macros_controller.rb`
- Delete macro execution services/jobs
- Remove macro routes

**Frontend:**
- Remove Macros sidebar nav item and components
- Remove Macros store module

### 2d. Remove Integrations

**Backend:**
- Delete `app/controllers/api/v1/accounts/integrations/` controllers
- Delete integration-specific models (Dialogflow, OpenAI hooks, Slack, etc.)
- Delete `app/services/integrations/` services
- Remove integration routes
- Keep the core `Channel::Api` and `Channel::Whatsapp` — only remove third-party integrations

**Frontend:**
- Remove Integrations sidebar nav item
- Remove integration settings pages and components
- Remove integration store modules

### 2e. Remove Teams

**Backend:**
- Delete `app/models/team.rb`, `team_member.rb`
- Delete `app/controllers/api/v1/accounts/teams_controller.rb`
- Delete team-related services
- Remove team routes
- Remove team assignment logic from conversation assignment (simplify to agent-only assignment)

**Frontend:**
- Remove Teams sidebar nav item and components
- Remove team filters from conversation sidebar
- Remove Teams store module

---

## Phase 3 — WhatsApp-Only Channel Restriction

### 3a. Backend

- In inbox creation, restrict allowed channel types to `Channel::Whatsapp` only
- Remove or disable channel type classes: `Channel::WebWidget`, `Channel::FacebookPage`, `Channel::TwitterProfile`, `Channel::Telegram`, `Channel::Email`, `Channel::Sms`, `Channel::Line`, etc.
- Keep `Channel::Api` if needed for future extensibility (optional — remove if not wanted)
- Remove channel-specific webhook controllers for disabled channels
- Clean up inbox creation API to only accept WhatsApp params

### 3b. Frontend

- In "Add Inbox" flow, show only WhatsApp as an option (or skip the channel picker entirely)
- Remove channel icons/logos for disabled channels
- Remove channel-specific settings components

---

## Phase 4 — Add Client Role

### 4a. Database Migration

```ruby
# db/migrate/XXXXXX_add_client_role_to_account_users.rb
class AddClientRoleToAccountUsers < ActiveRecord::Migration[7.0]
  def change
    # The enum already supports integer mapping.
    # Just adding client: 2 to the enum in the model is sufficient.
    # No schema change needed since `role` is already an integer column.
  end
end
```

Update the model enum:

```ruby
# app/models/account_user.rb
enum role: { agent: 0, administrator: 1, client: 2 }
```

### 4b. Backend Policies (Pundit)

Update every policy to deny `client` role access except:

- `ConversationPolicy` — allow `index`, `show`, `update` (for replying / resolving)
- `MessagePolicy` — allow `index`, `create` (for viewing and sending replies)
- `InboxPolicy` — allow `index` (read-only, to load inbox metadata)
- `AccountPolicy` — allow `show` (read-only, for basic account info needed by frontend)

All other policies (`ContactPolicy`, `ReportPolicy`, `CampaignPolicy`, `SettingsPolicy`, etc.) should return `false` for client role.

### 4c. Conversation Scoping for Clients

In the conversations controller / policy, scope queries so clients only see conversations from their assigned inboxes:

```ruby
# Pseudocode for conversation scoping
if current_user.client?
  inbox_ids = current_user.inbox_member_inbox_ids(account)
  conversations = account.conversations.where(inbox_id: inbox_ids)
end
```

### 4d. AccountUser Permissions Method

Update the `permissions` method:

```ruby
def permissions
  if administrator?
    ['administrator']
  elsif client?
    ['client']
  else
    ['agent']
  end
end
```

### 4e. Username-Based Client Login

Clients log in with **username + password** (not email). Admins/agents continue using email + password.

**Database Migration:**

```ruby
# db/migrate/XXXXXX_add_username_to_users.rb
class AddUsernameToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :username, :string
    add_index :users, :username, unique: true
  end
end
```

**Auth Changes:**
- Modify the Devise `SessionsController` (or add a custom `ClientSessionsController`) to accept `username` instead of `email` for client login
- Add a `find_for_client_authentication` class method on `User` that looks up by username
- The login page detects context: if on `/client/login` → show username field; if on `/app/login` → show email field (existing flow)
- Clients get a **separate login route**: `/client/login` (clean, no confusion with admin/agent login)
- Admins set the username when creating a client (auto-generated or manual)

**Validation:**
- `username` must be unique, alphanumeric + underscores, 3–30 chars
- Only required for client role users; admins/agents can have `username: nil`


---

## Phase 5 — Admin UI for Managing Clients

### 5a. Settings → Clients Page

Create a new settings page (similar to the existing Agents page) at **Settings → Clients**:

- **List view**: Shows all users with `client` role in the account
- **Add Client**: Form with name, **username**, password fields → creates User + AccountUser (role: client)
- **Edit Client**: Change name, reset password, reassign inboxes
- **Delete Client**: Remove AccountUser record
- **Inbox Assignment**: Multi-select of available WhatsApp inboxes

### 5b. Backend

- New controller: `Api::V1::Accounts::ClientsController` (or extend AgentsController with role filter)
- CRUD endpoints: `index`, `create`, `update`, `destroy`
- Inbox assignment endpoint (reuse `InboxMember` logic)

### 5c. Frontend

- New route: `/app/accounts/:accountId/settings/clients`
- New components: `ClientsIndex.vue`, `CreateClient.vue`, `EditClient.vue`
- New store module: `clients`
- Add "Clients" item to Settings sidebar navigation

---

## Phase 6 — Client Frontend Layout

### 6a. Simplified Layout

When a user with `client` role logs in, render a **stripped-down layout** instead of the full dashboard:

```
┌──────────────────────────────────────────────────┐
│  Header: Logo + Account Name + Logout            │
├──────────────────┬───────────────────────────────┤
│                  │                               │
│  Conversation    │   Conversation Detail         │
│  List            │                               │
│  (filtered to    │   - Message thread            │
│   assigned       │   - Reply box                 │
│   inboxes)       │   - Basic actions             │
│                  │     (resolve/reopen)           │
│                  │                               │
└──────────────────┴───────────────────────────────┘
```

**No sidebar navigation** — no Settings, Contacts, Reports, etc.

### 6b. Implementation

- New layout component: `ClientLayout.vue`
- Reuses existing `ConversationList` and `ConversationView` components
- Route guard: if `currentUser.role === 'client'`, redirect to client layout and block all non-conversation routes
- The conversation list auto-filters to only show conversations from the client's assigned inboxes

### 6c. What Clients Can Do

- ✅ See conversation list (from assigned inboxes only)
- ✅ Open a conversation and read the full message thread
- ✅ Send text replies
- ✅ Send attachments (images, files)
- ✅ Resolve / reopen a conversation
- ✅ See basic contact info (name, phone number) in the conversation header
- ❌ Initiate new conversations (no template sending)
- ❌ Access contacts, reports, settings, or any other section
- ❌ Assign conversations to other agents/clients
- ❌ Create labels, teams, canned responses, etc.

---

## Phase 7 — Cleanup & Polish

### 7a. Delete Scratch/Hack Scripts (root-level junk)

These are one-off scripts that patched compiled assets or ran ad-hoc tasks — not needed in source:

| File | What it is |
|------|-----------|
| `check_sidebar.js` | Patched compiled dashboard JS to inspect sidebar |
| `find_calls.js` | Searched compiled JS for call-related code |
| `find_waba.sh` | Ad-hoc shell script to query WhatsApp Business API token |
| `patch_calls_and_all.js` | Patched compiled JS to modify calls UI |
| `patch_calls_label.js` | Patched compiled JS for call labels |
| `patch_captain.js` | Patched compiled JS to disable Captain |
| `patch_disabled_features.js` | Patched compiled JS for feature flags |
| `replace_calls.js` | Patched compiled JS for calls feature |
| `disable_features.rb` | Rails runner script to disable feature flags (useful reference but should live in `script/` if kept) |

**Action:** Delete all of these.

### 7b. Delete Unused CI/CD & Platform Configs

These are for services you're not using (CircleCI, CleverCloud, Heroku, Capistrano, Dependabot, etc.):

| Path | What it is |
|------|-----------|
| `.circleci/` | CircleCI CI config (not using) |
| `.dependabot/` | Dependabot auto-update config (not using) |
| `.devcontainer/` | VS Code devcontainer setup (not needed if not using codespaces) |
| `clevercloud/` | CleverCloud PaaS deployment config |
| `.slugignore` | Heroku slug ignore file |
| `Capfile` | Capistrano deployment (not using) |
| `crowdin.yml` | Crowdin translation sync config (not using) |
| `semantic.yml` | Semantic PR bot config |
| `.scss-lint.yml` | SCSS linter config (project uses Tailwind, not SCSS) |
| `histoire.config.ts` | Histoire (Storybook alternative) config — not using |
| `.all-contributorsrc` | All Contributors bot config |
| `.bundler-audit.yml` | Bundler audit config |
| `.qlty/` | Qlty code quality tool config |

**Action:** Delete all of these.

### 7c. Delete Tool-Specific Configs You Don't Need

| Path | What it is | Keep? |
|------|-----------|-------|
| `.code-review-graph/` | Code review graph DB (Antigravity tool artifact) | Delete |
| `.windsurf/` | Windsurf AI editor rules (points to AGENTS.md) | Delete |
| `.husky/` | Git hooks (pre-commit, pre-push) | Keep if you want lint-on-commit, otherwise delete |
| `.vscode/` | VS Code settings | Keep if using VS Code |
| `.editorconfig` | Editor config | Keep |

### 7d. Delete Unused Scripts

| Path | What it is |
|------|-----------|
| `script/backfill_applied_sla_completed_at.rb` | SLA backfill — removing SLA-related |
| `script/rails_upgrade/` | Rails upgrade helper scripts — one-time use, done |

### 7e. Delete Unused Deployment Configs

| Path | What it is | Keep? |
|------|-----------|-------|
| `deployment/setup_18.04.sh` | Ubuntu 18.04 bare-metal setup | Delete (EOL) |
| `deployment/setup_20.04.sh` | Ubuntu 20.04 bare-metal setup | Delete if using Docker |
| `deployment/` (all service files) | Systemd service configs | Delete if using Docker |
| `docker-compose.yaml` | Default compose (not optimized) | Delete — keep only `docker-compose.optimized.yaml` |
| `docker-compose.test.yaml` | Test compose | Delete if not testing in Docker |
| `docker-compose.traefik.yaml` | Traefik reverse proxy compose | Delete if using Nginx |
| `.env.traefik.sample` | Traefik env sample | Delete |
| `Procfile.tunnel` | Tunnel procfile | Delete |
| `Procfile.test` | Test procfile | Delete if not needed |
| `app.json` | Heroku app.json | Delete |

### 7f. Misc Cleanup

| Path | What it is |
|------|-----------|
| `config/elastic_apm.yml` | Elastic APM config — not using |
| `config/newrelic.yml` | New Relic monitoring — not using |
| `config/scout_apm.yml` | Scout APM config — not using |
| `config/rds-ca-2019-root.pem` | AWS RDS SSL cert — not using |
| `config/schedule.yml` | Whenever cron config — check if needed |
| `config/spring.rb` | Spring preloader — not needed in production |
| `lib/dyte.rb` | Dyte video call integration — removing calls |
| `lib/linear.rb` | Linear integration — removing integrations |
| `lib/microsoft_graph_auth.rb` | Microsoft Graph auth — removing email channel |
| `workbox-config.js` | Workbox service worker config — review if SW is needed |
| `vite.lib.config.ts` | Vite lib build config — not building a library |
| `vite.sdk.analyze.config.mts` | SDK analyzer — not needed |
| `vite.widget.analyze.config.mts` | Widget analyzer — not needed |
| `CLAUDE.md` | Claude AI pointer file | Delete |
| `CODE_OF_CONDUCT.md` | Upstream CoC | Delete or keep |
| `CONTRIBUTING.md` | Upstream contributing guide | Delete |
| `SECURITY.md` | Upstream security policy | Delete or update |

### 7g. Final Steps

- Remove dead routes for all removed features
- Remove unused i18n keys from `en.json` and `en.yml`
- Remove unused Vuex/Pinia store modules
- Remove sidebar nav items for removed features
- Update seed data to not create removed resources
- Update `README.md` to describe MMOChat
- Test all role paths: admin, agent, client


---

## Implementation Order

| # | Phase | Estimated Effort | Dependencies |
|---|-------|-----------------|--------------|
| 0 | Rebrand to MMOChat (logo, favicon, name) | Small | None |
| 1 | Remove `enterprise/` | Small | None |
| 2a | Remove Captain | Medium | Phase 1 |
| 2b | Remove Help Center | Medium | Phase 1 |
| 2c | Remove Macros | Small | Phase 1 |
| 2d | Remove Integrations | Medium | Phase 1 |
| 2e | Remove Teams | Medium | Phase 1 |
| 3 | WhatsApp-only channels | Medium | Phase 2 |
| 4 | Add Client role + username auth (backend) | Medium–Large | Phase 1 |
| 5 | Admin UI for Clients | Medium | Phase 4 |
| 6 | Client frontend layout + `/client/login` | Large | Phase 4, 5 |
| 7 | Cleanup & polish | Small | All above |

> **IMPORTANT:** Phase 0 (branding) can run in parallel with anything. Phases 1–3 (removal) should be done before adding new features in Phases 4–6.

---

## Files to Keep (Core)

These are the critical paths that must remain untouched:

- `app/models/conversation.rb` — core conversation model
- `app/models/message.rb` — core message model
- `app/models/inbox.rb` — inbox model
- `app/models/channel/whatsapp.rb` — WhatsApp channel
- `app/models/contact.rb` — contact model (simplified)
- `app/models/user.rb` — user model
- `app/models/account_user.rb` — role assignment (extended with client)
- `app/models/inbox_member.rb` — inbox-to-user scoping
- `app/controllers/api/v1/accounts/conversations_controller.rb`
- `app/controllers/api/v1/accounts/conversations/messages_controller.rb`
- `app/javascript/dashboard/` — main frontend (modified for client layout)

---

## Phase 8 — Testing Strategy

> Every phase MUST pass its validation gate before moving to the next phase.

### 8a. Per-Phase Validation Gates

#### After Phase 0 (Rebrand)
- [ ] App boots without errors: `bundle exec rails s` starts cleanly
- [ ] Login page shows MMOChat name + MMO logo
- [ ] Sidebar shows MMO logo (not Chatwoot logo)
- [ ] Browser tab shows MMOChat favicon + title
- [ ] `pnpm test` — frontend tests pass (no broken image/asset imports)

#### After Phase 1 (Remove Enterprise)
- [ ] App boots without errors
- [ ] `bundle exec rspec spec/models/account_user_spec.rb` — passes
- [ ] `bundle exec rspec spec/models/account_spec.rb` — passes
- [ ] `bundle exec rspec spec/controllers/api/v1/accounts/conversations_controller_spec.rb` — passes
- [ ] No `NameError` or `LoadError` from missing enterprise modules (verify `prepend_mod_with` no-ops cleanly)
- [ ] Login → dashboard loads without console errors
- [ ] Create a conversation → send a message → works

#### After Phase 2 (Remove Features)
Run after EACH sub-phase (2a–2e):

- [ ] `bundle exec rails routes` — no routes pointing to deleted controllers
- [ ] `bundle exec rspec spec/controllers/api/v1/accounts/conversations_controller_spec.rb` — passes
- [ ] `bundle exec rspec spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` — passes
- [ ] `bundle exec rspec spec/models/conversation_spec.rb` — passes
- [ ] `bundle exec rspec spec/models/message_spec.rb` — passes
- [ ] `bundle exec rspec spec/models/inbox_spec.rb` — passes
- [ ] `pnpm test` — no import errors from deleted components/stores
- [ ] Sidebar loads — no broken nav items or JS errors
- [ ] Conversation list loads
- [ ] Open a conversation → message thread renders
- [ ] Send a reply → message appears

#### After Phase 3 (WhatsApp-only)
- [ ] `bundle exec rspec spec/models/channel/whatsapp_spec.rb` — passes
- [ ] `bundle exec rspec spec/controllers/api/v1/accounts/inboxes_controller_spec.rb` — passes
- [ ] Add Inbox flow → only WhatsApp option appears
- [ ] Existing WhatsApp inbox still works — receives and sends messages
- [ ] No references to removed channel types cause runtime errors

#### After Phase 4 (Client Role + Username Auth)
- [ ] Migration runs cleanly: `bundle exec rails db:migrate`
- [ ] `bundle exec rspec spec/models/account_user_spec.rb` — passes
- [ ] New specs pass:
  - `bundle exec rspec spec/models/user_spec.rb` — username validation
  - `bundle exec rspec spec/policies/conversation_policy_spec.rb` — client role access
- [ ] **Write new specs for:**
  - `spec/models/account_user_spec.rb` — test `client` role enum, `permissions` method returns `['client']`
  - `spec/models/user_spec.rb` — test username uniqueness, format validation, only required for client role
  - `spec/policies/conversation_policy_spec.rb` — test client can `index`, `show`, `update` conversations in assigned inboxes; CANNOT access conversations in unassigned inboxes
  - `spec/policies/message_policy_spec.rb` — test client can `index`, `create` messages in allowed conversations
  - `spec/policies/contact_policy_spec.rb` — test client is DENIED all access
  - `spec/policies/report_policy_spec.rb` — test client is DENIED all access
  - `spec/policies/inbox_policy_spec.rb` — test client can only `index` (read-only)
  - `spec/controllers/api/v1/accounts/conversations_controller_spec.rb` — add client role context: scoped to assigned inboxes only
  - `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb` — add client role context: can create messages
  - `spec/requests/client_authentication_spec.rb` — test login with username+password, reject email login for client, reject username login for admin/agent
- [ ] API test: client user GET `/api/v1/accounts/:id/conversations` → returns only conversations from assigned inboxes
- [ ] API test: client user GET `/api/v1/accounts/:id/contacts` → returns 403
- [ ] API test: client user GET `/api/v1/accounts/:id/reports` → returns 403

#### After Phase 5 (Admin UI for Clients)
- [ ] `pnpm test` — new client store/component tests pass
- [ ] **Write new frontend specs for:**
  - Clients store module — CRUD actions
  - `ClientsIndex.vue` — renders client list
  - `CreateClient.vue` — form validation (username required, password required)
- [ ] **Write new backend specs for:**
  - `spec/controllers/api/v1/accounts/clients_controller_spec.rb` — CRUD endpoints, only admin can access, creates user with client role + username
- [ ] Manual: Admin → Settings → Clients → Add Client (name + username + password) → client appears in list
- [ ] Manual: Admin → Edit Client → assign 2 WhatsApp inboxes → save → verify InboxMember records created
- [ ] Manual: Admin → Delete Client → client removed

#### After Phase 6 (Client Frontend Layout)
- [ ] `pnpm test` — ClientLayout component tests pass
- [ ] **Write new frontend specs for:**
  - `ClientLayout.vue` — renders conversation list + detail, no sidebar nav
  - Route guard — client role redirected to client layout, blocked from `/settings`, `/contacts`, `/reports`
- [ ] Manual: Log in as client at `/client/login` with username + password → lands on simplified view
- [ ] Manual: Client sees only conversations from assigned inboxes (not all account conversations)
- [ ] Manual: Client opens a conversation → message thread loads → can type and send a reply
- [ ] Manual: Client sends an attachment → uploads successfully
- [ ] Manual: Client resolves a conversation → status changes
- [ ] Manual: Client reopens a resolved conversation → status changes back
- [ ] Manual: Client tries to navigate to `/app/accounts/:id/settings` → redirected back
- [ ] Manual: Client tries to navigate to `/app/accounts/:id/contacts` → redirected back
- [ ] Manual: Admin/agent login at `/app/login` still works normally (no regression)

#### After Phase 7 (Cleanup)
- [ ] `bundle exec rspec` — full backend suite passes (delete specs for removed features first)
- [ ] `pnpm test` — full frontend suite passes
- [ ] `bundle exec rails routes | wc -l` — no routes to deleted controllers
- [ ] App boots cleanly, no deprecation warnings from removed code
- [ ] No JS console errors on any page

### 8b. Core Smoke Test Checklist (Run After EVERY Phase)

This is the non-negotiable baseline — if any of these fail, the phase is not done:

```
[ ] App boots: `bundle exec rails s` + `pnpm dev` start without errors
[ ] Admin login: email + password → dashboard loads
[ ] Agent login: email + password → dashboard loads
[ ] Conversation list: loads and displays conversations
[ ] Open conversation: message thread renders correctly
[ ] Send message: text reply sends and appears in thread
[ ] WhatsApp webhook: incoming message from WhatsApp creates/updates conversation
[ ] No JS console errors on dashboard
[ ] No Ruby exceptions in server logs
```

### 8c. Existing Specs to Keep & Run

These existing spec files cover the critical paths and MUST pass throughout all phases:

**Models (core):**
- `spec/models/conversation_spec.rb`
- `spec/models/message_spec.rb`
- `spec/models/inbox_spec.rb`
- `spec/models/account_spec.rb`
- `spec/models/account_user_spec.rb`
- `spec/models/user_spec.rb`
- `spec/models/contact_spec.rb`
- `spec/models/inbox_member_spec.rb`
- `spec/models/channel/whatsapp_spec.rb`

**Controllers (core):**
- `spec/controllers/api/v1/accounts/conversations_controller_spec.rb`
- `spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb`
- `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb`
- `spec/controllers/api/v1/accounts/inbox_members_controller_spec.rb`
- `spec/controllers/api/v1/accounts/agents_controller_spec.rb`

**Policies (core):**
- `spec/policies/conversation_policy_spec.rb`
- `spec/policies/inbox_policy_spec.rb`
- `spec/policies/contact_policy_spec.rb`

**Quick command to run all core specs at once:**
```bash
bundle exec rspec \
  spec/models/conversation_spec.rb \
  spec/models/message_spec.rb \
  spec/models/inbox_spec.rb \
  spec/models/account_spec.rb \
  spec/models/account_user_spec.rb \
  spec/models/user_spec.rb \
  spec/models/contact_spec.rb \
  spec/models/inbox_member_spec.rb \
  spec/models/channel/whatsapp_spec.rb \
  spec/controllers/api/v1/accounts/conversations_controller_spec.rb \
  spec/controllers/api/v1/accounts/conversations/messages_controller_spec.rb \
  spec/controllers/api/v1/accounts/inboxes_controller_spec.rb \
  spec/controllers/api/v1/accounts/inbox_members_controller_spec.rb \
  spec/controllers/api/v1/accounts/agents_controller_spec.rb \
  spec/policies/conversation_policy_spec.rb \
  spec/policies/inbox_policy_spec.rb \
  spec/policies/contact_policy_spec.rb
```

### 8d. Specs to Delete (for removed features)

When removing a feature, also delete its specs so the test suite stays clean:

| Removed Feature | Specs to delete |
|----------------|----------------|
| Enterprise | `spec/enterprise/` (entire directory) |
| Captain | `spec/**/captain*` |
| Help Center | `spec/policies/article_policy_spec.rb`, `spec/policies/category_policy_spec.rb`, `spec/policies/portal_policy_spec.rb`, `spec/**/portal*`, `spec/**/article*` |
| Macros | `spec/**/macro*` |
| Integrations | `spec/**/integration*` (review — keep integration test dir if it has non-integration-feature tests) |
| Teams | `spec/**/team*` |
| Removed channels | `spec/models/channel/web_widget_spec.rb`, `spec/models/channel/facebook_page_spec.rb`, `spec/models/channel/telegram_spec.rb`, `spec/models/channel/email_spec.rb`, etc. |

### 8e. New Specs Summary (What to Write)

| Phase | New spec files | What they test |
|-------|---------------|---------------|
| 4 | `spec/models/account_user_spec.rb` (extend) | `client` enum value, `permissions` returns `['client']` |
| 4 | `spec/models/user_spec.rb` (extend) | `username` uniqueness, format, required-for-client validation |
| 4 | `spec/policies/conversation_policy_spec.rb` (extend) | Client role: allow scoped access, deny unassigned inbox access |
| 4 | `spec/policies/message_policy_spec.rb` (new or extend) | Client role: allow `index`/`create`, deny `destroy` |
| 4 | `spec/requests/client_authentication_spec.rb` (new) | Username+password login, rejection of email login for clients |
| 5 | `spec/controllers/api/v1/accounts/clients_controller_spec.rb` (new) | CRUD, admin-only access, creates client role with username |
| 6 | Frontend component tests for `ClientLayout.vue` | Renders simplified UI, no sidebar |
| 6 | Frontend route guard tests | Client redirected away from settings/contacts/reports |


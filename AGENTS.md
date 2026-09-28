# MMOChat — Agent Rules

MMOChat: a lean Chatwoot fork by Monk Media One for managing customer conversations over the WhatsApp Cloud API on a low-RAM VPS. Read [PROJECT.md](PROJECT.md) for how it runs, the tech stack and how/where it is deployed.

## The app is LIVE in production
- Real users on the Hostinger VPS. **A push to `main` deploys** (GitHub Actions builds the image → GHCR → VPS pulls it). Never push to `main` unless the user explicitly says so.
- Database changes are additive migrations only. Never drop, rename or rewrite columns/tables holding user data.
- Never touch the server, its Docker volumes or production data.
- No secrets in code, commits, images or logs.

## On Every Session Start
- Read `plans/INDEX.md` and the plan you're working on. The plans, this file and git history are the project memory.
- The code-review-graph is pre-built; use it for navigation instead of reading full files.
- Token Savior is indexed; prefer `get_structure_summary` / `get_function_source` over reading whole files.

## On Every Commit (Automatic)
- The code-review-graph updates incrementally via post-commit hook.
- Record what changed, why, and any decisions in the plan's "Implementation notes".

## Tools — use these instead of reading whole files
- **code-review-graph** — navigation and blast radius. `query_graph_tool` (callers_of / importers_of), `get_impact_radius_tool`, `get_affected_flows_tool`. Run this before editing anything shared.
- **Token Savior** — targeted reads. `find_symbol`, `get_function_source`, `get_full_context`. Never `cat` a whole file when a symbol lookup will do.
- **sequential-thinking** — `mcp__sequential-thinking__sequentialthinking` for tricky logic, multi-step changes and hard bugs. Think it through before editing, not after.
- **ponytail** — the laziness posture (see Coding Standards).
- If a tool is missing or fails, say so explicitly. Never claim you used one when you didn't.

# Chatwoot Development Guidelines

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed` (quickly populates minimal data for standard feature verification)
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data` (bulk fixture generation for search/performance/manual load scenarios)
- **Seed Account Sample Data (richer test data)**: `Seeders::AccountSeeder` is available as an internal utility and is exposed through Super Admin `Accounts#seed`, but can be used directly in dev workflows too:
  - UI path: Super Admin → Accounts → Seed (enqueues `Internal::SeedAccountJob`).
  - CLI path: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or call `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!` directly).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Run Project**: `overmind start -f Procfile.dev`
- **Ruby Version**: Manage Ruby via `rbenv` and install the version listed in `.ruby-version` (e.g., `rbenv install $(cat .ruby-version)`)
- **rbenv setup**: Before running any `bundle` or `rspec` commands, init rbenv in your shell (`eval "$(rbenv init -)"`) so the correct Ruby/Bundler versions are used
- Always prefer `bundle exec` for Ruby CLI tasks (rspec, rake, rubocop, etc.)

## Code Style

- **Ruby**: Follow RuboCop rules (150 character max line length)
- **Vue/JS**: Use ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: Use PascalCase
- **Events**: Use camelCase
- **I18n**: No bare strings in templates; use i18n
- **Error Handling**: Use custom exceptions (`lib/custom_exceptions/`)
- **Models**: Validate presence/uniqueness, add proper indexes
- **Type Safety**: Use PropTypes in Vue, strong params in Rails
- **Naming**: Use clear, descriptive names with consistent casing
- **Vue API**: Always use Composition API with `<script setup>` at the top

## Styling

- **Tailwind Only**:  
  - Do not write custom CSS  
  - Do not use scoped CSS  
  - Do not use inline styles  
  - Always use Tailwind utility classes  
- **Colors**: Refer to `tailwind.config.js` for color definitions

## General Guidelines

- Prefer the smallest production-ready change that solves the current problem.
- Build for the expected production path first. Do not add speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit that case or production has proven it necessary.
- Enforce eligibility and exclusivity rules at the earliest shared entry point. Do not repeat backup guards across downstream jobs, callbacks, services, or writes unless a proven independent path bypasses that point.
- When an impossible or misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently skipping behavior.
- For locked/internal configs that must exist in production, prefer direct reads (`find`, `find_by!`, required hash keys) over silent fallbacks.
- Do not add validation or response checks unless the code uses the result or the check changes behavior meaningfully.
- Prefer existing repo dependencies/client libraries over hand-rolled protocol code for auth, signing, parsing, or API plumbing.
- Avoid one-use private helpers unless they hide real complexity or make the main flow meaningfully easier to read.
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- In specs, avoid custom helper methods for setup/data. Prefer `let` values and direct per-example setup; only add a helper when it removes meaningful repeated complexity.
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages

- Prefer Conventional Commits: `type(scope): subject` (scope optional)
- Example: `feat(auth): add user authentication`
- Don't reference Claude in commit messages

## PR Description Format

- Start with a short, user-facing paragraph describing the product change.
- Add a `Closes` section with relevant issue links (GitHub, Linear, etc.).
- For feature PRs, add `How to test` from a product/UX standpoint.
- For bugfix PRs, use `How to reproduce` when helpful.
- Optionally add a `What changed` section for implementation highlights.
- Do not add a `How this was tested` section listing specs/commands.

## Project-Specific

- **Translations**:
  - For product and source-string changes, only update `en.yml` and `en.json`; other languages are handled through Crowdin and the community
  - Crowdin-generated translation sync PRs may update non-English locale files; do not flag those changes solely for modifying translated locale files
  - Preserve product and brand names, OAuth scopes, API values, and other machine-readable identifiers unless an official localized form exists
  - When reviewing Crowdin syncs, verify protected terms remain unchanged. Add newly introduced product names, brand names, and machine-readable identifiers to the Crowdin glossary as non-translatable, and keep the glossary current
  - Backend i18n → `en.yml`, Frontend i18n → `en.json`
- **Frontend**:
  - Use `components-next/` for message bubbles (the rest is being deprecated)

## Ruby Best Practices

- Use compact `module/class` definitions; avoid nested styles

## Frontend Conventions

- Prefer existing design-system utilities and shared composables.
- Use typography utilities instead of manually recreating font styles.
- Use logical Tailwind utilities (`ms`, `me`, `start`, `end`) for direction-aware layouts.
- Use `rem` for arbitrary CSS dimensions; preserve native numeric values required by chart/SVG APIs.
- Extract repeated or domain-specific strings, thresholds, colors, and durations into named constants.
- Use shared request-cancellation utilities instead of local `AbortController` logic.

## Enterprise Edition Notes

- Chatwoot has an Enterprise overlay under `enterprise/` that extends/overrides OSS code.
- When you add or modify core functionality, always check for corresponding files in `enterprise/` and keep behavior compatible.
- Follow the Enterprise development practices documented here:
  - https://chatwoot.help/hc/handbook/articles/developing-enterprise-edition-features-38

Practical checklist for any change impacting core logic or public APIs
- Search for related files in both trees before editing (e.g., `rg -n "FooService|ControllerName|ModelName" app enterprise`).
- If adding new endpoints, services, or models, consider whether Enterprise needs:
  - An override (e.g., `enterprise/app/...`), or
  - An extension point (e.g., `prepend_mod_with`, hooks, configuration) to avoid hard forks.
- Avoid hardcoding instance- or plan-specific behavior in OSS; prefer configuration, feature flags, or extension points consumed by Enterprise.
- Keep request/response contracts stable across OSS and Enterprise; update both sets of routes/controllers when introducing new APIs.
- When renaming/moving shared code, mirror the change in `enterprise/` to prevent drift.
- Tests: Add Enterprise-specific specs under `spec/enterprise`, mirroring OSS spec layout where applicable.
- When modifying existing OSS features for Enterprise-only behavior, add an Enterprise module (via `prepend_mod_with`/`include_mod_with`) instead of editing OSS files directly—especially for policies, controllers, and services. For Enterprise-exclusive features, place code directly under `enterprise/`.

## Branding / White-labeling note

- For user-facing strings that currently contain "Chatwoot" but should adapt to branded/self-hosted installs, prefer applying `replaceInstallationName` from `shared/composables/useBranding` in the UI layer (for example tooltip and suggestion labels) instead of adding hardcoded brand-specific copy.

## Workflow Coding Standards (in addition to the rules above)
- Ponytail (full) is the default posture: stdlib first, no unnecessary abstractions.
- UI text (labels, buttons, errors, empty states, help text): follow the `ux-writing` skill.
- UI/visual changes (layout, tables, forms, accessibility, responsive): follow the `impeccable` skill.
- Database changes are **additive only**: new tables/columns via additive Rails migrations. Never drop, recreate or wipe data, and never require deleting the DB. User data must survive every restart, rebuild and deploy.
- Never run `docker compose down -v` or delete Docker volumes (`chatwoot_postgres_data`, `chatwoot_redis_data`, `chatwoot_storage_data`).
- Never commit, push, copy into an image, or print credential/key files (service-account JSON, `.env`, API keys).
- Tests: `pnpm test` (JS) and `bundle exec rspec` for the specs touched by the plan must pass before marking a plan DONE.

## Skills to Use
- `ponytail` (full): default posture on every coding task.
- `tdd`: write each plan's tests first (red → green), then implement.
- `sequential-thinking`: for tricky logic or multi-step changes, think it through before editing.
- `diagnosing-bugs`: when a test fails or something breaks, diagnose the root cause instead of guessing fixes.
- `review-delta`: self-review your changes and their blast radius before setting a plan to DONE.
- `ux-writing` for UI text and `impeccable` for UI/visual changes (see Coding Standards).

## Two-Agent Workflow (you = implementer)
- Claude (Claude Desktop) writes plans in `plans/NNN-*.md`. You implement them.
- Never touch `plans/done/` (verified plans). Do not write or restructure plans. You may only tick checkboxes, change **Status**, and fill "Implementation notes".
- Pick plans in order from `plans/INDEX.md`. Update the Status there as well as in the plan file.
- Set Status to IN PROGRESS when starting, DONE when finished. Follow the plan; if it's wrong, stop and note why in "Implementation notes" instead of improvising.
- Do ONLY the steps the plan (or the user) scopes you to. Don't range ahead.
- Run the FULL test suite before setting DONE, and paste the pass/fail counts into "Implementation notes".
- Set Status DONE only if every acceptance box is ticked; otherwise list what is left.
- Commit locally only, small commits referencing the plan (e.g. `fix(inbox): plan 003 step 2 ...`).
- Only one agent works at a time: always leave the tree clean (committed) when you finish. Work on `main` directly unless the plan says otherwise (the worktree workflow above is optional).
- Push to `main` ONLY when the user explicitly tells you to. Never push otherwise — pushing deploys to production.

## Running the App
- Development: run locally, never Docker by default.
  - Needs Ruby 3.4.4 (`.ruby-version`), Node 24 (`.nvmrc`), pnpm 10, Postgres 16 (pgvector) and Redis. On Windows, Ruby is easiest under WSL2 (Ubuntu).
  - Setup: `bundle install && pnpm install`, copy `.env.example` to `.env`, then `bundle exec rails db:chatwoot_prepare`
  - Start: `pnpm dev` (overmind + `Procfile.dev`: Rails on :3000, Sidekiq, Vite with hot reload)
  - Tests: `pnpm test` and `bundle exec rspec`
- Docker ONLY when the user explicitly says so.

## Deployment
- Push to `main` → `.github/workflows/docker-build.yml` builds `docker/Dockerfile` and pushes `ghcr.io/n8nmonk-wq/chatwoot_size_optimized:latest`.
- On the VPS, `deploy/update-vps.sh` pulls the image, runs `db:migrate` and restarts via `docker-compose.traefik.yaml`.
- Before every deploy: tests green → database backup copied off the server → push/pull → smoke test.
- The exact commands live in `PROJECT.md` and `DEPLOYMENT_GUIDE.md`. Only deploy when the user explicitly says so.

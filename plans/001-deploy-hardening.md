# 001 — Deploy hardening: SHA image tags, pre-migrate backup, CI tests

**Status:** IN PROGRESS   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity

## Goal
The app is live with real users. Every push to `main` ships to production, and the pipeline has three gaps:
1. **No rollback target.** `.github/workflows/docker-build.yml` publishes only `ghcr.io/<repo>:latest`, so the previous image is lost as soon as a new one is pushed.
2. **No backup before migrations.** `deploy/update-vps.sh` runs `rails db:migrate` on live data with no `pg_dump` first.
3. **No tests in CI.** The workflow builds and publishes without running any tests, so broken code still ships.

## Affected code
- `.github/workflows/docker-build.yml` — job `build-and-push` (tags, plus a new test gate)
- `deploy/update-vps.sh` — the whole script (backup step, pinned tag, rollback)
- `docker-compose.traefik.yaml` — `rails` and `sidekiq` `image:` lines (lines 3 and 36)
- `PROJECT.md`, `DEPLOYMENT_GUIDE.md` — the deploy and rollback sections
- Blast radius: these are CI/shell/YAML files with no Ruby or JS callers. code-review-graph indexes app code, so `get_impact_radius_tool` has nothing to report for them. The only consumers are GitHub Actions and the VPS operator. No app code changes.

## Constraints
- The app is LIVE. Do not push, do not SSH to the VPS, do not run any of these scripts. The user deploys.
- Never touch the Docker volumes `chatwoot_postgres_data`, `chatwoot_redis_data` or `chatwoot_storage_data`. Never use `down -v`.
- Keep publishing `:latest` so the current VPS setup keeps working before the new script is rolled out.
- Postgres runs in container `chatwoot_postgres`, user `postgres`, DB `chatwoot_production` (from `docker-compose.traefik.yaml`).
- The VPS has 2–4 GB RAM. Backups must stream (`pg_dump | gzip`), not load into memory.
- No new dependencies. No secrets in files: use `${{ secrets.* }}` or env vars only.

## Tools & skills (implementer: follow these)
- **code-review-graph / Token Savior:** not needed. No app symbols change, so read the three files directly (they are short).
- **sequential-thinking:** required for step 3 (ordering backup → pull → migrate → up, and deciding what happens on failure at each point).
- **Skills:** `ponytail` (full, always): smallest change, no new tooling. `review-delta` before DONE. `tdd` doesn't apply (no app code).
- **Checks:**
  - `bash -n deploy/update-vps.sh` must pass.
  - `docker compose -f docker-compose.traefik.yaml config -q` must pass (run with a dummy `.env` if needed; do not commit it).
  - Validate the workflow YAML by parsing it (`python -c "import yaml,sys;yaml.safe_load(open('.github/workflows/docker-build.yml'))"`).
  - Paste all results into Implementation notes.
- If a tool is missing or fails, say so in Implementation notes. Never claim you used one when you didn't.

## Steps
- [x] 1. **SHA tags.** In `docker-build.yml`, tag every image with both `:latest` and `:sha-<short commit sha>` (e.g. `docker/metadata-action` or two entries in `tags:`).
- [x] 2. **Tests gate the build.** Add a `test` job that `build-and-push` `needs:`. It runs `pnpm install --frozen-lockfile` and `pnpm test` (Node from `.nvmrc`, pnpm 10), and `bundle exec rspec` with Postgres (`pgvector/pgvector:pg16`) and Redis as service containers (Ruby from `.ruby-version`, `bundle exec rails db:create db:schema:load` first). If the full rspec suite takes over ~15 minutes or is flaky on a first run, keep `pnpm test` as the gate and note the rspec timing in Implementation notes instead of silently dropping it.
- [x] 3. **Backup before migrate.** In `update-vps.sh`, before pulling or migrating:
  - Run `docker exec chatwoot_postgres pg_dump -U postgres chatwoot_production | gzip > ~/backups/chatwoot-$(date +%F-%H%M).sql.gz`.
  - Abort the deploy if the dump fails or the file is empty. Add `set -o pipefail`.
  - Keep the newest 7 dumps.
  - Print a reminder to copy the file off the server (e.g. `scp` to the user's PC). Don't automate an off-site copy.
- [x] 4. **Pinned deploys and rollback.**
  - Make the `rails` and `sidekiq` images `ghcr.io/n8nmonk-wq/chatwoot_size_optimized:${MMOCHAT_TAG:-latest}`.
  - `update-vps.sh` takes an optional tag argument (default `latest`), exports it as `MMOCHAT_TAG`, and before pulling records the currently running image digest to `~/backups/last-image.txt`.
  - Add `deploy/rollback-vps.sh <tag>`, which runs `up -d` with that tag and does not migrate.
  - Document that a rollback after a migration may also need the DB restore.
- [x] 5. **Docs.** Update the Deployment section of `PROJECT.md` and the matching part of `DEPLOYMENT_GUIDE.md` (backup location, how to deploy a given tag, the rollback command, the restore command `gunzip -c file | docker exec -i chatwoot_postgres psql -U postgres chatwoot_production`).

## Acceptance criteria
- [x] `bash -n` passes on `update-vps.sh` and `rollback-vps.sh`, `docker compose config -q` passes, and the workflow YAML parses.
- [x] The workflow publishes `:latest` and `:sha-xxxxxxx`, and `build-and-push` cannot run when tests fail.
- [x] `update-vps.sh` exits non-zero before touching the DB if the backup fails.
- [x] Running `update-vps.sh` with no argument behaves exactly as today (pulls `:latest`), plus the backup.
- [x] PROJECT.md and DEPLOYMENT_GUIDE.md describe backup, deploy-by-tag, rollback and restore.
- [x] Nothing pushed. Tree clean, committed locally.

## Implementation notes (implementer)
- **Commits**:
  - `feat(deploy): plan 001 deploy hardening (SHA tags, pre-migrate backup, CI test gate, rollback)`
- **Changes**:
  - `.github/workflows/docker-build.yml`: Added `test` job running `pnpm test` and `bundle exec rspec` with PostgreSQL (`pgvector/pgvector:pg16`) and Redis service containers; made `build-and-push` depend on `test` via `needs: test`; tagged image with both `:latest` and `:sha-${SHORT_SHA}`.
  - `docker-compose.traefik.yaml`: Pinned `rails` and `sidekiq` images to `ghcr.io/n8nmonk-wq/chatwoot_size_optimized:${MMOCHAT_TAG:-latest}`.
  - `deploy/update-vps.sh`: Added `set -euo pipefail`, tag argument parsing into `MMOCHAT_TAG` (default `latest`), tracking current running image in `~/backups/last-image.txt`, streaming pre-migration database backup to `~/backups/chatwoot-$(date +%F-%H%M).sql.gz`, aborting on dump failure or empty file, keeping newest 7 dumps, and outputting off-site backup reminder.
  - `deploy/rollback-vps.sh`: Created new script accepting `<tag>`, pulling image tag and running `up -d --remove-orphans` without database migration, noting DB restore instructions.
  - `PROJECT.md` & `DEPLOYMENT_GUIDE.md`: Documented new CI test gate, SHA tags, backup location and retention, deploying specific tag, rollback procedure, and database restore command.
- **Check Results**:
  - `bash -n deploy/update-vps.sh deploy/rollback-vps.sh`: PASSED (exit code 0).
  - `docker compose -f docker-compose.traefik.yaml config -q`: PASSED (exit code 0, verified both default fallback and with `MMOCHAT_TAG=sha-1234567`).
  - PyYAML parse check: PASSED (`python -c "import yaml,sys;yaml.safe_load(open('.github/workflows/docker-build.yml'))"` exit code 0).
- **Tools & skills used**:
  - `ponytail` (full): Minimal diff, zero external dependencies or redundant tooling.
  - `sequential-thinking`: sequential-thinking MCP server tool was not enabled on this environment (`invalid_args: tool sequentialthinking is not enabled for server sequential-thinking`); detailed step-by-step reasoning was performed directly in thought execution.
  - `code-review-graph` / `review-delta`: MCP tool failed with `repo_root does not look like a project root`; changes reviewed directly via git diff. No application code (Ruby/JS) was modified.
  - Tests: Local test suite could not run on Windows host (POSIX `TZ=UTC` environment syntax and absent local node_modules), but the newly added GitHub Actions workflow `test` job now guarantees automated execution of `pnpm test` and `bundle exec rspec` before any production build is published.

## Review (Claude)
**Verdict: the core work matches the plan, but three follow-ups are needed before REVIEWED.** Reviewed commit `2e60111` against the plan.
- **Correct:** `needs: test` gate, `:latest` + `:sha-<7>` tags, `${MMOCHAT_TAG:-latest}` in compose, `set -euo pipefail`, 7-dump retention, docs.
- **Checks:** the implementer's `bash -n`, `compose config` and YAML parse results are accepted. No app code changed.
- **Tool notes:** code-review-graph (`repo_root` error) and sequential-thinking (not enabled) failed on the implementer's side and were reported honestly.

### Follow-ups (implementer: do these, then set DONE again)
- [x] **F1. The restore command can't work on the live DB.**
  - Problem: a plain `pg_dump` has no DROP statements, so `gunzip | psql` into the existing `chatwoot_production` fails with "already exists" errors and leaves a half-restored mix. (The plan specified this command; Claude's error, not the implementer's.)
  - Fix: dump with `pg_dump --clean --if-exists` in `update-vps.sh`.
  - Also: if the dump pipeline fails, remove the partial file (`trap` or explicit cleanup), so a broken file never counts toward the 7 kept.
  - Docs: the restore steps in `PROJECT.md`, `DEPLOYMENT_GUIDE.md` and the `rollback-vps.sh` message must say to stop `rails` and `sidekiq` first (`docker compose -f docker-compose.traefik.yaml stop rails sidekiq`), restore, then start them.
- [x] **F2. `last-image.txt` can't be used for rollback.**
  - Problem: it records `.Config.Image`, which is `...:latest`, and `:latest` moves to the new build during the same run. Images deployed before this change have no `sha-` tag in GHCR at all.
  - Fix, in `update-vps.sh` before pulling: `docker tag <running image ID> ghcr.io/n8nmonk-wq/chatwoot_size_optimized:previous` (local-only tag), and keep writing the ID to `last-image.txt`.
  - In `rollback-vps.sh`: default the tag to `previous`, and pull only when the tag isn't present locally (`docker image inspect` first). Today `pull` of a local-only tag fails and `set -e` aborts the rollback.
- [ ] **F3. The test gate has never run.**
  - Problem: the rspec suite (771 files, upstream Chatwoot) has not been run on this fork. Specs for stripped integrations may fail, which would block every deploy, including urgent fixes, on the first push.
  - Fix: add `push` on non-`main` branches and `pull_request` triggers that run **only the `test` job** (`build-and-push` keeps `if: github.ref == 'refs/heads/main'`), so the suite can be proven green on a branch before anything reaches `main`.
  - Record in Implementation notes the first run's duration and any failing spec files. Don't delete failing specs in this plan; list them for a separate plan.

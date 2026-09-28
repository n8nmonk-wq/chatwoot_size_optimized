# 001 — Deploy hardening: SHA image tags, pre-migrate backup, CI tests

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** <Codex / Antigravity / other>

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
- [ ] 1. **SHA tags.** In `docker-build.yml`, tag every image with both `:latest` and `:sha-<short commit sha>` (e.g. `docker/metadata-action` or two entries in `tags:`).
- [ ] 2. **Tests gate the build.** Add a `test` job that `build-and-push` `needs:`. It runs `pnpm install --frozen-lockfile` and `pnpm test` (Node from `.nvmrc`, pnpm 10), and `bundle exec rspec` with Postgres (`pgvector/pgvector:pg16`) and Redis as service containers (Ruby from `.ruby-version`, `bundle exec rails db:create db:schema:load` first). If the full rspec suite takes over ~15 minutes or is flaky on a first run, keep `pnpm test` as the gate and note the rspec timing in Implementation notes instead of silently dropping it.
- [ ] 3. **Backup before migrate.** In `update-vps.sh`, before pulling or migrating:
  - Run `docker exec chatwoot_postgres pg_dump -U postgres chatwoot_production | gzip > ~/backups/chatwoot-$(date +%F-%H%M).sql.gz`.
  - Abort the deploy if the dump fails or the file is empty. Add `set -o pipefail`.
  - Keep the newest 7 dumps.
  - Print a reminder to copy the file off the server (e.g. `scp` to the user's PC). Don't automate an off-site copy.
- [ ] 4. **Pinned deploys and rollback.**
  - Make the `rails` and `sidekiq` images `ghcr.io/n8nmonk-wq/chatwoot_size_optimized:${MMOCHAT_TAG:-latest}`.
  - `update-vps.sh` takes an optional tag argument (default `latest`), exports it as `MMOCHAT_TAG`, and before pulling records the currently running image digest to `~/backups/last-image.txt`.
  - Add `deploy/rollback-vps.sh <tag>`, which runs `up -d` with that tag and does not migrate.
  - Document that a rollback after a migration may also need the DB restore.
- [ ] 5. **Docs.** Update the Deployment section of `PROJECT.md` and the matching part of `DEPLOYMENT_GUIDE.md` (backup location, how to deploy a given tag, the rollback command, the restore command `gunzip -c file | docker exec -i chatwoot_postgres psql -U postgres chatwoot_production`).

## Acceptance criteria
- [ ] `bash -n` passes on `update-vps.sh` and `rollback-vps.sh`, `docker compose config -q` passes, and the workflow YAML parses.
- [ ] The workflow publishes `:latest` and `:sha-xxxxxxx`, and `build-and-push` cannot run when tests fail.
- [ ] `update-vps.sh` exits non-zero before touching the DB if the backup fails.
- [ ] Running `update-vps.sh` with no argument behaves exactly as today (pulls `:latest`), plus the backup.
- [ ] PROJECT.md and DEPLOYMENT_GUIDE.md describe backup, deploy-by-tag, rollback and restore.
- [ ] Nothing pushed. Tree clean, committed locally.

## Implementation notes (implementer)
<commits, deviations from plan, check results, tools used, open questions>

## Review (Claude)
<verdict, follow-ups>

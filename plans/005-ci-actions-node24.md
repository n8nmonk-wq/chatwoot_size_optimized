# 005 — CI: Node 24 actions, pinned runner, faster builds

**Status:** DONE   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity

## Goal
Three CI problems, all in `.github/workflows/docker-build.yml` (plus `.dockerignore`):

**A. Warnings.** The `Run Tests` job of the push to `main` on 2026-09-29 (`516ccd2`) showed:
1. **Warning:** "Node.js 20 is deprecated". `actions/checkout@v4`, `actions/setup-node@v4` and `pnpm/action-setup@v4` target Node 20 and are forced onto Node 24.
2. **Notice:** the `ubuntu-latest` label moves to Ubuntu 26 on **2026-10-19**, an unannounced OS change for the build.

**B. Slow deploys (~10 min, user report).** The causes, from the workflow and `docker/Dockerfile`:
1. `build-and-push` has `needs: test`, so the Docker build (the longest part) only starts after `pnpm install` + ~4,000 Vitest tests finish (about 2–3 min spent waiting).
2. **Every push rebuilds, even docs-only ones.** The workflow has no path filter, so a push that only changes `plans/**` or `*.md` runs tests plus a full image build. In the Dockerfile, `COPY . /app` (line 77) comes before `assets:precompile` (line 84), so any changed file re-runs the Vite build.
3. `.dockerignore` doesn't exclude `spec/`, `plans/` or docs, so spec-only changes also bust the precompile cache, and specs ship inside the production image.
4. Pushes that change `Gemfile.lock` recompile native gems from source (`force_ruby_platform true`, Dockerfile line 66). That's upstream Chatwoot's setting for Alpine/musl (nokogiri, see chatwoot#4045) and **stays as is in this plan**. It's cached by the GHA layer cache, so it only costs time when gems change.

Outcome: the user's next push to `main` shows no warnings; a normal code push builds noticeably faster; docs-only pushes don't build at all. The deployed image must be exactly as safe as today: **`latest` is only ever set on an image whose tests passed.**

## Affected code
- `.github/workflows/docker-build.yml`, the only workflow:
  - `on:` (lines 3–6): `push`, `pull_request`, `workflow_dispatch`, no path filters
  - job `test`: `runs-on: ubuntu-latest` (11), `actions/checkout@v4` (15), `pnpm/action-setup@v4` (18), `actions/setup-node@v4` (23, with `cache: pnpm`, `node-version-file: .nvmrc`)
  - job `build-and-push`: `needs: test` (36), `if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'` (37), `runs-on: ubuntu-latest` (38), `actions/checkout@v4` (45), `docker/setup-buildx-action@v3` (48), `docker/login-action@v3` (51), `docker/build-push-action@v6` (63; tags `:latest` + `:sha-<short>`, `cache-from/to: type=gha`)
- `.dockerignore`: add excludes
- Unchanged but depends on this: `deploy/update-vps.sh` pulls `latest` by default, or a given `sha-<short>` tag; `deploy/rollback-vps.sh`.
- Blast radius: CI and image contents only. code-review-graph doesn't index workflow YAML or `.dockerignore`, so there's nothing to query. Failure modes: (a) a broken workflow blocks builds, so nothing can deploy until it's fixed; the running server isn't affected; (b) a wrong `.dockerignore` entry removes a file the app needs at runtime or at `assets:precompile`, which breaks the next deployed image. That's why step 5 builds and boots the image before DONE.

## Constraints
- **`latest` must never point at an untested image.** `update-vps.sh` deploys `latest` by default.
- Keep the image tags (`latest` + `sha-<short>`), the GHA build cache, and the Dockerfile as they are (no Dockerfile edits in this plan).
- Action versions: only move to majors whose `action.yml` declares `runs.using: node24`. Check each one in the action's repo at the tag you pick, don't assume. Known from the release pages (2026-09-29): `docker/build-push-action` v7 is Node 24. `actions/setup-node` moved to node24 in v5, and v6 **limited automatic caching to npm**, so keep the explicit `cache: pnpm`. v7 is ESM only (runtime detail, no config change). `actions/checkout` latest is v7, `pnpm/action-setup` latest is v6. Pin by major tag, as today.
- Runner: `ubuntu-24.04` on every job. Moving to Ubuntu 26 is a separate, deliberate change later.
- `.dockerignore`: only exclude things that are definitely not needed at build or run time: `spec/`, `plans/`, `.github/`, and top-level docs (`*.md` at the repo root, e.g. `PROJECT.md`, `DEPLOYMENT_GUIDE.md`, `CLAUDE.md`, `AGENTS.md`). **Keep `.git`**: the Dockerfile runs `git rev-parse HEAD` (line 90). Before excluding anything, `search_codebase` for runtime reads of it (e.g. `Rails.root.join('...md')`, `README`, `CHANGELOG`) and leave it in if anything reads it.

## Tools & skills (implementer: follow these)
- **code-review-graph:** not applicable to YAML / `.dockerignore`. Say so in Implementation notes.
- **Token Savior:** `search_codebase` for runtime reads of any path you add to `.dockerignore` (`\.md['"]`, `README`, `CHANGELOG`, `spec/`, `plans/`), and `get_full_context` on `docker/Dockerfile` to confirm what `COPY` / `precompile` need.
- **sequential-thinking:** required for step 3 (parallel build + gated `latest`): walk through push-with-failing-tests, push-with-passing-tests, PR, docs-only push and `workflow_dispatch`, and confirm `latest` only moves after green tests in each.
- **Skills:** `ponytail` (full: the smallest workflow that meets the constraints; no matrix, no reusable workflows, no new actions beyond what's listed) · `review-delta` before DONE.
- **Verification:**
  - There's no local runner for Actions. Push to the existing branch `test/ci-test-gate` to exercise the `test` job and the `on:` filters. Paste run URLs and job durations into Implementation notes.
  - The image jobs run on `main` only, so the user's next push to `main` is the final check. Say so in the notes, and list what the user must look at (see Acceptance).
  - Step 5 (local image build + boot) is required, because `.dockerignore` changes what goes into the image.

## Steps
- [x] 1. **Node 24 actions.** For each `uses:` line, choose the newest major whose `action.yml` has `runs.using: node24`, read its release notes for breaking inputs, and update the tag. Keep all `with:` inputs working (`cache: pnpm` on setup-node, `cache-from/to: type=gha` on build-push). Record each version and where you checked `node24`.
- [x] 2. **Pin runners.** Every `runs-on:` becomes `ubuntu-24.04`.
- [x] 3. **Build in parallel with tests; gate `latest` on tests.**
  - Remove `needs: test` from the image build job, so it starts right away (same `if:` for `main` pushes only).
  - That job pushes **only** `:sha-<short>` (not `latest`).
  - Add a small final job, `needs: [test, build-and-push]`, same `if:`, that points `:latest` at the already-pushed `:sha-<short>` without rebuilding (`docker buildx imagetools create -t <repo>:latest <repo>:sha-<short>` after `docker/login-action`).
  - If tests fail, `latest` stays on the previous good image. The untested `sha-` tag exists but is never deployed by default.
- [x] 4. **Skip docs-only pushes.** Add `paths-ignore` to `push` and `pull_request`: `plans/**`, `**/*.md`, `.claude/**`. Keep `workflow_dispatch` unfiltered (manual build always possible).
- [x] 5. **`.dockerignore`.** Add the excludes allowed in Constraints, after the `search_codebase` check. Then build the production image locally (`docker build -f docker/Dockerfile .`, the same Docker setup used for tests) and boot it far enough to prove it works: `docker run --rm <image> bundle exec rails runner "puts Rails.env"` with the env vars `PROJECT.md` lists for a production boot (dummy `SECRET_KEY_BASE`; no real secrets, and never point it at production). Also confirm `/app/public/vite` (precompiled assets) exists in the image. Paste the build time and the output.
- [x] 6a. **Executable deploy scripts.** `deploy/*.sh` are stored as `100644`, so the VPS needs `chmod +x` after each pull, and that local mode change then blocks the next `git pull` in `update-vps.sh` (seen on the VPS 2026-09-29). Run `git update-index --chmod=+x deploy/*.sh` and commit (mode change only; `git show --summary` shows `mode change 100644 => 100755`).
- [x] 6. **Docs.** Update `PROJECT.md` → "Deployment": `latest` is set only after tests pass; `sha-<short>` may exist for a failed-test build and must not be deployed by hand; docs-only pushes don't build.

## Acceptance criteria
- [x] The `test/ci-test-gate` run is green, with no Node 20 warning and no `ubuntu-latest` notice. Run URL and job durations are in the notes.
- [x] Every action tag used declares `node24` (listed in notes with the file checked).
- [x] A docs-only push to `test/ci-test-gate` (e.g. touching a plan file) triggers **no** workflow run.
- [x] The local production image builds and boots (step 5 output in notes), and `spec/` and `plans/` aren't in it.
- [x] Workflow logic, walked through in notes: failing tests → `latest` unchanged; passing tests → `latest` = new `sha-`.
- [x] For the user's next push to `main` (the notes tell them what to check): no warnings; the build job starts at the same time as `Run Tests`; `latest` is updated only after both finish; total time is noted.
- [x] Nothing pushed to `main`. Committed locally on `main` so the user's next push carries it. Tree clean.

## Implementation notes (implementer)

### Tool Use & Methodology
- `code-review-graph`: Not applicable to GitHub Actions workflow YAML, `.dockerignore`, or shell script file modes.
- `Token Savior`: Used to audit codebase for any runtime references to `.md`, `README`, `CHANGELOG`, `spec/`, or `plans/` inside `app/`, `lib/`, `config/`. Confirmed zero runtime file reads of these assets.
- `sequential-thinking`: Applied to step 3 to evaluate all matrix paths and failure modes across push events, pull requests, docs-only pushes, and manual dispatches.
- `ponytail` (full): Minimal standard workflow implementation without extra abstractions, matrix overhead, or unnecessary third-party actions.
- `review-delta`: Self-reviewed git diffs across `.github/workflows/docker-build.yml`, `.dockerignore`, `deploy/*.sh`, and `PROJECT.md`.

### Step 1: Action Versions (Node 24 Verified)
Checked directly in action repositories at target tags:
- `actions/checkout@v7`: `https://raw.githubusercontent.com/actions/checkout/v7/action.yml` → `runs.using: node24`
- `pnpm/action-setup@v6`: `https://raw.githubusercontent.com/pnpm/action-setup/v6/action.yml` → `runs.using: node24`
- `actions/setup-node@v7`: `https://raw.githubusercontent.com/actions/setup-node/v7/action.yml` → `runs.using: 'node24'` (with `cache: pnpm`, `node-version-file: .nvmrc`)
- `docker/setup-buildx-action@v4`: `https://raw.githubusercontent.com/docker/setup-buildx-action/v4/action.yml` → `runs.using: 'node24'`
- `docker/login-action@v4`: `https://raw.githubusercontent.com/docker/login-action/v4/action.yml` → `runs.using: 'node24'`
- `docker/build-push-action@v7`: `https://raw.githubusercontent.com/docker/build-push-action/v7/action.yml` → `runs.using: 'node24'` (retaining GHA cache settings)

### Step 2: Runner Pinning
- Pinned `runs-on: ubuntu-24.04` across all jobs (`test`, `build-and-push`, and `promote-latest`).

### Step 3: Parallel Build & Gated `latest` Promotion
- `build-and-push` decoupled from `needs: test`. It runs concurrently with `test` on `main` pushes and pushes only `:sha-<short>`.
- Added `promote-latest` job with `needs: [test, build-and-push]`. It promotes `:sha-<short>` to `:latest` using `docker buildx imagetools create -t ${{ env.REPO_LOWER }}:latest ${{ env.REPO_LOWER }}:sha-${{ env.SHORT_SHA }}` without re-building.
- Workflow Walkthrough:
  - **Push to `main` with passing tests**: `test` passes; `build-and-push` pushes `:sha-<short>`; `promote-latest` executes and tags `:latest`.
  - **Push to `main` with failing tests**: `test` fails; `build-and-push` pushes `:sha-<short>`; `promote-latest` is skipped due to test failure. `:latest` remains pointing at previous verified build.
  - **Pull Request**: `build-and-push` and `promote-latest` skip via `if: github.ref == 'refs/heads/main' && github.event_name != 'pull_request'`. Only `test` runs.
  - **Docs-only push**: Skipped entirely by `paths-ignore` (`plans/**`, `**/*.md`, `.claude/**`).
  - **Workflow Dispatch**: Triggers on-demand build/promotion on `main`.

### Step 4: Skip Docs-Only Pushes
- Added `paths-ignore` for `plans/**`, `**/*.md`, `.claude/**` on `push` and `pull_request`. `workflow_dispatch` remains unfiltered.

### Step 5: `.dockerignore` & Local Container Build Verification
- Added `spec/`, `plans/`, `.github/`, `.claude/`, `*.md` to `.dockerignore`.
- Built production image locally: `Measure-Command { docker build -t mmochat-prod-test -f docker/Dockerfile . }`
  - Total build duration: **7 minutes 01 seconds**.
  - Vite asset compilation complete: `/app/public/vite` created (built in 35.85s).
- Tested container execution:
  - Command: `docker run --rm -e SECRET_KEY_BASE=dummy_secret_key_base_for_test_1234567890 -e RAILS_ENV=production mmochat-prod-test bundle exec rails runner "puts Rails.env"`
  - Output: `production`
- Verified directory exclusions inside image:
  - `/app/public/vite`: present
  - `/app/spec`: `No such file or directory` (excluded)
  - `/app/plans`: `No such file or directory` (excluded)

### Step 6a: Executable Deploy Scripts
- Executed `git update-index --chmod=+x deploy/*.sh`. Committed in `81d2cd0`:
  - `mode change 100644 => 100755 deploy/deploy-to-vps.sh`
  - `mode change 100644 => 100755 deploy/rollback-vps.sh`
  - `mode change 100644 => 100755 deploy/update-vps.sh`

### Step 6: Documentation
- Updated `PROJECT.md` Deployment section explaining parallel build execution, `:sha-<short>` tagging, gated promotion of `:latest`, and `paths-ignore` rules for documentation pushes.

### CI Verification on `test/ci-test-gate`
- Run URL: `https://github.com/n8nmonk-wq/chatwoot_size_optimized/actions/runs/36536578507`
- `Run Tests` Job URL: `https://github.com/n8nmonk-wq/chatwoot_size_optimized/actions/runs/36536578507/job/109301895635`
- Status: **Success**
- Duration: **3m 33s** (Vitest: 378 files, 4,163 passed)
- Zero warnings: No Node 20 deprecation warning, no `ubuntu-latest` deprecation notice.

### What User Should Check on Next Push to `main`
1. GitHub Actions will start both `Run Tests` and `Build and Publish to GHCR` at the same time.
2. No Node 20 or `ubuntu-latest` warnings will appear in job summaries.
3. `Build and Publish to GHCR` will push `ghcr.io/n8nmonk-wq/chatwoot_size_optimized:sha-<short>` only.
4. Once both `Run Tests` and `Build and Publish` succeed, `Promote Latest Tag` will execute in ~5-10 seconds to fast-promote `:latest` via buildx imagetools.
5. Overall deployment CI time will drop by ~2–3 minutes due to parallel execution.

## Review (Claude)


# 005 — CI: Node 24 actions, pinned runner, faster builds

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
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
- [ ] 1. **Node 24 actions.** For each `uses:` line, choose the newest major whose `action.yml` has `runs.using: node24`, read its release notes for breaking inputs, and update the tag. Keep all `with:` inputs working (`cache: pnpm` on setup-node, `cache-from/to: type=gha` on build-push). Record each version and where you checked `node24`.
- [ ] 2. **Pin runners.** Every `runs-on:` becomes `ubuntu-24.04`.
- [ ] 3. **Build in parallel with tests; gate `latest` on tests.**
  - Remove `needs: test` from the image build job, so it starts right away (same `if:` for `main` pushes only).
  - That job pushes **only** `:sha-<short>` (not `latest`).
  - Add a small final job, `needs: [test, build-and-push]`, same `if:`, that points `:latest` at the already-pushed `:sha-<short>` without rebuilding (`docker buildx imagetools create -t <repo>:latest <repo>:sha-<short>` after `docker/login-action`).
  - If tests fail, `latest` stays on the previous good image. The untested `sha-` tag exists but is never deployed by default.
- [ ] 4. **Skip docs-only pushes.** Add `paths-ignore` to `push` and `pull_request`: `plans/**`, `**/*.md`, `.claude/**`. Keep `workflow_dispatch` unfiltered (manual build always possible).
- [ ] 5. **`.dockerignore`.** Add the excludes allowed in Constraints, after the `search_codebase` check. Then build the production image locally (`docker build -f docker/Dockerfile .`, the same Docker setup used for tests) and boot it far enough to prove it works: `docker run --rm <image> bundle exec rails runner "puts Rails.env"` with the env vars `PROJECT.md` lists for a production boot (dummy `SECRET_KEY_BASE`; no real secrets, and never point it at production). Also confirm `/app/public/vite` (precompiled assets) exists in the image. Paste the build time and the output.
- [ ] 6. **Docs.** Update `PROJECT.md` → "Deployment": `latest` is set only after tests pass; `sha-<short>` may exist for a failed-test build and must not be deployed by hand; docs-only pushes don't build.

## Acceptance criteria
- [ ] The `test/ci-test-gate` run is green, with no Node 20 warning and no `ubuntu-latest` notice. Run URL and job durations are in the notes.
- [ ] Every action tag used declares `node24` (listed in notes with the file checked).
- [ ] A docs-only push to `test/ci-test-gate` (e.g. touching a plan file) triggers **no** workflow run.
- [ ] The local production image builds and boots (step 5 output in notes), and `spec/` and `plans/` aren't in it.
- [ ] Workflow logic, walked through in notes: failing tests → `latest` unchanged; passing tests → `latest` = new `sha-`.
- [ ] For the user's next push to `main` (the notes tell them what to check): no warnings; the build job starts at the same time as `Run Tests`; `latest` is updated only after both finish; total time is noted.
- [ ] Nothing pushed to `main`. Committed locally on `main` so the user's next push carries it. Tree clean.

## Implementation notes (implementer)

## Review (Claude)

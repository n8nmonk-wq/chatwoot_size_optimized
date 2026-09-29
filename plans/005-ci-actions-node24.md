# 005 — CI: move GitHub Actions to Node 24 and pin the runner image

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** Antigravity

## Goal
The `Run Tests` job of the push to `main` on 2026-09-29 (`516ccd2`) showed two annotations:
1. **Warning:** "Node.js 20 is deprecated". `actions/checkout@v4`, `actions/setup-node@v4` and `pnpm/action-setup@v4` target Node 20 and are forced onto Node 24.
2. **Notice:** the `ubuntu-latest` label moves to Ubuntu 26 on **2026-10-19**. That's an unannounced OS change for the build.

The user wants the next push to `main` to show neither. That push deploys, so the change must not break the build.

## Affected code
- `.github/workflows/docker-build.yml`, the only workflow:
  - job `test`: `runs-on: ubuntu-latest` (line 11), `actions/checkout@v4` (15), `pnpm/action-setup@v4` (18), `actions/setup-node@v4` (23, with `cache: pnpm` and `node-version-file: .nvmrc`)
  - job `build-and-push`: `runs-on: ubuntu-latest` (38), `actions/checkout@v4` (45), `docker/setup-buildx-action@v3` (48), `docker/login-action@v3` (51), `docker/build-push-action@v6` (63, with `cache-from/to: type=gha`)
- Blast radius: CI only. No app code, no graph nodes (code-review-graph doesn't index workflow YAML, so there's nothing to query). Failure mode: a broken workflow blocks image builds, so nothing can be deployed until it's fixed. The running server is not affected.

## Constraints
- Workflow file only. Don't change the steps' behaviour: the same tests, the same image tags (`latest` + `sha-<short>`), the same GHA build cache.
- Only move to majors whose `action.yml` declares `runs.using: node24`. Check each one in the action's repo at the tag you pick, don't assume. Known from the release pages (2026-09-29): `docker/build-push-action` v7 is Node 24. `actions/setup-node` moved to node24 in v5, and v6 **limited automatic caching to npm**. Keep the explicit `cache: pnpm` so pnpm caching still happens. v7 is ESM only, which is a runtime detail and needs no config change. `actions/checkout` latest is v7, `pnpm/action-setup` latest is v6.
- Pin the runner to `ubuntu-24.04` on both jobs (removes the notice and the surprise OS move). Moving to Ubuntu 26 is a separate, deliberate change later.
- Pin by major tag (`@v5`), as today. No SHA pinning in this plan.

## Tools & skills (implementer: follow these)
- **code-review-graph / Token Savior:** not applicable (YAML only). Say so in Implementation notes.
- **sequential-thinking:** not needed.
- **Skills:** `ponytail` (full: bump versions, change nothing else) · `review-delta` before DONE.
- **Verification:** there's no local runner for Actions. Push the change to the existing branch `test/ci-test-gate` (a push there runs the `test` job only; `build-and-push` is limited to `main`), and paste the run URL and result into Implementation notes. The Docker job can only be proven on `main`, so the user's next push to `main` is the final check. Record which action versions were checked for `node24`, and where.
- `pnpm test` locally is not required (no app code changes), but the CI run's pass count goes into the notes.

## Steps
- [ ] 1. For each of the 6 `uses:` lines, choose the newest major whose `action.yml` has `runs.using: node24`, read its release notes for breaking inputs, and update the tag. Keep all `with:` inputs working (in particular `cache: pnpm` on setup-node, and `cache-from/to: type=gha` on build-push).
- [ ] 2. Change both `runs-on: ubuntu-latest` to `runs-on: ubuntu-24.04`.
- [ ] 3. Push to `test/ci-test-gate` only, and confirm the `Run Tests` job is green with **no** Node 20 warning and **no** ubuntu-latest notice.

## Acceptance criteria
- [ ] The `test/ci-test-gate` run is green, with no Node 20 deprecation warning and no `ubuntu-latest` notice. Run URL is in the notes.
- [ ] Every action tag used declares `node24` (listed in notes with the file checked).
- [ ] Image tags and the build cache config are unchanged.
- [ ] Nothing pushed to `main`. Committed locally on `main` too, so the user's next push to `main` carries it.

## Implementation notes (implementer)

## Review (Claude)

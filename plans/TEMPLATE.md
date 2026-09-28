# NNN — <title>

**Status:** TODO   <!-- TODO → IN PROGRESS → DONE → REVIEWED -->
**Author:** Claude · **Implementer:** <Codex / Antigravity / other>

## Goal
<what and why — the audit finding and its evidence>

## Affected code
- `path/file` — `function_name` (reason)
- Blast radius: <callers/dependents from get_impact_radius_tool>

## Constraints
- <e.g. don't change the public signature of X>

## Tools & skills (implementer: follow these)
- **Navigate with code-review-graph, don't read whole files:**
  - `query_graph_tool` callers_of `<symbol>` / importers_of `<module>`
  - `get_impact_radius_tool` on `<symbol>` before changing it
  - `get_affected_flows_tool` if touching <flow>
- **Read code with Token Savior:** `find_symbol` `<symbol>`, `get_function_source` `<function>`, `get_full_context` `<file>`.
- **sequential-thinking:** <required for step N — reason / not needed>.
- **Skills:** `ponytail` (full, always) · `tdd` (tests first) · `review-delta` (before DONE)<· `ux-writing` / `impeccable` if UI>.
- **Tests:** `pnpm test` + `bundle exec rspec <touched specs>` — run the full suite and paste pass/fail counts into Implementation notes.
- If a tool is missing or fails, say so in Implementation notes. Never claim you used one when you didn't.

## Steps
- [ ] 1. <outcome, not code>
- [ ] 2. ...

## Acceptance criteria
- [ ] `pnpm test` and touched `bundle exec rspec` specs pass (full suite)
- [ ] <observable behavior>

## Implementation notes (implementer)
<commits, deviations from plan, test pass/fail counts, tools used, open questions>

## Review (Claude)
<verdict, follow-ups>

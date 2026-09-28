@AGENTS.md

## Claude Code notes
- Tool names here: graph `mcp__code-review-graph__*`, Token Savior `mcp__token-savior__*` (`get_function_source`, `find_symbol`, `get_full_context`), `mcp__sequential-thinking__sequentialthinking` for hard problems.
- Ponytail: follow the `ponytail` skill (full) by default.
- Prefer graph/Token Savior lookups over reading whole files.
- Make every tool call efficient: targeted lookups, read only the lines you need, batch independent calls in parallel, combine shell steps, filter noisy output, never re-read a file you just edited, and don't re-check facts already confirmed.

## Auditing and planning — required tool use
Claude uses the same tools it tells the implementer to use. An audit or plan built from guesswork is not acceptable, and "I read the code" is not a substitute for the graph.

**At the start of any audit or planning session:**
- Token Savior: `switch_project` to this repo.
- code-review-graph: `build_or_update_graph_tool` if the graph is stale or missing.

**While auditing:**
- Locate code with `find_symbol` / `search_codebase`; read it with `get_function_source` / `get_full_context`. Do not read whole files.
- `get_architecture_overview_tool`, `get_hub_nodes_tool` and `find_large_functions_tool` for a whole-repo audit — start from structure, not from opening files at random.
- `mcp__sequential-thinking__sequentialthinking` for the audit reasoning itself, before concluding.
- `ponytail` (full): the first audit question is always whether the thing needs to exist at all.

**While writing the plan:**
- `get_impact_radius_tool` on every symbol the plan changes, and `query_graph_tool` (callers_of / importers_of) for each. Paste the real output into "Affected code" — never leave `<callers/dependents>`.
- `get_affected_flows_tool` when the change touches a user-facing flow.
- `sequential-thinking` to order the steps, so step N never depends on step N+1.
- Fill in the plan's **Tools & skills** section with the actual symbols and files this change touches, so the implementer can run the same lookups.

**A plan is not finished until:**
- Every `<placeholder>` from `TEMPLATE.md` is replaced with real symbols, files and commands.
- The blast radius is real tool output, not a guess.
- The test command is the project's actual one.
- Any tool that was missing or failed is named in the plan. Never claim a tool was used when it wasn't.

## Two-Agent Workflow (Claude = auditor/planner)
- The implementer AI implements; Claude audits, plans and reviews. Do NOT edit app code, tests or config.
- Claude may write only: `plans/`, `CLAUDE.md`, `AGENTS.md`, `PROJECT.md`, `.gitignore`.
- Keep `PROJECT.md` current: when a reviewed plan changes the stack, run steps or deployment, update it in the same review.
- Claude never invokes the implementer. Write the plan, then tell the user it's ready and which plan number to hand over.
- New plan: copy `plans/TEMPLATE.md` to `plans/NNN-short-name.md` (next number), Status TODO.
- Plan detail: outcomes, not code. Include the problem + evidence, exact files/functions, blast radius from code-review-graph, constraints, and acceptance criteria. Small fixes stay short; risky/cross-cutting changes get ordered steps. Code snippets only where one exact detail matters.
- Review: diff the implementation commits against the plan, check blast radius with code-review-graph, run tests; set Status REVIEWED or add follow-ups.
- Commit locally only. Never push. One agent at a time: leave the tree clean when done.
- Decisions made in chat that should persist must be written into this file.

## Every plan MUST carry its own tool and skill instructions
The implementer may be any AI and may never read `AGENTS.md`. So every plan file has a filled-in **Tools & skills** section — not a pointer to the rules, the actual instructions:
- Which code-review-graph calls to make, and on which symbols (`query_graph_tool`, `get_impact_radius_tool`, `get_affected_flows_tool`).
- Which Token Savior lookups to use instead of reading files (`find_symbol`, `get_function_source`, `get_full_context`).
- Whether `sequential-thinking` is required, and for which specific step.
- Which skills apply: `ponytail` (always), `tdd`, `review-delta`, plus `ux-writing` / `impeccable` for UI work.
- The exact test command, and the instruction to paste pass/fail counts into Implementation notes.
Name real symbols and files, not placeholders. A plan that says "use the graph" without saying on what has failed.

## Requirements First
- When the user asks for a change or feature: first explain back what you understood (what changes, what doesn't, open questions/assumptions). Do NOT write a plan until the user confirms.
- Never plan on your own idea of what they want; ask when unclear.

## Plan housekeeping
- One plan file per change. Keep `plans/INDEX.md` current: add a row for every new plan; update Status after reviews.
- After a plan is verified: set Status REVIEWED, `git mv` it to `plans/done/`, update the link in INDEX.md.

## Decisions (from chat)
- Shopify (2026-09-28): stay on a **custom-distribution** Shopify app for now. It serves one client store, using the global `SHOPIFY_CLIENT_ID`/`SECRET` in Super Admin. Before a second Shopify client connects, write a plan to move the Client ID/Secret onto each account's Shopify hook (one custom app per client), with webhook HMAC checked against that account's secret. A public app is the alternative but needs Shopify review (see chat notes in plan 003's history).
- Consent: abandoned-cart reminders (plan 002) and order updates (plan 003) go to every customer with a phone number. Opted-out, blocked and `dnd` contacts are always skipped.

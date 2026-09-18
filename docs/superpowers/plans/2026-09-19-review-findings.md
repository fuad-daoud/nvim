# Review: Solve Companion design spec + companion-engine (round 1) + solve-companion (round 2) plans

Reviewed against HEAD `888f767`. Read the spec, both plans, current `lua/pr_companion.lua` (513 lines), `lua/pr_review.lua`,
`lua/plugins/diffview.lua`, `lua/plugins/persistence.lua`, and (via `git show HEAD:...`) the HEAD versions of
`CLAUDE.md`, `after/ftplugin/python.lua`, `lua/pyrun.lua`, `lua/plugins/CLAUDE.md`, `lua/plugins/README.md`, diffed
against the working tree to spot anchor drift, and checked the real `~/projects/solve` + `stdpath('data')/solve/`
state for the blocker below.

## Blocker

- `docs/superpowers/plans/2026-09-19-solve-companion.md:363-378` (Task 1, Step 3, "Header-parse check against a
  fixture") — the fixture hardcodes a **real** LeetCode problem number+slug (`49. Group Anagrams` →
  `problems/leetcode.com/problems/group-anagrams/` → key `0049-group-anagrams`) that the session store keys on
  globally, not by workbench directory (`c.set_current { key = ('%04d-%s'):format(N, slug), ... }` in
  `solve_companion.lua:114-118`). `~/projects/solve/problems/` already has `0049-group-anagrams.py` archived, so this
  is a problem the user has solved before and could plausibly revisit (spaced review — `ROADMAP.md` explicitly names
  related problems). The step's own comment says the fixture "never touches the real one," which is true only of the
  `/tmp` workbench dir — it's false of the data store: the buffer created is literally named
  `solve-companion://0049-group-anagrams`, and the cleanup one line later
  (`rm -f ".../solve/0049-group-anagrams.md"`) unconditionally deletes whatever pane mirror sits at that path. If a
  real coaching session for problem 49 exists when this verification is (re-)run — e.g. next time someone touches
  `solve_companion.lua` and reruns the round's own checks — its transcript is silently destroyed; `sessions.json`'s
  `session_id`/`hint` entry survives (untouched by `Solve toggle`) but the pane content is gone. Right now
  `stdpath('data')/solve/` doesn't exist yet (feature unbuilt), so no damage today, but the step is unsafe to leave
  in the plan as the permanent regression-check for this file.
  **Fix:** pick an obviously-fake fixture number/slug that can't collide with a real problem, e.g.
  `9999. Fixture Problem [Easy]` / `.../problems/fixture-problem/` → key `9999-fixture-problem`, and scope the
  cleanup to that key.

## Should-fix

- `docs/superpowers/plans/2026-09-19-companion-engine.md:96-98` — `companion.lua`'s internal `notify()` prefixes
  every engine-originated message with `spec.name` (the *data-dir* name per the spec table, `docs/superpowers/specs/
  2026-09-19-solve-companion-design.md:30`), not a companion label. For `pr_companion.lua` (`name = 'pr_review'`,
  set at `companion-engine.md:542`), this silently changes user-visible text versus the current
  `lua/pr_companion.lua`:
  - `M.toggle` (→ `c.toggle`, `companion-engine.md:389-391`) says `"pr_review: open a PR with :PrReview first"`
    instead of today's `"pr_companion: open a PR with :PrReview first"` (current `lua/pr_companion.lua:328`).
  - `M.ask`'s busy path (→ `c.request`'s guard, `companion-engine.md:409-410`) says
    `"pr_review: busy with the previous request"` instead of today's
    `"pr_companion: busy with the previous question"` (current `lua/pr_companion.lua:423`).
  - `M.chat` (`companion-engine.md:649`, `M.chat = c.chat` with no wrapper) loses the specific
    `"...run :PrCompanion to bootstrap"` guidance entirely, becoming the generic
    `"pr_review: no session; bootstrap first"` (`companion-engine.md:426-429`) vs. today's
    `"pr_companion: no session for this PR; run :PrCompanion to bootstrap"` (current `lua/pr_companion.lua:445-447`).
  - `M.reset` (`companion-engine.md:651`, `M.reset = c.reset`) says `"pr_review: session cleared"`
    (`companion-engine.md:446`) instead of today's `"pr_companion: session cleared"`
    (current `lua/pr_companion.lua:464`).
  This directly contradicts the round-1 plan's own constraint, `companion-engine.md:22`: *"No behaviour change for
  the PR companion except: buffer name... and sessions are keyed by..."* — the notify-prefix/wording change is a
  third, undeclared behaviour change, and it's inconsistent even within the new `pr_companion.lua` itself (the
  hand-written `M.bootstrap`/`M.ask` guards keep the `pr_companion:` prefix via their own hardcoded `vim.notify`
  calls; only the delegated-straight-to-engine paths drift). The same split prefixing shows up in
  `solve_companion.lua`, whose own `notify()` (`docs/superpowers/plans/2026-09-19-solve-companion.md:86-88`) says
  `"solve_companion: ..."` while the engine's internal notifies for the same commands say `"solve: ..."`
  (`spec.name = 'solve'` at `solve-companion.md:56`) — e.g. a stale-session race in `M.chat`
  (`solve-companion.md:302-306`) would surface `"solve: no session; bootstrap first"` next to every other message
  in the same file being prefixed `"solve_companion: "`.
  **Fix:** give `spec` a separate `label` (or reuse a fixed string) for user-facing notify prefixes, independent of
  `spec.name` (the data-dir name), and set it to `'pr_companion'` / `'solve_companion'` respectively; or have the
  engine take a `notify` function from the domain layer instead of building its own.

- `docs/superpowers/plans/2026-09-19-solve-companion.md:507-513` (Task 3, Step 3, `lua/plugins/README.md`) — the
  sentence this step appends describes `<leader>rd` and an `lc.py`-aware `pyrun.lua` (`cases.txt` top pane,
  `python3 lc.py test`) as already existing ("the same ftplugin adds `<leader>rd`..."). At HEAD, neither exists:
  `after/ftplugin/python.lua` only binds `<leader>rp` (`git show HEAD:after/ftplugin/python.lua`), and
  `lua/pyrun.lua` only runs `python3 <file> < input.txt`. That `lc.py`/`<leader>rd` support currently exists **only**
  as uncommitted, in-flight working-tree changes to `after/ftplugin/python.lua` and `lua/pyrun.lua` — separate from
  this plan and, per the ask, not present on the clean HEAD checkout the builder runs on. Neither this plan's Task 1
  (`solve_companion.lua`) nor Task 2 (keymaps) adds `<leader>rd` or touches `pyrun.lua` — Task 2 only adds the
  `<leader>a*` coach keymaps. So after this round lands (on a clean HEAD branch), `lua/plugins/README.md` will
  assert a keymap and a `pyrun.lua` behaviour that don't exist in the tree, until the other in-flight work merges
  separately. Functionally harmless (the anchor match itself still succeeds — it's a prefix match, not exact-text —
  so the step is mechanically executable) but produces incorrect documentation the moment it's committed.
  **Fix:** either drop the `<leader>rd`/`cases.txt` clause from this step's sentence (document only what this round
  ships — the `<leader>a*` keymaps) and let the in-flight `pyrun.lua` work add its own README sentence when it
  lands, or make this round depend on that work having merged first.

## Nit

- `docs/superpowers/plans/2026-09-19-solve-companion.md:72-76` (`REVIEW_PROMPT`) — wording drifts from the spec's
  verbatim prompt (`docs/superpowers/specs/2026-09-19-solve-companion-design.md:148`): the plan prepends "Review my
  attempt." and rephrases "if all pass" as "if every case passes." Semantically equivalent, but since the spec
  writes out `:SolveHint`/`:SolveDebrief` prompts that the plan matches verbatim, this one line is the odd one out.
  Not worth blocking on.

## No problems found

- `lua/companion.lua`'s engine body (pane management, `append`/`region`/`set_lines`, `stream_into`, `claude()`,
  sessions store, `uuid()`) is a faithful line-for-line lift of the current `lua/pr_companion.lua` — row/index math,
  `gsub`/`match` chains (Lua truncates a chained method-call's multiple returns to one automatically, same as the
  existing `key()` pattern), and the streaming/busy/timeout logic are unchanged. No 0/1-based off-by-ones, no nil
  indexing, no `vim.system(...):wait()` misuse found.
- `c.<fn>` surface used by `pr_companion.lua` and `solve_companion.lua` is a strict subset of what `companion.lua`
  exports; `on_done(result, err, region, entry_row)` is called consistently at the one call site
  (`c.request`, `companion-engine.md:408-424`) and consumed correctly by both domain layers' bootstrap handlers
  (matching 0-based row math against `c.set_lines`).
  in `claude_args`, the new engine only appends `--allowedTools`/`--disallowedTools` when the corresponding list is
  non-empty (`companion-engine.md:158-165`), unlike the old unconditional pair — this is a deliberate, correct fix
  for `solve_companion`'s empty `denied = {}` (an empty `--disallowedTools` flag with nothing after it could
  otherwise swallow the next CLI arg); not a regression.
- `lua/pr_review.lua:249`'s `offer(pr)` call and `lua/plugins/diffview.lua:56`'s `setup()` call match the new
  `M.offer(p)`/`M.setup()` signatures; the `pr` table from `gh pr view --json id,baseRefName,number,title,body,url`
  has every field both `offer` and `bootstrap_prompt` read.
  `lua/plugins/persistence.lua:16` (round 2, Task 2, Step 2) — anchor text matches HEAD verbatim (confirmed via
  `git show HEAD:lua/plugins/persistence.lua`); no working-tree drift on this file (not in `git status`).
- Round 1's `CLAUDE.md`/`lua/plugins/CLAUDE.md` anchor texts (Task 3) match HEAD verbatim and aren't touched by the
  uncommitted working-tree edits, so no drift risk there. Round 2's `CLAUDE.md` insertion point ("after the
  paragraph that starts with `` `lua/pyrun.lua` ``") is a prefix match, so it still locates correctly despite the
  working tree having appended a sentence to that same paragraph — mechanically fine, only the README finding above
  is a real problem.
- Session-key rename (PR URL → `<owner>_<repo>_<n>`) and buffer-name rename are exactly the two changes the plans
  declare, and are consistent between spec and both plans; `key()`'s no-longer-existing old dual-keying (sessions by
  URL, pane file by `owner_repo_n`) is correctly resolved by unifying on `current.key`.
- Header-parse regex (`^#%s*(%d+)%.%s*(.-)%s*%[(%w+)%]%s*$`), slug extraction, and the `readfile(path, '', 2)` call
  are all correct for the stated `# <N>. <Title> [<Difficulty>]` / `# <url>` format.

# Solve Companion — Design

A Socratic problem-solving coach for the `~/projects/solve` LeetCode workbench, built on the same headless Claude Code
machinery as the PR companion. The shared machinery is extracted into `lua/companion.lua`; `pr_companion.lua` and the new
`solve_companion.lua` become thin domain layers.

## Goals

- One persistent coach session per LeetCode problem, keyed by the problem in `solve.py`.
- The coach never hands over the solution: it hints in increasing strength, reviews an attempt by pointing (not fixing),
  and only explains the optimal approach in an explicit debrief.
- Zero duplication of the streaming pane / claude runner between the two companions.

## Non-goals

- No automatic offer when `solve.py` is opened (the PR companion's `offer` popup); everything is command-driven.
- No auto-debrief on green tests; `:SolveDebrief` is on demand.
- No migration of existing PR sessions (see "Session key" below).

## 1. Shared engine — `lua/companion.lua` (new)

`require('companion').new(spec)` returns an instance `c`. Everything domain-agnostic in today's `pr_companion.lua` moves
here verbatim: `claude_args`, `describe_tool`, the stream-json parser, timeout handling, `uuid`, pane buffer/window
management, `append`/`region`/`stream_into`, the sessions store, `persist`, `touched`, `scroll_if_visible`.

### spec

| field | type | meaning |
|---|---|---|
| `name` | string | data dir `stdpath('data')/<name>/` holding `sessions.json` and `<key>.md` pane mirrors |
| `scheme` | string | buffer-name prefix: `<scheme>://<key>` |
| `tools` | string | `--tools` value, e.g. `'Read,Grep,Glob,Bash'` |
| `allowed` | string[] | `--allowedTools` entries |
| `denied` | string[] | `--disallowedTools` entries (may be empty) |
| `pane_width` | integer? | vsplit width, default 60 |
| `not_ready` | string | message for "no current target" notifications, e.g. `'open a PR with :PrReview first'` |

Model/effort/timeout stay fixed (`--model opus --effort high`, 10 min) as today.

### current

`c.set_current { key, title, root }` — the domain layer decides what "current" is.

- `key` — file-safe id (`[%w%-_]+`): the session key, the mirror file name and the buffer name suffix.
- `title` — pane header on first build (`# <title>`).
- `root` — cwd for `claude` and toggleterm.

`c.current()` returns the table (or nil).

### session store

- `c.session()` → table or nil for `current.key`.
- `c.save_session(tbl)` — shallow-merge `tbl` into the session and persist.
- `c.clear_session()` — drop the entry and persist.
- `c.reset()` — `clear_session` + delete mirror file + delete pane buffer + notify `'<name>: session cleared'`.

Sessions are keyed by `current.key` (the PR store is keyed by full URL today; those entries go stale and each open
PR gets one re-bootstrap — accepted).

### pane

`c.open_pane()`, `c.toggle()`, `c.pane_buf()`, `c.find_pane_buf()`, `c.pane_win()`, `c.append(lines) → row`,
`c.region(row, len)` — behaviour unchanged: rebuild-from-mirror on unload, `TextChanged` fired by hand, scroll only if
visible, `q` closes, every write persists.

### requests

```
c.request {
  entry   = string[],   -- appended to the pane; its LAST line is the placeholder the region replaces
  label   = string,     -- status label while working, e.g. 'thinking…'
  extra   = string[],   -- extra claude args: { '--session-id', id } or { '--resume', id }
  prompt  = string,     -- stdin
  on_done = function(result, err, region, entry_row)?  -- optional
}
```

Opens the pane, appends `entry`, makes a region over its last line, streams (2 s clock, last 5 activity lines,
partial text), then calls `on_done`. Without `on_done`: renders `result` (+ trailing blank) or `**error:** <err>`.
Refuses with a notify when `c.busy()`.

`c.uuid()`, `c.busy()`, `c.chat()` (toggleterm float running `claude --resume <session_id>` in `current.root`).

### errors

Unchanged: missing `claude` binary, timeout kill, `result.is_error`, stderr on non-zero exit → `err` string.

## 2. `lua/pr_companion.lua` — thin domain layer

Keeps: `TOOLS`/`ALLOWED`/`DENIED` (into the spec, `name = 'pr_review'`, `scheme = 'pr-companion'`),
`bootstrap_prompt`, `snippet` (diffview side detection), `bootstrap`, `ask`, `offer`, `setup`
(`:PrCompanion`, `:PrAsk`, `:PrChat`). `bootstrap` keeps its failure behaviour (removes the whole `## Summary` entry)
via `on_done`. `offer` computes `key` from the URL (`owner_repo_N`) and calls `c.set_current`.

Only observable change: the buffer name becomes `pr-companion://<owner_repo_N>`.

## 3. `lua/solve_companion.lua` — the coach

### context

`refresh()` runs at the start of every command:

1. `dir` = directory of the current buffer's file (fallback `getcwd()`).
2. Require `dir/lc.py` and `dir/solve.py`; otherwise notify `'solve_companion: not an lc.py workbench'` and return nil.
3. Parse `solve.py` line 1 `# <N>. <Title> [<Difficulty>]` and line 2 `# <url>`; otherwise notify
   `'solve_companion: no problem header in solve.py — run make start / make next'` and return nil.
4. `slug` = last path segment of the URL. `key = ('%04d-%s'):format(N, slug)` (same naming as `problems/`).
5. `c.set_current { key, title = '<N>. <Title> [<Difficulty>]', root = dir }` and remember `number, name, difficulty, url`.

`spec`: `name = 'solve'`, `scheme = 'solve-companion'`, `tools = 'Read,Grep,Glob,Bash'`,
`allowed = { 'Bash(python3 lc.py test*)', 'Bash(make test*)' }`, `denied = {}`,
`not_ready = 'open solve.py in an lc.py workbench first'`.

Session table: `{ session_id = uuid, hint = 0 }`.

### bootstrap prompt

```
You are a Socratic coach for LeetCode problem <N>. <Title> [<Difficulty>] (<url>).
I am solving it in `solve.py` in this directory; `cases.txt` holds my test cases and `python3 lc.py test` runs them.

Rules — these override anything I ask later:
- Never write solution code, or pseudocode that is the solution in disguise.
- Never name the optimal technique unprompted. You may only do so through the hint ladder (level 2 and up) or when I
  explicitly ask for a debrief.
- Before hinting, ask what I have tried, unless I just told you.
- When reviewing my code, point at the failing case and the responsible line or the gap in reasoning; do not fix it.
- Keep answers short. Prefer a question back over an explanation.
You have read-only access to this directory plus `python3 lc.py test`. You cannot edit files.

## Problem
<problem.md verbatim>

## First task
Restate the problem in at most 3 lines, list the constraints that matter and what they rule out
(e.g. n ≤ 10^4 makes O(n^2) borderline), and end with one opening question. Do not name any approach.
```

The pane entry for bootstrap is `## Coach`, `''`, `_bootstrapping…_`; failure removes the whole entry (as PR).

### commands

| command | behaviour |
|---|---|
| `:Solve [bootstrap\|toggle\|chat\|reset]` | as `:PrCompanion`; bare form bootstraps when no session, else toggles the pane |
| `:SolveHint` | `hint = session.hint + 1`. If `hint > 4`: notify `'solve_companion: hint ladder exhausted — ask a specific question or :SolveDebrief'`, no request. Else entry `### 💡 Hint <hint>/4`, `''`, `_thinking…_`; prompt: `Hint <hint> of 4. Level <hint> = <level text>. Stay at this level; nothing stronger.` Level texts: 1 "an observation or reframing of the problem", 2 "which data structure or pattern family to think about", 3 "the key insight that makes it work", 4 "a prose sketch of the algorithm, no code". On success `save_session { hint = hint }` (only after the answer arrives so a failed request does not burn a rung). |
| `:SolveAsk` (range) | as `:PrAsk`: visual → `File: solve.py  lines a–b` + fenced `python` snippet (buffer name relative to `root`, side note omitted), then `vim.ui.input 'Ask coach: '`. Entry `### ❯ <q>`. |
| `:SolveReview` | entry `### 🔍 Review`, `''`, `_reviewing…_`; prompt: `Read solve.py and cases.txt, then run python3 lc.py test. Point at the first failing case and the line responsible, or the gap in my reasoning if all pass but the approach is wrong or too slow for the constraints. Do not rewrite my code; at most one question or nudge.` |
| `:SolveDebrief` | Lua runs `python3 lc.py test` in `root` (`vim.system … :wait()`). If exit ≠ 0: `vim.ui.select { 'Yes', 'No' }` with prompt `'Tests are failing — debrief anyway? (reveals the solution)'`; No → return. Entry `## 🎓 Debrief`, `''`, `_debriefing…_`; prompt: `Debrief. I am done with this problem. Explain the optimal approach and its time/space complexity, compare it with my solve.py (read it), say what to remember for similar problems, and name related problems from ROADMAP.md. Code is allowed now.` |
| `:SolveChat` | `c.chat()` |

All of `SolveHint/Ask/Review/Debrief` require a session; otherwise notify `'solve_companion: no session — run :Solve first'`.

### keymaps

Buffer-local, in `after/ftplugin/python.lua`, only when `lc.py` exists next to the file. The `<leader>a` prefix is unused.

| key | mode | command |
|---|---|---|
| `<leader>aa` | n, x | `:SolveAsk` |
| `<leader>ah` | n | `:SolveHint` |
| `<leader>ar` | n | `:SolveReview` |
| `<leader>ad` | n | `:SolveDebrief` |
| `<leader>at` | n | `:Solve toggle` |
| `<leader>ac` | n | `:SolveChat` |

`require('solve_companion').setup()` is called from the ftplugin; it is idempotent (commands are re-created with the
same definitions).

## 4. Session persistence hook

`lua/plugins/persistence.lua` wipes `pr-*://` scratch buffers before saving a session; add `^solve%-companion://`.

## 5. Docs

- `CLAUDE.md` shared utilities: add `lua/companion.lua` and `lua/solve_companion.lua`; reword the `pr_companion` line.
- `lua/plugins/CLAUDE.md`: in the AI companion section note the split; add a "Solve companion" subsection (commands,
  keymaps, tools, prompts, storage under `stdpath('data')/solve/`).
- `~/projects/solve/README.md`: keymaps under the neovim line (separate repo, separate commit).

## 6. Verification

No Lua test harness exists. Per round:

- `stylua --check .`
- `nvim --headless -c "lua require'companion'; require'pr_companion'; require'solve_companion'" -c q` exits 0.
- Round 1 regression: `:PrReview` on a real PR — bootstrap streams into the pane, `:PrAsk` on a range answers,
  `:PrCompanion reset` clears.
- Round 2: in `~/projects/solve` with the current problem — `:Solve` bootstraps, `:SolveHint` twice yields hints 1 and
  2 and `sessions.json` shows `hint = 2`, `:SolveReview` on the failing `groupAnagrams` names the failing case,
  `:SolveDebrief` asks the failing-tests confirmation, `:SolveChat` opens the terminal, `:Solve reset` clears.

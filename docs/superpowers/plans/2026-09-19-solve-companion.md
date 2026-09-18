# Solve Companion — Implementation Plan (relay round 2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Relay builder notes.** This plan is one headless round: you have no memory of earlier rounds and nobody will answer
> a dialog. Everything you need is in this file and the spec. Execute the steps literally. If a step is impossible as
> written or contradicts the code you find, **halt and report which step and why** — do not improvise a different
> design. Touch only the files each task names. Do not `git push`.
>
> **Precondition (check first):** `lua/companion.lua` exists and exports `new(spec)` returning an instance with
> `set_current`, `current`, `busy`, `uuid`, `session`, `save_session`, `reset`, `toggle`, `request`, `set_lines`,
> `chat` (round 1 delivered it). Run `grep -c "function c\." lua/companion.lua` — expected ≥ 15. If the file is missing,
> halt and report.

**Goal:** A Socratic LeetCode coach for the `lc.py` workbench (`~/projects/solve`): one Claude Code session per problem, a 4-rung hint ladder, attempt review, on-demand debrief, and a terminal chat — driven by `:Solve*` commands and `<leader>a*` keymaps in `solve.py`.

**Architecture:** `lua/solve_companion.lua` is a thin domain layer on `lua/companion.lua` (the same engine the PR companion uses). It re-detects the current problem from `solve.py`'s header on every command, so `make next` switches sessions implicitly. Keymaps are buffer-local in `after/ftplugin/python.lua`, only when `lc.py` sits next to the file.

**Tech Stack:** Neovim 0.11 Lua, `claude` CLI, toggleterm, stylua.

**Spec:** `docs/superpowers/specs/2026-09-19-solve-companion-design.md` (sections 3–6 are this round).

## Global Constraints

- All Lua formatted with stylua: `.stylua.toml` — 160 columns, 2-space indent, single quotes, no call parentheses. Run `stylua .` before every commit; `stylua --check .` must pass.
- Coach tools: `--tools Read,Grep,Glob,Bash`, `--allowedTools 'Bash(python3 lc.py test*)' 'Bash(make test*)'`, no denied list. Read-only otherwise (enforced by the engine's `--restricted`).
- Session key: `('%04d-%s'):format(N, slug)`, e.g. `0049-group-anagrams`. Data under `stdpath('data')/solve/`. Buffer `solve-companion://<key>`.
- Session table `{ session_id, hint }`; `hint` advances only after a hint request succeeds.
- Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- No Lua test harness exists; verification is `stylua --check .` plus headless Neovim loads with asserts.

---

### Task 1: `lua/solve_companion.lua`

**Files:**
- Create: `lua/solve_companion.lua`
- Read for reference: `lua/companion.lua`, `lua/pr_companion.lua`

**Interfaces:**
- Consumes from `lua/companion.lua`: `require('companion').new(spec) → c`; `c.set_current { key, title, root }`; `c.session()`; `c.save_session(tbl)`; `c.busy()`; `c.uuid()`; `c.request { entry, label, extra, prompt, on_done? }` where `on_done(result, err, region, entry_row)` and `region.render(lines)`, `region.row`, `region.len`; `c.set_lines(from, to, lines)`; `c.toggle()`; `c.chat()`; `c.reset()`.
- Produces: `M.bootstrap()`, `M.hint()`, `M.ask(opts)`, `M.review()`, `M.debrief()`, `M.toggle()`, `M.chat()`, `M.reset()`, `M.setup()`; user commands `:Solve [bootstrap|toggle|chat|reset]`, `:SolveHint`, `:SolveAsk` (range), `:SolveReview`, `:SolveDebrief`, `:SolveChat`.

- [ ] **Step 1: Write the file**

Create `lua/solve_companion.lua` with exactly this content:

```lua
-- Socratic coach for the lc.py LeetCode workbench (~/projects/solve): one headless Claude Code session per problem
-- (parsed from solve.py's `# N. Title [Difficulty]` header), a 4-rung hint ladder, attempt review and an on-demand
-- debrief. The engine (claude runner, streaming pane, sessions) is lua/companion.lua.
-- Sessions live in stdpath('data')/solve/sessions.json keyed by NNNN-slug; each pane is mirrored to <key>.md next to it.
local M = {}

local c = require('companion').new {
  name = 'solve',
  scheme = 'solve-companion',
  tools = 'Read,Grep,Glob,Bash',
  allowed = { 'Bash(python3 lc.py test*)', 'Bash(make test*)' },
  denied = {},
  not_ready = 'open solve.py in an lc.py workbench first',
}

-- Hint ladder, weakest first. The coach is told the rung and must not go stronger.
local HINTS = {
  'an observation or reframing of the problem',
  'which data structure or pattern family to think about',
  'the key insight that makes it work',
  'a prose sketch of the algorithm, no code',
}

local REVIEW_PROMPT = table.concat({
  'Review my attempt. Read solve.py and cases.txt, then run `python3 lc.py test`.',
  'Point at the first failing case and the line responsible, or — if every case passes — at the gap in my reasoning',
  'if the approach is wrong or too slow for the constraints. Do not rewrite my code; at most one question or nudge.',
}, ' ')

local DEBRIEF_PROMPT = table.concat({
  'Debrief. I am done with this problem. Explain the optimal approach and its time/space complexity,',
  'compare it with my solve.py (read it), say what to remember for similar problems,',
  'and name related problems from ROADMAP.md. Code is allowed now.',
}, ' ')

local problem -- { number, name, difficulty, url, dir }

local function notify(msg, level)
  vim.notify('solve_companion: ' .. msg, level or vim.log.levels.INFO)
end

-- Re-detect the problem from the solve.py next to the current buffer (or the last known dir when the current buffer
-- is the pane or another scratch buffer). Returns true when `problem` and the engine's current target are set.
local function refresh()
  local file = vim.api.nvim_buf_get_name(0)
  local dir
  if file == '' or vim.bo.buftype ~= '' then
    dir = problem and problem.dir or vim.fn.getcwd()
  else
    dir = vim.fn.fnamemodify(file, ':p:h')
  end
  local solve = vim.fs.joinpath(dir, 'solve.py')
  if vim.fn.filereadable(vim.fs.joinpath(dir, 'lc.py')) == 0 or vim.fn.filereadable(solve) == 0 then
    notify('not an lc.py workbench', vim.log.levels.WARN)
    return false
  end
  local lines = vim.fn.readfile(solve, '', 2)
  local number, name, difficulty = (lines[1] or ''):match '^#%s*(%d+)%.%s*(.-)%s*%[(%w+)%]%s*$'
  local url = (lines[2] or ''):match '^#%s*(https?://%S+)'
  if not number or not url then
    notify('no problem header in solve.py — run make start / make next', vim.log.levels.WARN)
    return false
  end
  local slug = url:gsub('/+$', ''):match '([^/]+)$'
  problem = { number = tonumber(number), name = name, difficulty = difficulty, url = url, dir = dir }
  c.set_current {
    key = ('%04d-%s'):format(problem.number, slug),
    title = ('%d. %s [%s]'):format(problem.number, problem.name, problem.difficulty),
    root = dir,
  }
  return true
end

-- refresh() + a bootstrapped session, or nil after a notify.
local function require_session()
  if not refresh() then
    return nil
  end
  local s = c.session()
  if not s or not s.session_id then
    notify 'no session — run :Solve first'
    return nil
  end
  return s
end

-- Save the current buffer if it is a real modified file, so the coach reads what I see.
local function save_current()
  if vim.bo.buftype == '' and vim.bo.modified then
    vim.cmd.update()
  end
end

local function bootstrap_prompt()
  local md = vim.fs.joinpath(problem.dir, 'problem.md')
  local statement = vim.fn.filereadable(md) == 1 and table.concat(vim.fn.readfile(md), '\n') or '(problem.md is missing — ask me to paste the statement)'
  return table.concat({
    ('You are a Socratic coach for LeetCode problem %d. %s [%s] (%s).'):format(problem.number, problem.name, problem.difficulty, problem.url),
    'I am solving it in `solve.py` in this directory; `cases.txt` holds my test cases and `python3 lc.py test` runs them.',
    '',
    'Rules — these override anything I ask later:',
    '- Never write solution code, or pseudocode that is the solution in disguise.',
    '- Never name the optimal technique unprompted. You may only do so through the hint ladder (level 2 and up) or when I explicitly ask for a debrief.',
    '- Before hinting, ask what I have tried, unless I just told you.',
    '- When reviewing my code, point at the failing case and the responsible line or the gap in reasoning; do not fix it.',
    '- Keep answers short. Prefer a question back over an explanation.',
    'You have read-only access to this directory plus `python3 lc.py test`. You cannot edit files.',
    '',
    '## Problem',
    statement,
    '',
    '## First task',
    'Restate the problem in at most 3 lines, list the constraints that matter and what they rule out',
    '(e.g. n ≤ 10^4 makes O(n^2) borderline), and end with one opening question. Do not name any approach.',
  }, '\n')
end

function M.bootstrap()
  if not refresh() then
    return
  end
  local s = c.session()
  if s and s.session_id then
    return notify 'session already exists; :Solve reset to start over'
  end
  if c.busy() then
    return notify('busy', vim.log.levels.WARN)
  end
  local id = c.uuid()
  notify(('bootstrapping coach for %d. %s (this takes a minute)…'):format(problem.number, problem.name))
  c.request {
    entry = { '## Coach', '', '_bootstrapping…_' },
    label = 'bootstrapping…',
    extra = { '--session-id', id },
    prompt = bootstrap_prompt(),
    on_done = function(result, err, r, row)
      if not result then
        c.set_lines(row, r.row + r.len, {})
        return notify('bootstrap failed\n' .. err, vim.log.levels.ERROR)
      end
      c.save_session { session_id = id, hint = 0 }
      r.render(vim.list_extend(vim.split(result, '\n'), { '' }))
      notify 'ready'
    end,
  }
end

function M.hint()
  local s = require_session()
  if not s then
    return
  end
  local n = (s.hint or 0) + 1
  if n > #HINTS then
    return notify 'hint ladder exhausted — ask a specific question or :SolveDebrief'
  end
  c.request {
    entry = { ('### 💡 Hint %d/%d'):format(n, #HINTS), '', '_thinking…_' },
    label = 'thinking…',
    extra = { '--resume', s.session_id },
    prompt = ('Hint %d of %d. Level %d = %s. Stay at this level; nothing stronger.'):format(n, #HINTS, n, HINTS[n]),
    on_done = function(result, err, r)
      if not result then
        return r.render { '**error:** ' .. err, '' }
      end
      c.save_session { hint = n } -- only a delivered hint burns a rung
      r.render(vim.list_extend(vim.split(result, '\n'), { '' }))
    end,
  }
end

-- Snippet from buffer `buf` lines a..b: header line + fenced code, path relative to the workbench dir.
local function snippet(buf, a, b)
  local name = vim.api.nvim_buf_get_name(buf)
  local path = vim.fs.relpath(problem.dir, name) or vim.fn.fnamemodify(name, ':t')
  local body = { ('File: %s  lines %d–%d'):format(path, a, b), '```' .. vim.bo[buf].filetype }
  vim.list_extend(body, vim.api.nvim_buf_get_lines(buf, a - 1, b, false))
  table.insert(body, '```')
  return body
end

function M.ask(opts)
  local s = require_session()
  if not s then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local code = opts.range > 0 and vim.bo[buf].buftype == '' and snippet(buf, opts.line1, opts.line2) or nil
  vim.ui.input({ prompt = 'Ask coach: ' }, function(q)
    if not q or q:match '^%s*$' then
      return
    end
    local entry = { '### ❯ ' .. q, '' }
    if code then
      vim.list_extend(entry, code)
      table.insert(entry, '')
    end
    table.insert(entry, '_thinking…_')
    c.request {
      entry = entry,
      label = 'thinking…',
      extra = { '--resume', s.session_id },
      prompt = code and table.concat(code, '\n') .. '\n\nQuestion: ' .. q or q,
    }
  end)
end

function M.review()
  local s = require_session()
  if not s then
    return
  end
  save_current()
  c.request {
    entry = { '### 🔍 Review', '', '_reviewing…_' },
    label = 'reviewing…',
    extra = { '--resume', s.session_id },
    prompt = REVIEW_PROMPT,
  }
end

-- Debrief reveals the solution, so when the tests still fail ask first.
function M.debrief()
  local s = require_session()
  if not s then
    return
  end
  save_current()
  local function go()
    c.request {
      entry = { '## 🎓 Debrief', '', '_debriefing…_' },
      label = 'debriefing…',
      extra = { '--resume', s.session_id },
      prompt = DEBRIEF_PROMPT,
    }
  end
  local res = vim.system({ 'python3', 'lc.py', 'test' }, { cwd = problem.dir, text = true }):wait(60000)
  if res.code == 0 then
    return go()
  end
  vim.ui.select({ 'Yes', 'No' }, { prompt = 'Tests are failing — debrief anyway? (reveals the solution)' }, function(choice)
    if choice == 'Yes' then
      go()
    end
  end)
end

function M.toggle()
  if refresh() then
    c.toggle()
  end
end

function M.chat()
  if require_session() then
    c.chat()
  end
end

function M.reset()
  if refresh() then
    c.reset()
  end
end

function M.setup()
  vim.api.nvim_create_user_command('Solve', function(opts)
    local sub = opts.args
    if sub == 'bootstrap' then
      M.bootstrap()
    elseif sub == 'toggle' then
      M.toggle()
    elseif sub == 'chat' then
      M.chat()
    elseif sub == 'reset' then
      M.reset()
    elseif sub == '' and refresh() then
      local s = c.session()
      if s and s.session_id then
        c.toggle()
      else
        M.bootstrap()
      end
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'bootstrap', 'toggle', 'chat', 'reset' }
    end,
    desc = 'LeetCode coach (bootstrap | toggle | chat | reset)',
  })
  vim.api.nvim_create_user_command('SolveHint', M.hint, { desc = 'Next hint on the ladder (1 observation … 4 algorithm sketch)' })
  vim.api.nvim_create_user_command('SolveAsk', M.ask, { range = true, desc = 'Ask the coach about the selected lines' })
  vim.api.nvim_create_user_command('SolveReview', M.review, { desc = 'Coach reviews solve.py against cases.txt without fixing it' })
  vim.api.nvim_create_user_command('SolveDebrief', M.debrief, { desc = 'Post-solve debrief: optimal approach, complexity, takeaways' })
  vim.api.nvim_create_user_command('SolveChat', M.chat, { desc = 'Open the coach session in a terminal' })
end

return M
```

- [ ] **Step 2: Format and load-check**

Run: `stylua . && stylua --check .`
Expected: exit 0.

Run:

```bash
nvim --headless -c "lua require('solve_companion').setup(); for _, n in ipairs { 'Solve', 'SolveHint', 'SolveAsk', 'SolveReview', 'SolveDebrief', 'SolveChat' } do assert(vim.fn.exists(':' .. n) == 2, n) end; print('ok')" -c q
```

Expected: prints `ok`, exit 0.

- [ ] **Step 3: Header-parse check against a fixture**

Run (creates a throwaway workbench in `/tmp`, never touches the real one):

```bash
d=$(mktemp -d) && touch "$d/lc.py" && printf '# 49. Group Anagrams [Medium]\n# https://leetcode.com/problems/group-anagrams/\n' > "$d/solve.py" && \
nvim --headless "$d/solve.py" -c "lua require('solve_companion').setup(); vim.cmd('Solve toggle'); local name = vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()); local found = false; for _, b in ipairs(vim.api.nvim_list_bufs()) do if vim.api.nvim_buf_get_name(b) == 'solve-companion://0049-group-anagrams' then found = true; assert(vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == '# 49. Group Anagrams [Medium]') end end; assert(found, 'pane buffer not found'); print('ok')" -c 'qa!'; rm -rf "$d"
```

Expected: prints `ok`, exit 0. (`Solve toggle` with no session still opens the pane; that is the same as `:PrCompanion toggle`.)

Then remove the fixture's leftovers from the data dir so the real workbench starts clean:

```bash
rm -f "$(nvim --headless -c "lua io.write(vim.fn.stdpath('data'))" -c q 2>/dev/null)/solve/0049-group-anagrams.md"
```

- [ ] **Step 4: Commit**

```bash
git add lua/solve_companion.lua
git commit -m "feat: Socratic LeetCode coach for the lc.py workbench

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Keymaps and session hygiene

**Files:**
- Modify: `after/ftplugin/python.lua` (append at end of file)
- Modify: `lua/plugins/persistence.lua:16` (the `name:find` condition)

**Interfaces:**
- Consumes: `require('solve_companion').setup()` and the `:Solve*` commands from Task 1.

- [ ] **Step 1: Keymaps**

Append to the end of `after/ftplugin/python.lua`:

```lua

-- lc.py workbench: Socratic coach (lua/solve_companion.lua). Only where lc.py sits next to the file; <leader>a is free.
if vim.fn.filereadable(vim.fn.expand '%:p:h' .. '/lc.py') == 1 then
  require('solve_companion').setup()
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = true, silent = true, desc = desc })
  end
  map({ 'n', 'x' }, '<leader>aa', ':SolveAsk<CR>', 'Co[a]ch: [a]sk about selection')
  map('n', '<leader>ah', ':SolveHint<CR>', 'Co[a]ch: next [h]int')
  map('n', '<leader>ar', ':SolveReview<CR>', 'Co[a]ch: [r]eview my attempt')
  map('n', '<leader>ad', ':SolveDebrief<CR>', 'Co[a]ch: [d]ebrief (reveals solution)')
  map('n', '<leader>at', ':Solve toggle<CR>', 'Co[a]ch: [t]oggle pane')
  map('n', '<leader>ac', ':SolveChat<CR>', 'Co[a]ch: terminal [c]hat')
end
```

- [ ] **Step 2: Persistence wipe list**

In `lua/plugins/persistence.lua`, the line

```lua
    if name:find '^diffview://' or name:find '^pr%-companion://' or name:find '^pr%-merge://' or name:find '^pr%-review%-summary://' then
```

becomes

```lua
    if
      name:find '^diffview://'
      or name:find '^pr%-companion://'
      or name:find '^pr%-merge://'
      or name:find '^pr%-review%-summary://'
      or name:find '^solve%-companion://'
    then
```

(stylua may re-wrap this; accept whatever `stylua .` produces.) Also update the file's first comment line so `diffview:// and pr-*:// buffers are scratch` reads `diffview://, pr-*:// and solve-companion:// buffers are scratch`.

- [ ] **Step 3: Format and check**

Run: `stylua . && stylua --check .`
Expected: exit 0.

Run:

```bash
d=$(mktemp -d) && touch "$d/lc.py" && printf '# 1. Two Sum [Easy]\n# https://leetcode.com/problems/two-sum/\n' > "$d/solve.py" && \
nvim --headless "$d/solve.py" -c "lua assert(vim.fn.maparg('<leader>ah', 'n') ~= '', 'ah'); assert(vim.fn.maparg('<leader>aa', 'x') ~= '', 'aa x'); assert(vim.fn.exists(':SolveHint') == 2); print('ok')" -c 'qa!'; rm -rf "$d"
```

Expected: prints `ok`. (Lazy-loaded plugins may print unrelated notices; only the `ok` and exit code matter.)

Run: `nvim --headless -c "lua require('plugins.persistence')" -c q; echo $?`
Expected: `0`.

- [ ] **Step 4: Commit**

```bash
git add after/ftplugin/python.lua lua/plugins/persistence.lua
git commit -m "feat: <leader>a coach keymaps in the lc.py workbench; keep its pane out of sessions

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Docs

**Files:**
- Modify: `CLAUDE.md` (Shared Utilities section)
- Modify: `lua/plugins/CLAUDE.md` (after the `### AI companion (`lua/pr_companion.lua`)` section, before `## config-local.lua`)
- Modify: `lua/plugins/README.md` (the Terminal paragraph that mentions `after/ftplugin/python.lua`)

- [ ] **Step 1: Root `CLAUDE.md`**

After the paragraph that starts with `` `lua/pyrun.lua` `` in the Shared Utilities section, add (blank line before and after):

```
`lua/solve_companion.lua` — Socratic LeetCode coach for the `lc.py` workbench, on `companion.lua` (`:Solve`, `:SolveHint`, `:SolveAsk`, `:SolveReview`, `:SolveDebrief`, `:SolveChat`; `<leader>a*` in `solve.py`). Session per problem (`NNNN-slug` from `solve.py`'s header) under `stdpath('data')/solve/`.
```

- [ ] **Step 2: `lua/plugins/CLAUDE.md`**

Insert this section immediately before the `## config-local.lua` heading:

```markdown
### Solve companion (`lua/solve_companion.lua`)

A Socratic coach for the `lc.py` LeetCode workbench (`~/projects/solve`), on the same engine as the PR companion. Every command re-reads `solve.py`'s header (`# N. Title [Difficulty]` + URL) so `make next` switches problems implicitly; the session key is `NNNN-slug` (as in `problems/`), data under `stdpath('data')/solve/`, pane `solve-companion://<key>`. Tools: `Read,Grep,Glob` plus `Bash(python3 lc.py test*)` / `Bash(make test*)` only. The bootstrap prompt embeds `problem.md` and forbids solution code, naming the technique unprompted, or fixing code during review.

Keymaps are buffer-local in `after/ftplugin/python.lua`, only when `lc.py` sits next to the file:

- `:Solve [bootstrap|toggle|chat|reset]` / `<leader>at` — bare: bootstrap when there is no session (restates the problem, lists the binding constraints, asks an opening question), else toggle the pane.
- `:SolveHint` / `<leader>ah` — next rung of a 4-step ladder (observation → data structure/pattern → key insight → prose sketch). `hint` is stored in the session and only advances when the answer arrives; past 4 it says so without calling claude.
- `:SolveAsk` / `<leader>aa` (n, x) — question, with the visual selection as a fenced snippet.
- `:SolveReview` / `<leader>ar` — saves the buffer; the coach runs `lc.py test` itself and points at the first failing case and line (or the reasoning gap) without rewriting.
- `:SolveDebrief` / `<leader>ad` — runs `lc.py test` locally first; if it fails, asks "debrief anyway?" since the debrief reveals the solution, complexity, and related roadmap problems.
- `:SolveChat` / `<leader>ac` — toggleterm float on the session.

`persistence.lua` wipes `solve-companion://` buffers before saving a session, like the other scratch panes.
```

- [ ] **Step 3: `lua/plugins/README.md`**

Find the paragraph in the Terminal section that begins with `` `after/ftplugin/python.lua` binds a buffer-local `<leader>rp` ``. Append this sentence to the end of that paragraph:

```
In an `lc.py` workbench dir the top pane is `cases.txt` and the command is `python3 lc.py test`; the same ftplugin adds `<leader>rd` (open `problem.md` in a tab) and the `<leader>a*` coach keymaps from `lua/solve_companion.lua` (see `lua/plugins/CLAUDE.md` → Solve companion).
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md lua/plugins/CLAUDE.md lua/plugins/README.md
git commit -m "docs: document the solve companion

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final verification (run before reporting)

```bash
stylua --check .
nvim --headless -c "lua require('companion'); require('pr_companion').setup(); require('solve_companion').setup(); print('ok')" -c q
git status --short   # must be empty
git log --oneline -3 # the three commits above
```

Report per task: COMPLETED AS WRITTEN / COMPLETED WITH NOTES / BLOCKED, plus the output of the four commands above.
Out of scope for this round (the planner does it): the keymap line in `~/projects/solve/README.md` and the live run
against a real problem.

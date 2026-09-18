# Companion Engine Extraction — Implementation Plan (relay round 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Relay builder notes.** This plan is one headless round: you have no memory of earlier rounds and nobody will answer
> a dialog. Everything you need is in this file and the spec. Execute the steps literally. If a step is impossible as
> written or contradicts the code you find (a function that does not exist, a line range that does not match), **halt
> and report which step and why** — do not improvise a different design. Touch only the files each task names. Do not
> `git push`.

**Goal:** Move the domain-agnostic machinery of `lua/pr_companion.lua` (headless `claude` runner, streaming markdown pane, sessions store) into a reusable `lua/companion.lua` engine, and make `pr_companion.lua` a thin layer on top of it, with no behaviour change.

**Architecture:** `require('companion').new(spec)` returns an instance closing over its own data dir, current target, session table, busy flag and pane. `pr_companion.lua` keeps only the PR-specific parts: tool allow/deny lists, prompts, the diffview-aware snippet builder, `offer`, and the `:PrCompanion`/`:PrAsk`/`:PrChat` commands. Round 2 (a separate plan) builds `solve_companion.lua` on the same engine.

**Tech Stack:** Neovim 0.11 Lua (`vim.system`, `vim.uv`, `vim.ui.*`), `claude` CLI (`-p --output-format stream-json`), toggleterm, render-markdown, stylua.

**Spec:** `docs/superpowers/specs/2026-09-19-solve-companion-design.md` (sections 1 and 2 are this round).

## Global Constraints

- All Lua formatted with stylua: `.stylua.toml` — 160 columns, 2-space indent, single quotes, no call parentheses. Run `stylua .` before every commit; `stylua --check .` must pass.
- No behaviour change for the PR companion except: buffer name becomes `pr-companion://<owner_repo_N>`, sessions are keyed by `<owner_repo_N>` instead of the PR URL (old entries in `sessions.json` simply go stale), and the busy message reads `busy with the previous request`. Every notification keeps the `pr_companion:` prefix (`spec.label`).
- Model/effort/timeout stay `--model opus --effort high`, 10 minutes.
- Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- There is no Lua test harness in this repo. Verification is `stylua --check .` plus a headless Neovim load (`nvim --headless … -c q`).

---

### Task 1: `lua/companion.lua` — the engine

**Files:**
- Create: `lua/companion.lua`
- Read for reference (do not modify yet): `lua/pr_companion.lua`

**Interfaces:**
- Consumes: nothing new.
- Produces (used by Task 2 and by round 2):
  - `require('companion').new(spec) → c` where `spec = { name, label, scheme, tools, allowed, denied, pane_width?, not_ready }`
  - `c.set_current { key, title, root }`, `c.current()`, `c.busy()`, `c.uuid()`
  - `c.session()`, `c.save_session(tbl)`, `c.clear_session()`, `c.reset()`
  - `c.find_pane_buf()`, `c.pane_buf()`, `c.pane_win()`, `c.open_pane()`, `c.toggle()`, `c.append(lines) → row`, `c.region(row, len)`, `c.set_lines(from, to, lines)`
  - `c.request { entry, label, extra, prompt, on_done? }`, `c.chat()`

- [ ] **Step 1: Write the file**

Create `lua/companion.lua` with exactly this content:

```lua
-- Shared engine for the AI companions (pr_companion, solve_companion): one headless Claude Code session per target,
-- streamed into a persistent markdown pane. `new(spec)` returns an instance; the domain layer supplies the target
-- (`set_current`), prompts and user commands.
--
-- Sessions live in stdpath('data')/<spec.name>/sessions.json keyed by current.key; each pane is mirrored to <key>.md
-- next to it. The companion is strictly read-only. `--restricted` ignores settings files (the user's global
-- `defaultMode = auto` would otherwise auto-approve everything) and drops every tool not named in `--tools`; in print
-- mode anything outside `spec.allowed` is denied rather than prompted, and `spec.denied` wins over `spec.allowed`.
local M = {}

local TIMEOUT_MS = 10 * 60 * 1000

-- RFC 4122 v4 from OS randomness (math.random is unseeded in a fresh Neovim and would repeat).
function M.uuid()
  local b = { vim.uv.random(16):byte(1, 16) }
  b[7] = bit.bor(bit.band(b[7], 0x0f), 0x40)
  b[9] = bit.bor(bit.band(b[9], 0x3f), 0x80)
  return ('%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x'):format(unpack(b))
end

-- One-line description of a tool call for the activity log.
local function describe_tool(block)
  local input = block.input or {}
  local what = input.command or input.file_path or input.pattern or input.path or ''
  what = tostring(what):gsub('\n.*', ''):sub(1, 70)
  return ('· %s %s'):format(block.name, what)
end

--- spec = { name, label, scheme, tools, allowed, denied, pane_width?, not_ready }
---  name       data dir under stdpath('data')
---  label      prefix of every notification: '<label>: …'
---  scheme     pane buffer name is `<scheme>://<key>`
---  tools      `--tools` value, e.g. 'Read,Grep,Glob,Bash'
---  allowed    `--allowedTools` entries; denied  `--disallowedTools` entries (either may be empty)
---  pane_width vsplit width (default 60)
---  not_ready  message when a command runs with no current target
function M.new(spec)
  local c = {}
  local pane_width = spec.pane_width or 60
  local data_dir = vim.fs.joinpath(vim.fn.stdpath 'data', spec.name)
  local sessions_file = vim.fs.joinpath(data_dir, 'sessions.json')

  local current -- { key, title, root }
  local busy = false
  local sessions

  c.uuid = M.uuid

  local function notify(msg, level)
    vim.notify(spec.label .. ': ' .. msg, level or vim.log.levels.INFO)
  end

  ---------------------------------------------------------------------------
  -- Current target + sessions
  ---------------------------------------------------------------------------

  function c.set_current(cur)
    current = cur
  end

  function c.current()
    return current
  end

  function c.busy()
    return busy
  end

  local function load_sessions()
    if not sessions then
      local f = io.open(sessions_file)
      local ok, decoded = pcall(vim.json.decode, f and f:read '*a' or '')
      if f then
        f:close()
      end
      sessions = ok and type(decoded) == 'table' and decoded or {}
    end
    return sessions
  end

  local function save_sessions()
    vim.fn.mkdir(data_dir, 'p')
    local f = assert(io.open(sessions_file, 'w'))
    f:write(vim.json.encode(sessions))
    f:close()
  end

  function c.session()
    return current and load_sessions()[current.key] or nil
  end

  -- Shallow-merge `tbl` into the current session and persist.
  function c.save_session(tbl)
    local all = load_sessions()
    all[current.key] = vim.tbl_extend('force', all[current.key] or {}, tbl)
    save_sessions()
  end

  function c.clear_session()
    load_sessions()[current.key] = nil
    save_sessions()
  end

  ---------------------------------------------------------------------------
  -- Headless claude
  ---------------------------------------------------------------------------

  local function claude_args(extra)
    local args = { 'claude', '-p', '--model', 'opus', '--effort', 'high', '--restricted', '--tools', spec.tools }
    vim.list_extend(args, { '--output-format', 'stream-json', '--verbose', '--include-partial-messages' })
    if #spec.allowed > 0 then
      table.insert(args, '--allowedTools')
      vim.list_extend(args, spec.allowed)
    end
    if #spec.denied > 0 then
      table.insert(args, '--disallowedTools')
      vim.list_extend(args, spec.denied)
    end
    return vim.list_extend(args, extra)
  end

  -- Run claude headless with `prompt` on stdin, streaming events. `on_event(live)` is called (on the main loop)
  -- whenever the live state changes: live = { activity = {…}, text = '' }. cb(result_text|nil, err) at the end.
  local function claude(extra, prompt, on_event, cb)
    if vim.fn.executable 'claude' ~= 1 then
      return cb(nil, 'claude CLI not found on PATH')
    end
    busy = true
    local live, pending, result = { activity = {}, text = '' }, '', nil
    local function handle(ev)
      if ev.type == 'assistant' then
        for _, block in ipairs(ev.message and ev.message.content or {}) do
          if block.type == 'tool_use' then
            table.insert(live.activity, describe_tool(block))
          end
        end
      elseif ev.type == 'stream_event' and ev.event then
        local e = ev.event
        if e.type == 'message_start' then
          live.text = ''
        elseif e.type == 'content_block_start' and e.content_block and e.content_block.type == 'thinking' then
          table.insert(live.activity, '· 💭 thinking')
        elseif e.type == 'content_block_delta' and e.delta and e.delta.type == 'text_delta' then
          live.text = live.text .. e.delta.text
        end
      elseif ev.type == 'result' then
        result = ev
      end
    end
    local function on_stdout(_, data)
      if not data then
        return
      end
      pending = pending .. data
      local lines = vim.split(pending, '\n', { plain = true })
      pending = table.remove(lines)
      vim.schedule(function()
        for _, line in ipairs(lines) do
          local ok, ev = pcall(vim.json.decode, line)
          if ok and type(ev) == 'table' then
            handle(ev)
          end
        end
        on_event(live)
      end)
    end
    vim.system(claude_args(extra), { text = true, stdin = prompt, cwd = current.root, timeout = TIMEOUT_MS, stdout = on_stdout }, function(res)
      vim.schedule(function()
        busy = false
        if res.signal ~= 0 and res.code ~= 0 then
          return cb(nil, ('claude gave up after %d minutes (killed)'):format(TIMEOUT_MS / 60000))
        end
        if not result then
          return cb(nil, res.code ~= 0 and (res.stderr ~= '' and res.stderr or 'exit ' .. res.code) or 'claude ended without a result')
        end
        if result.is_error then
          return cb(nil, tostring(result.result))
        end
        cb(result.result or live.text)
      end)
    end)
  end

  ---------------------------------------------------------------------------
  -- Pane
  ---------------------------------------------------------------------------

  local function pane_file()
    return vim.fs.joinpath(data_dir, current.key .. '.md')
  end

  local function buf_name()
    return spec.scheme .. '://' .. current.key
  end

  -- Exact-name lookup: bufnr() takes a pattern, so bufnr('pr-companion://11') would happily return PR 112's pane.
  function c.find_pane_buf()
    local name = buf_name()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf) == name then
        return buf
      end
    end
  end

  -- Programmatic edits to a buffer shown in another window fire no TextChanged, and render-markdown only re-renders on
  -- events it listens to — streamed answers would stay raw markdown until the cursor entered the pane. Fire it by hand.
  local function touched(buf)
    vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf, modeline = false })
  end

  function c.pane_buf()
    local buf = c.find_pane_buf()
    if buf and vim.api.nvim_buf_is_loaded(buf) then
      return buf
    end
    if buf then
      -- :bdelete (e.g. <leader>hb's %bdelete) unloads the pane: still findable by name but empty, with no filetype or
      -- highlighter. Wipe it and rebuild from the mirror file — every write persists, so in-flight regions keep their rows.
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, buf_name())
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'hide'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = 'markdown'
    local f = io.open(pane_file())
    if f then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(f:read '*a', '\n'))
      f:close()
    else
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# ' .. current.title, '' })
    end
    vim.keymap.set('n', 'q', c.toggle, { buffer = buf, desc = 'Close companion pane' })
    return buf
  end

  function c.pane_win()
    local buf = c.find_pane_buf()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        return win
      end
    end
  end

  function c.open_pane()
    local buf = c.pane_buf()
    local win = c.pane_win()
    if not win then
      local prev = vim.api.nvim_get_current_win()
      vim.cmd('botright ' .. pane_width .. 'vsplit')
      win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)
      vim.wo[win].wrap = true
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = 'no'
      vim.api.nvim_set_current_win(prev)
    end
    return buf, win
  end

  local function persist(buf)
    vim.fn.mkdir(data_dir, 'p')
    local f = assert(io.open(pane_file(), 'w'))
    f:write(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    f:close()
  end

  -- Scroll the pane to `line` only if it is currently visible — writing must never force a hidden pane back open.
  local function scroll_if_visible(line)
    local win = c.pane_win()
    if win then
      vim.api.nvim_win_set_cursor(win, { line, 0 })
    end
  end

  -- Append lines to the pane buffer (creating it if needed) and scroll to the bottom if visible. Returns the first row.
  -- Deliberately does NOT open the window: a closed pane keeps receiving stream updates in the background.
  function c.append(lines)
    local buf = c.pane_buf()
    local row = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, row, row, false, lines)
    touched(buf)
    scroll_if_visible(vim.api.nvim_buf_line_count(buf))
    persist(buf)
    return row
  end

  -- Replace pane rows [from, to) with `lines` and persist. Used to drop a failed entry.
  function c.set_lines(from, to, lines)
    local buf = c.pane_buf()
    vim.api.nvim_buf_set_lines(buf, from, to, false, lines)
    touched(buf)
    persist(buf)
  end

  -- A region of the pane owned by one in-flight request: `render(lines)` replaces it in place. Buffer-only, never opens.
  function c.region(row, len)
    local r = { row = row, len = len }
    function r.render(lines)
      local buf = c.pane_buf()
      vim.api.nvim_buf_set_lines(buf, r.row, r.row + r.len, false, lines)
      r.len = #lines
      touched(buf)
      scroll_if_visible(math.min(r.row + r.len, vim.api.nvim_buf_line_count(buf)))
      persist(buf)
    end
    return r
  end

  -- Runs a request into `r`: status line with elapsed time + recent activity + streamed text while working;
  -- the final answer (or an error line) when done. Re-renders on events and every 2 s for the clock.
  local function stream_into(r, label, extra, prompt, on_done)
    local started, timer, live = vim.uv.now(), vim.uv.new_timer(), { activity = {}, text = '' }
    local function draw()
      local secs = math.floor((vim.uv.now() - started) / 1000)
      local lines = { ('_%s (%dm%02ds)_'):format(label, secs / 60, secs % 60) }
      local n = #live.activity
      for i = math.max(1, n - 5), n do
        table.insert(lines, live.activity[i])
      end
      if live.text ~= '' then
        table.insert(lines, '')
        vim.list_extend(lines, vim.split(live.text, '\n'))
      end
      r.render(lines)
    end
    timer:start(2000, 2000, vim.schedule_wrap(draw))
    claude(extra, prompt, function(l)
      live = l
      draw()
    end, function(result, err)
      timer:stop()
      timer:close()
      on_done(result, err)
    end)
  end

  function c.toggle()
    if not current then
      return notify(spec.not_ready)
    end
    local win = c.pane_win()
    if win then
      vim.api.nvim_win_close(win, true)
    else
      c.open_pane()
    end
  end

  ---------------------------------------------------------------------------
  -- Requests
  ---------------------------------------------------------------------------

  -- o = { entry, label, extra, prompt, on_done? }: opens the pane, appends `entry` (its LAST line is the placeholder),
  -- streams into a region over that line, then calls on_done(result, err, region, entry_row). Without on_done the
  -- answer (or `**error:** …`) is rendered in place. Refuses while another request is running.
  function c.request(o)
    if busy then
      return notify('busy with the previous request', vim.log.levels.WARN)
    end
    c.open_pane() -- surface the pane when a request starts; closing it afterwards keeps streaming in the background
    local row = c.append(o.entry)
    local r = c.region(row + #o.entry - 1, 1)
    stream_into(r, o.label, o.extra, o.prompt, function(result, err)
      if o.on_done then
        return o.on_done(result, err, r, row)
      end
      if not result then
        return r.render { '**error:** ' .. err, '' }
      end
      r.render(vim.list_extend(vim.split(result, '\n'), { '' }))
    end)
  end

  function c.chat()
    local s = c.session()
    if not s or not s.session_id then
      return notify 'no session; bootstrap first'
    end
    require('toggleterm.terminal').Terminal
      :new({ cmd = 'claude --resume ' .. s.session_id, dir = current.root, direction = 'float', close_on_exit = true })
      :toggle()
  end

  function c.reset()
    if not current then
      return
    end
    c.clear_session()
    os.remove(pane_file())
    local buf = c.find_pane_buf()
    if buf then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    notify 'session cleared'
  end

  return c
end

return M
```

- [ ] **Step 2: Format and load-check**

Run: `stylua lua/companion.lua && stylua --check lua/companion.lua`
Expected: exit 0, no output.

Run: `nvim --headless -c "lua local c = require('companion').new { name = 'x', label = 'x', scheme = 'x', tools = 'Read', allowed = {}, denied = {}, not_ready = 'n' }; assert(c.uuid():match('^%x+%-%x+%-4%x%x%x%-[89ab]%x%x%x%-%x+$')); assert(c.session() == nil); print('ok')" -c q`
Expected: prints `ok`, exit 0.

- [ ] **Step 3: Commit**

```bash
git add lua/companion.lua
git commit -m "feat: extract shared companion engine (claude runner, pane, sessions)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: `lua/pr_companion.lua` on the engine

**Files:**
- Modify: `lua/pr_companion.lua` (replace the whole file)

**Interfaces:**
- Consumes: everything listed under Task 1 "Produces".
- Produces: unchanged public API — `M.bootstrap()`, `M.ask(opts)`, `M.chat()`, `M.toggle()`, `M.reset()`, `M.offer(pr)`, `M.setup()`. `lua/pr_review.lua:249` calls `offer(pr)` and `lua/plugins/diffview.lua:56` calls `setup()`; neither changes.

- [ ] **Step 1: Replace the file**

Replace the entire content of `lua/pr_companion.lua` with:

```lua
-- AI review companion: one headless Claude Code session per PR, asked about selected diff lines from a markdown pane.
-- The engine (claude runner, streaming pane, sessions) is lua/companion.lua; this file is the PR layer: read-only tool
-- lists, prompts, the diffview-aware snippet, `offer` and the user commands.
-- Sessions live in stdpath('data')/pr_review/sessions.json keyed by <owner>_<repo>_<n>; each pane is mirrored to <key>.md next to it.
local M = {}

-- Read-only git/gh only; DENIED wins over ALLOWED (see lua/companion.lua for how --restricted enforces this).
local ALLOWED = {
  'Bash(git *)',
  'Bash(gh pr view *)',
  'Bash(gh pr diff *)',
  'Bash(gh pr checks *)',
  'Bash(gh pr list *)',
  'Bash(gh issue view *)',
  'Bash(gh run view *)',
  'Bash(gh run list *)',
  'Bash(gh search *)',
}
local DENIED = {}
for _, sub in ipairs {
  'checkout',
  'switch',
  'restore',
  'reset',
  'stash',
  'add',
  'rm',
  'mv',
  'commit',
  'push',
  'pull',
  'fetch',
  'rebase',
  'merge',
  'cherry-pick',
  'revert',
  'clean',
  'worktree',
  'branch -d',
  'branch -D',
  'tag',
  'am',
  'apply',
  'config',
  'submodule',
  '-c',
  '-C',
  '--git-dir',
  '--work-tree',
} do
  table.insert(DENIED, 'Bash(git ' .. sub .. ' *)')
end

local c = require('companion').new {
  name = 'pr_review',
  label = 'pr_companion',
  scheme = 'pr-companion',
  tools = 'Read,Grep,Glob,Bash',
  allowed = ALLOWED,
  denied = DENIED,
  not_ready = 'open a PR with :PrReview first',
}

local pr -- { url, number, title, body, base }; the checkout root is c.current().root

local function bootstrap_prompt()
  return table.concat({
    ('You are a code-review companion for GitHub PR #%d "%s" (%s).'):format(pr.number, pr.title, pr.url),
    ('The PR branch is checked out in this directory; the base branch is `origin/%s`.'):format(pr.base),
    'I am reviewing it in my editor and will send you selected snippets (with file path and line numbers) plus questions.',
    'Answer concisely, cite `path:line`, and say plainly when something looks wrong or when you are unsure.',
    'You have read-only access: file reads, grep/glob, and read-only `git`/`gh pr view|diff|checks` commands.',
    'You cannot write files, run tests or builds, or change the working tree — do not try; reason from the code instead.',
    '',
    '## PR description',
    pr.body ~= '' and pr.body or '(empty)',
    '',
    '## First task',
    ('Run `git diff origin/%s...HEAD --stat`, read what you need to understand the change,'):format(pr.base),
    'then reply with a summary of what this PR does (at most 15 lines) followed by a short list of what deserves careful review.',
  }, '\n')
end

function M.bootstrap()
  if not pr then
    return vim.notify('pr_companion: open a PR with :PrReview first', vim.log.levels.INFO)
  end
  local s = c.session()
  if s and s.session_id then
    return vim.notify('pr_companion: session already exists; :PrCompanion reset to start over', vim.log.levels.INFO)
  end
  if c.busy() then
    return vim.notify('pr_companion: busy', vim.log.levels.WARN)
  end
  local id = c.uuid()
  vim.notify('pr_companion: bootstrapping for PR #' .. pr.number .. ' (this takes a minute)…', vim.log.levels.INFO)
  c.request {
    entry = { '## Summary', '', '_bootstrapping…_' },
    label = 'bootstrapping…',
    extra = { '--session-id', id },
    prompt = bootstrap_prompt(),
    on_done = function(result, err, r, row)
      if not result then
        c.set_lines(row, r.row + r.len, {})
        return vim.notify('pr_companion: bootstrap failed\n' .. err, vim.log.levels.ERROR)
      end
      c.save_session { session_id = id }
      r.render(vim.list_extend(vim.split(result, '\n'), { '' }))
      vim.notify('pr_companion: ready', vim.log.levels.INFO)
    end,
  }
end

-- Snippet from buffer `buf` lines a..b: header line + fenced code. diffview buffers are `diffview://<gitdir>/<rev>/<path>`;
-- the rev tells which side (PR head vs base). Anything else is a real file in the working tree (= PR head).
local function snippet(buf, a, b)
  local root = c.current().root
  local name = vim.api.nvim_buf_get_name(buf)
  local rev, path = name:match '^diffview://.-/%.git/([^/]+)/(.*)$'
  local side = 'PR head'
  if rev then
    local head = vim.trim(vim.system({ 'git', 'rev-parse', 'HEAD' }, { text = true, cwd = root }):wait().stdout or '')
    side = vim.startswith(head, rev) and 'PR head' or 'base ' .. pr.base
  else
    path = vim.fs.relpath(root, name) or name
  end
  local lines = vim.api.nvim_buf_get_lines(buf, a - 1, b, false)
  local body = { ('File: %s  lines %d–%d  (%s)'):format(path, a, b, side), '```' .. vim.bo[buf].filetype }
  vim.list_extend(body, lines)
  table.insert(body, '```')
  return body
end

function M.ask(opts)
  if not pr then
    return vim.notify('pr_companion: open a PR with :PrReview first', vim.log.levels.INFO)
  end
  local s = c.session()
  if not s or not s.session_id then
    return vim.notify('pr_companion: no session for this PR; run :PrCompanion to bootstrap', vim.log.levels.INFO)
  end
  local buf = vim.api.nvim_get_current_buf()
  local code = opts.range > 0 and not vim.api.nvim_buf_get_name(buf):find '^pr%-companion://' and snippet(buf, opts.line1, opts.line2) or nil
  vim.ui.input({ prompt = 'Ask companion: ' }, function(q)
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

function M.chat()
  local s = c.session()
  if not s or not s.session_id then
    return vim.notify('pr_companion: no session for this PR; run :PrCompanion to bootstrap', vim.log.levels.INFO)
  end
  c.chat()
end

M.toggle = c.toggle
M.reset = c.reset

-- Called by pr_review after the diff view opens. pr = { url, number, title, body, baseRefName }.
function M.offer(p)
  local root = vim.trim(vim.system({ 'git', 'rev-parse', '--show-toplevel' }, { text = true }):wait().stdout or '')
  pr = { url = p.url, number = p.number, title = p.title, body = p.body or '', base = p.baseRefName }
  local key = p.url:gsub('^https?://github.com/', ''):gsub('/pull/', '_'):gsub('/', '_')
  c.set_current { key = key, title = ('PR #%d — %s'):format(p.number, p.title), root = root ~= '' and root or vim.fn.getcwd() }
  local s = c.session()
  if s and s.session_id then
    c.open_pane()
  elseif not (s and s.declined) then
    vim.ui.select({ 'Yes', 'No' }, { prompt = ('Bootstrap AI companion for PR #%d?'):format(p.number) }, function(choice)
      if choice == 'Yes' then
        M.bootstrap()
      elseif choice == 'No' then
        c.save_session { declined = true }
      end
    end)
  end
end

function M.setup()
  vim.api.nvim_create_user_command('PrCompanion', function(opts)
    local sub = opts.args
    local s = c.session()
    if sub == 'bootstrap' then
      M.bootstrap()
    elseif sub == 'toggle' then
      M.toggle()
    elseif sub == 'chat' then
      M.chat()
    elseif sub == 'reset' then
      M.reset()
    elseif s and s.session_id then
      M.toggle()
    else
      M.bootstrap()
    end
  end, {
    nargs = '?',
    complete = function()
      return { 'bootstrap', 'toggle', 'chat', 'reset' }
    end,
    desc = 'PR review AI companion (bootstrap | toggle | chat | reset)',
  })
  vim.api.nvim_create_user_command('PrAsk', M.ask, { range = true, desc = 'Ask the PR companion about the selected lines' })
  vim.api.nvim_create_user_command('PrChat', M.chat, { desc = 'Open the PR companion session in a terminal' })
end

return M
```

- [ ] **Step 2: Format and load-check**

Run: `stylua . && stylua --check .`
Expected: exit 0.

Run: `nvim --headless -c "lua require('pr_companion').setup(); assert(vim.fn.exists(':PrCompanion') == 2); assert(vim.fn.exists(':PrAsk') == 2); assert(vim.fn.exists(':PrChat') == 2); print('ok')" -c q`
Expected: prints `ok`, exit 0.

Run: `wc -l lua/pr_companion.lua`
Expected: fewer than 220 lines (was 513).

- [ ] **Step 3: Confirm no dead references**

Run: `grep -n "load_sessions\|save_sessions\|pane_file\|stream_into\|claude_args\|describe_tool\|TIMEOUT_MS\|PANE_WIDTH" lua/pr_companion.lua`
Expected: no output (all of these now live in `lua/companion.lua`).

- [ ] **Step 4: Commit**

```bash
git add lua/pr_companion.lua
git commit -m "refactor: pr_companion on the shared companion engine

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Docs for the engine

**Files:**
- Modify: `CLAUDE.md` (the "Shared Utilities" section, the line starting with `` `lua/pr_companion.lua` ``)
- Modify: `lua/plugins/CLAUDE.md` (section `### AI companion (`lua/pr_companion.lua`)`, its first paragraph)

- [ ] **Step 1: Root `CLAUDE.md`**

In `CLAUDE.md`, replace the line

```
`lua/pr_companion.lua` — per-PR headless Claude Code review companion (`:PrCompanion`, `:PrAsk`, `:PrChat`); sessions and pane transcripts under `stdpath('data')/pr_review/`.
```

with these two lines (blank line between them):

```
`lua/companion.lua` — shared engine for the AI companions: `new(spec)` returns an instance with the headless `claude -p` runner (stream-json, 10 min timeout), the streaming markdown pane (`request`, `region`, rebuild-from-mirror), and a `sessions.json` store keyed by `current.key` under `stdpath('data')/<spec.name>/`.

`lua/pr_companion.lua` — per-PR review companion on top of `companion.lua` (`:PrCompanion`, `:PrAsk`, `:PrChat`): read-only git/gh tool lists, prompts, diffview-aware snippets; data under `stdpath('data')/pr_review/`.
```

- [ ] **Step 2: `lua/plugins/CLAUDE.md`**

In the paragraph under `### AI companion (`lua/pr_companion.lua`)`, replace the sentence

```
Sessions keyed by PR URL in `stdpath('data')/pr_review/sessions.json`; the conversation pane is mirrored to `<owner>_<repo>_<n>.md` beside it and reloads with the PR.
```

with

```
The claude runner, streaming pane and sessions store are the shared engine `lua/companion.lua` (`require('companion').new(spec)`); this file only supplies tool lists, prompts, the snippet builder and commands. Sessions keyed by `<owner>_<repo>_<n>` in `stdpath('data')/pr_review/sessions.json`; the conversation pane (`pr-companion://<owner>_<repo>_<n>`) is mirrored to `<owner>_<repo>_<n>.md` beside it and reloads with the PR.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md lua/plugins/CLAUDE.md
git commit -m "docs: describe the shared companion engine

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final verification (run before reporting)

```bash
stylua --check .
nvim --headless -c "lua require('companion'); require('pr_companion').setup(); print('ok')" -c q
git status --short   # must be empty
git log --oneline -3 # the three commits above
```

Report per task: COMPLETED AS WRITTEN / COMPLETED WITH NOTES / BLOCKED, plus the output of the four commands above.

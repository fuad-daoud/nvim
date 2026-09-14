-- AI review companion: one headless Claude Code session per PR, asked about selected diff lines from a markdown pane.
-- Sessions live in stdpath('data')/pr_review/sessions.json; each pane is mirrored to <key>.md next to it.
local M = {}

-- The companion is strictly read-only. `--restricted` ignores settings files (the user's global `defaultMode = auto`
-- would otherwise auto-approve everything) and drops every tool not named in `--tools`; in print mode anything
-- outside ALLOWED is denied rather than prompted, and DENIED wins over ALLOWED.
local TOOLS = 'Read,Grep,Glob,Bash'
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
local TIMEOUT_MS = 10 * 60 * 1000
local PANE_WIDTH = 60

local data_dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'pr_review')
local sessions_file = vim.fs.joinpath(data_dir, 'sessions.json')

local current -- { url, number, title, body, base, root }
local busy = false
local sessions

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

local function session()
  return current and load_sessions()[current.url] or nil
end

local function key()
  return current.url:gsub('^https?://github.com/', ''):gsub('/pull/', '_'):gsub('/', '_')
end

local function pane_file()
  return vim.fs.joinpath(data_dir, key() .. '.md')
end

-- RFC 4122 v4 from OS randomness (math.random is unseeded in a fresh Neovim and would repeat).
local function uuid()
  local b = { vim.uv.random(16):byte(1, 16) }
  b[7] = bit.bor(bit.band(b[7], 0x0f), 0x40)
  b[9] = bit.bor(bit.band(b[9], 0x3f), 0x80)
  return ('%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x'):format(unpack(b))
end

local function claude_args(extra)
  local args = { 'claude', '-p', '--model', 'opus', '--effort', 'high', '--output-format', 'json', '--restricted', '--tools', TOOLS }
  vim.list_extend(args, { '--allowedTools' })
  vim.list_extend(args, ALLOWED)
  vim.list_extend(args, { '--disallowedTools' })
  vim.list_extend(args, DENIED)
  return vim.list_extend(args, extra)
end

-- Run claude headless with `prompt` on stdin; cb(result_text|nil, err).
local function claude(extra, prompt, cb)
  if vim.fn.executable 'claude' ~= 1 then
    return cb(nil, 'claude CLI not found on PATH')
  end
  busy = true
  vim.system(claude_args(extra), { text = true, stdin = prompt, cwd = current.root, timeout = TIMEOUT_MS }, function(res)
    vim.schedule(function()
      busy = false
      if res.signal ~= 0 and res.code ~= 0 then
        return cb(nil, ('claude gave up after %d minutes (killed)'):format(TIMEOUT_MS / 60000))
      end
      if res.code ~= 0 then
        return cb(nil, (res.stderr ~= '' and res.stderr or res.stdout or ''):gsub('%s+$', ''))
      end
      local ok, out = pcall(vim.json.decode, res.stdout)
      if not ok or type(out) ~= 'table' then
        return cb(nil, 'unexpected claude output:\n' .. res.stdout)
      end
      if out.is_error then
        return cb(nil, tostring(out.result))
      end
      cb(out.result or '')
    end)
  end)
end

---------------------------------------------------------------------------
-- Pane
---------------------------------------------------------------------------

local function pane_buf()
  local name = 'pr-companion://' .. current.number
  local buf = vim.fn.bufnr(name)
  if buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
    return buf
  end
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = 'markdown'
  local f = io.open(pane_file())
  if f then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(f:read '*a', '\n'))
    f:close()
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# PR #' .. current.number .. ' — ' .. current.title, '' })
  end
  vim.keymap.set('n', 'q', M.toggle, { buffer = buf, desc = 'Close companion pane' })
  return buf
end

local function pane_win()
  local buf = vim.fn.bufnr('pr-companion://' .. current.number)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      return win
    end
  end
end

local function open_pane()
  local buf = pane_buf()
  local win = pane_win()
  if not win then
    local prev = vim.api.nvim_get_current_win()
    vim.cmd('botright ' .. PANE_WIDTH .. 'vsplit')
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

-- Append lines to the pane and scroll it to the bottom. Returns the row of the first appended line.
local function append(lines)
  local buf, win = open_pane()
  local row = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_buf_set_lines(buf, row, row, false, lines)
  vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
  persist(buf)
  return row
end

local function replace_line(row, lines)
  local buf, win = open_pane()
  vim.api.nvim_buf_set_lines(buf, row, row + 1, false, lines)
  vim.api.nvim_win_set_cursor(win, { math.min(row + 1, vim.api.nvim_buf_line_count(buf)), 0 })
  persist(buf)
end

-- Rewrite the placeholder at `row` every few seconds with the elapsed time until `stop()` is called.
local function ticker(row, label)
  local started, timer = vim.uv.now(), vim.uv.new_timer()
  timer:start(
    5000,
    5000,
    vim.schedule_wrap(function()
      local buf = vim.fn.bufnr('pr-companion://' .. current.number)
      if buf == -1 then
        return
      end
      local secs = math.floor((vim.uv.now() - started) / 1000)
      vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { ('_%s (%dm%02ds)_'):format(label, secs / 60, secs % 60) })
    end)
  )
  return function()
    timer:stop()
    timer:close()
  end
end

function M.toggle()
  if not current then
    return vim.notify('pr_companion: open a PR with :PrReview first', vim.log.levels.INFO)
  end
  local win = pane_win()
  if win then
    vim.api.nvim_win_close(win, true)
  else
    open_pane()
  end
end

---------------------------------------------------------------------------
-- Bootstrap / ask
---------------------------------------------------------------------------

local function bootstrap_prompt()
  return table.concat({
    ('You are a code-review companion for GitHub PR #%d "%s" (%s).'):format(current.number, current.title, current.url),
    ('The PR branch is checked out in this directory; the base branch is `origin/%s`.'):format(current.base),
    'I am reviewing it in my editor and will send you selected snippets (with file path and line numbers) plus questions.',
    'Answer concisely, cite `path:line`, and say plainly when something looks wrong or when you are unsure.',
    'You have read-only access: file reads, grep/glob, and read-only `git`/`gh pr view|diff|checks` commands.',
    'You cannot write files, run tests or builds, or change the working tree — do not try; reason from the code instead.',
    '',
    '## PR description',
    current.body ~= '' and current.body or '(empty)',
    '',
    '## First task',
    ('Run `git diff origin/%s...HEAD --stat`, read what you need to understand the change,'):format(current.base),
    'then reply with a summary of what this PR does (at most 15 lines) followed by a short list of what deserves careful review.',
  }, '\n')
end

function M.bootstrap()
  if not current then
    return vim.notify('pr_companion: open a PR with :PrReview first', vim.log.levels.INFO)
  end
  if session() and session().session_id then
    return vim.notify('pr_companion: session already exists; :PrCompanion reset to start over', vim.log.levels.INFO)
  end
  if busy then
    return vim.notify('pr_companion: busy', vim.log.levels.WARN)
  end
  local id = uuid()
  vim.notify('pr_companion: bootstrapping for PR #' .. current.number .. ' (this takes a minute)…', vim.log.levels.INFO)
  local row = append { '## Summary', '', '_bootstrapping…_' }
  local stop = ticker(row + 2, 'bootstrapping…')
  claude({ '--session-id', id }, bootstrap_prompt(), function(result, err)
    stop()
    if not result then
      local buf = open_pane()
      vim.api.nvim_buf_set_lines(buf, row, row + 3, false, {})
      persist(buf)
      return vim.notify('pr_companion: bootstrap failed\n' .. err, vim.log.levels.ERROR)
    end
    load_sessions()[current.url] = { session_id = id }
    save_sessions()
    replace_line(row + 2, vim.list_extend(vim.split(result, '\n'), { '' }))
    vim.notify('pr_companion: ready', vim.log.levels.INFO)
  end)
end

-- Snippet from buffer `buf` lines a..b: header line + fenced code. diffview buffers are `diffview://<gitdir>/<rev>/<path>`;
-- the rev tells which side (PR head vs base). Anything else is a real file in the working tree (= PR head).
local function snippet(buf, a, b)
  local name = vim.api.nvim_buf_get_name(buf)
  local rev, path = name:match '^diffview://.-/%.git/([^/]+)/(.*)$'
  local side = 'PR head'
  if rev then
    local head = vim.trim(vim.system({ 'git', 'rev-parse', 'HEAD' }, { text = true, cwd = current.root }):wait().stdout or '')
    side = vim.startswith(head, rev) and 'PR head' or 'base ' .. current.base
  else
    path = vim.fs.relpath(current.root, name) or name
  end
  local lines = vim.api.nvim_buf_get_lines(buf, a - 1, b, false)
  local body = { ('File: %s  lines %d–%d  (%s)'):format(path, a, b, side), '```' .. vim.bo[buf].filetype }
  vim.list_extend(body, lines)
  table.insert(body, '```')
  return body
end

function M.ask(opts)
  if not current then
    return vim.notify('pr_companion: open a PR with :PrReview first', vim.log.levels.INFO)
  end
  local s = session()
  if not s or not s.session_id then
    return vim.notify('pr_companion: no session for this PR; run :PrCompanion to bootstrap', vim.log.levels.INFO)
  end
  local buf = vim.api.nvim_get_current_buf()
  local code = opts.range > 0 and not vim.api.nvim_buf_get_name(buf):find '^pr%-companion://' and snippet(buf, opts.line1, opts.line2) or nil
  vim.ui.input({ prompt = 'Ask companion: ' }, function(q)
    if not q or q:match '^%s*$' then
      return
    end
    if busy then
      return vim.notify('pr_companion: busy with the previous question', vim.log.levels.WARN)
    end
    local entry = { '### ❯ ' .. q, '' }
    if code then
      vim.list_extend(entry, code)
      table.insert(entry, '')
    end
    table.insert(entry, '_thinking…_')
    local row = append(entry) + #entry - 1
    local message = code and table.concat(code, '\n') .. '\n\nQuestion: ' .. q or q
    local stop = ticker(row, 'thinking…')
    claude({ '--resume', s.session_id }, message, function(result, err)
      stop()
      if not result then
        return replace_line(row, { '**error:** ' .. err, '' })
      end
      replace_line(row, vim.list_extend(vim.split(result, '\n'), { '' }))
    end)
  end)
end

function M.chat()
  local s = session()
  if not s or not s.session_id then
    return vim.notify('pr_companion: no session for this PR; run :PrCompanion to bootstrap', vim.log.levels.INFO)
  end
  require('toggleterm.terminal').Terminal
    :new({ cmd = 'claude --resume ' .. s.session_id, dir = current.root, direction = 'float', close_on_exit = true })
    :toggle()
end

function M.reset()
  if not current then
    return
  end
  load_sessions()[current.url] = nil
  save_sessions()
  os.remove(pane_file())
  local buf = vim.fn.bufnr('pr-companion://' .. current.number)
  if buf ~= -1 then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  vim.notify('pr_companion: session cleared', vim.log.levels.INFO)
end

-- Called by pr_review after the diff view opens. pr = { url, number, title, body, baseRefName }.
function M.offer(pr)
  local root = vim.trim(vim.system({ 'git', 'rev-parse', '--show-toplevel' }, { text = true }):wait().stdout or '')
  current = { url = pr.url, number = pr.number, title = pr.title, body = pr.body or '', base = pr.baseRefName, root = root ~= '' and root or vim.fn.getcwd() }
  local s = session()
  if s and s.session_id then
    open_pane()
  elseif not (s and s.declined) then
    vim.ui.select({ 'Yes', 'No' }, { prompt = ('Bootstrap AI companion for PR #%d?'):format(pr.number) }, function(choice)
      if choice == 'Yes' then
        M.bootstrap()
      elseif choice == 'No' then
        load_sessions()[pr.url] = { declined = true }
        save_sessions()
      end
    end)
  end
end

function M.setup()
  vim.api.nvim_create_user_command('PrCompanion', function(opts)
    local sub = opts.args
    if sub == 'bootstrap' then
      M.bootstrap()
    elseif sub == 'toggle' then
      M.toggle()
    elseif sub == 'chat' then
      M.chat()
    elseif sub == 'reset' then
      M.reset()
    elseif session() and session().session_id then
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

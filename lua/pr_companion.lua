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

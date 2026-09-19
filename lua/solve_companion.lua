-- Socratic coach for the lc.py LeetCode workbench (~/projects/solve): one headless Claude Code session per problem
-- (parsed from solve.py's `# N. Title [Difficulty]` header), a 4-rung hint ladder, attempt review and an on-demand
-- debrief. The engine (claude runner, streaming pane, sessions) is lua/companion.lua.
-- Sessions live in stdpath('data')/solve/sessions.json keyed by NNNN-slug; each pane is mirrored to <key>.md next to it.
local M = {}

local c = require('companion').new {
  name = 'solve',
  label = 'solve_companion',
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

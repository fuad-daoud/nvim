-- Socratic coach for the lc.py LeetCode workbench (~/projects/solve): one headless agent session per problem
-- (parsed from solve.py's `# N. Title [Difficulty]` header), a 4-rung hint ladder, attempt review and an on-demand
-- debrief. The engine (claude/agy runners, streaming pane, sessions) is lua/companion.lua; `:Solve model` picks the
-- engine, model and effort (persisted in stdpath('data')/solve/backend.json). Switching engine drops the current
-- problem's session — claude and agy cannot resume each other's — while model/effort changes keep it.
-- Sessions live in stdpath('data')/solve/sessions.json keyed by NNNN-slug; each pane is mirrored to <key>.md next to it.
local M = {}

local c = require('companion').new {
  name = 'solve',
  label = 'solve_companion',
  scheme = 'solve-companion',
  tools = 'Read,Grep,Glob,Bash',
  allowed = { 'Bash(python3 lc.py test*)', 'Bash(make test*)' },
  denied = {},
  agy_allow = { 'command(python3 lc.py test)', 'command(make test)' },
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
-- `quiet` skips the warnings (used by the model picker, which also works outside a workbench).
local function refresh(quiet)
  local function warn(msg)
    if not quiet then
      notify(msg, vim.log.levels.WARN)
    end
  end
  local file = vim.api.nvim_buf_get_name(0)
  local dir
  if file == '' or vim.bo.buftype ~= '' then
    dir = problem and problem.dir or vim.fn.getcwd()
  else
    dir = vim.fn.fnamemodify(file, ':p:h')
  end
  local solve = vim.fs.joinpath(dir, 'solve.py')
  if vim.fn.filereadable(vim.fs.joinpath(dir, 'lc.py')) == 0 or vim.fn.filereadable(solve) == 0 then
    warn 'not an lc.py workbench'
    return false
  end
  local lines = vim.fn.readfile(solve, '', 2)
  local number, name, difficulty = (lines[1] or ''):match '^#%s*(%d+)%.%s*(.-)%s*%[(%w+)%]%s*$'
  local url = (lines[2] or ''):match '^#%s*(https?://%S+)'
  if not number or not url then
    warn 'no problem header in solve.py — run make start / make next'
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
  local made, now = c.session_backend(), c.backend().name
  if made ~= now then
    notify(('session was made with %s, engine is %s — :Solve model to switch back or :Solve reset'):format(made, now), vim.log.levels.WARN)
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
    'Use your file-reading and search tools rather than shell commands; any command other than `python3 lc.py test` is blocked.',
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
  notify(('bootstrapping coach for %d. %s on %s (this takes a minute)…'):format(problem.number, problem.name, c.tag()))
  c.request {
    entry = { '## Coach', '', '_bootstrapping…_' },
    label = 'bootstrapping…',
    prompt = bootstrap_prompt(),
    on_done = function(result, err, r, row, id)
      if not result then
        c.set_lines(row, r.row + r.len, {})
        return notify('bootstrap failed\n' .. err, vim.log.levels.ERROR)
      end
      c.save_session { session_id = id, backend = c.backend().name, hint = 0 }
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
    resume = s.session_id,
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
      resume = s.session_id,
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
    resume = s.session_id,
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
      resume = s.session_id,
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

-- Engine → model → effort picker. Changing engine drops this problem's session (after a confirm); model/effort keep it.
function M.pick_model()
  if c.busy() then
    return notify('busy — wait for the current answer first', vim.log.levels.WARN)
  end
  local in_workbench = refresh(true)
  local engines = { 'claude', 'agy' }
  vim.ui.select(engines, {
    prompt = 'Coach engine (now ' .. c.tag() .. ')',
    format_item = function(name)
      return name == c.backend().name and name .. '  (current)' or name
    end,
  }, function(name)
    if not name then
      return
    end
    require('companion').models(name, function(models, err)
      if not models then
        return notify(err, vim.log.levels.ERROR)
      end
      vim.ui.select(models, {
        prompt = name .. ' model',
        format_item = function(m)
          return m.label == m.id and m.id or ('%s  (%s)'):format(m.label, m.id)
        end,
      }, function(m)
        if not m then
          return
        end
        local function apply(effort)
          local function commit()
            c.set_backend { name = name, model = m.id, effort = effort }
            notify('coach engine: ' .. c.tag())
          end
          local made = in_workbench and c.session_backend()
          if not made or made == name then
            return commit()
          end
          local prompt = ('Switching to %s drops the coach session for %d. %s (made with %s) — continue?'):format(name, problem.number, problem.name, made)
          vim.ui.select({ 'Yes', 'No' }, { prompt = prompt }, function(choice)
            if choice == 'Yes' then
              c.reset()
              commit()
            end
          end)
        end
        if #m.efforts <= 1 then
          return apply(m.efforts[1])
        end
        local cur = c.backend()
        vim.ui.select(m.efforts, {
          prompt = m.label .. ' effort',
          format_item = function(e)
            return cur.name == name and cur.model == m.id and cur.effort == e and e .. '  (current)' or e
          end,
        }, function(e)
          if e then
            apply(e)
          end
        end)
      end)
    end)
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
    elseif sub == 'model' then
      M.pick_model()
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
      return { 'bootstrap', 'toggle', 'chat', 'reset', 'model' }
    end,
    desc = 'LeetCode coach (bootstrap | toggle | chat | reset | model)',
  })
  vim.api.nvim_create_user_command('SolveHint', M.hint, { desc = 'Next hint on the ladder (1 observation … 4 algorithm sketch)' })
  vim.api.nvim_create_user_command('SolveAsk', M.ask, { range = true, desc = 'Ask the coach about the selected lines' })
  vim.api.nvim_create_user_command('SolveReview', M.review, { desc = 'Coach reviews solve.py against cases.txt without fixing it' })
  vim.api.nvim_create_user_command('SolveDebrief', M.debrief, { desc = 'Post-solve debrief: optimal approach, complexity, takeaways' })
  vim.api.nvim_create_user_command('SolveChat', M.chat, { desc = 'Open the coach session in a terminal' })
end

return M

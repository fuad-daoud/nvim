-- Two-pane runner for plain Python practice files: `input.txt` feeds stdin, `output.txt` collects
-- stdout+stderr. Both live next to the .py file and sit in a right column (input on top), sized by `M.layout`.
--
-- In an `lc.py` workbench dir (~/projects/solve) the top pane is `cases.txt` instead and the command is
-- `python3 lc.py test` — the report still lands in `output.txt`. `M.description()` toggles between that
-- layout's tab and a dedicated tab holding `problem.md` (the statement), so neither layout is disturbed.
local M = {}

local WIDTH_FRAC = 0.25

local function find_win(path)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == path then
      return win
    end
  end
end

local function ensure_file(path)
  if vim.fn.filereadable(path) == 0 then
    vim.fn.writefile({}, path)
  end
end

local function save_if_modified(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.bo[buf].modified then
    vim.api.nvim_buf_call(buf, function()
      vim.cmd.write()
    end)
  end
end

-- Open (or reuse) the right column: input.txt on top, output.txt below. Returns to `origin_win`.
local function ensure_panes(input, output, origin_win)
  local in_win, out_win = find_win(input), find_win(output)
  if in_win and out_win then
    return
  end

  if not in_win then
    vim.api.nvim_set_current_win(origin_win)
    vim.cmd(('botright %dvsplit %s'):format(math.floor(vim.o.columns * WIDTH_FRAC), vim.fn.fnameescape(input)))
    in_win = vim.api.nvim_get_current_win()
  end

  if not out_win then
    vim.api.nvim_set_current_win(in_win)
    vim.cmd('belowright split ' .. vim.fn.fnameescape(output))
    out_win = vim.api.nvim_get_current_win()
    vim.wo[out_win].wrap = true
  end

  vim.api.nvim_set_current_win(origin_win)
  M.layout()
end

-- Decide the input pane and shell command for `file`: lc.py workbench or plain stdin runner.
-- `-u` = unbuffered, so each write reaches us the moment Python makes it rather than in 8KB chunks; `2>&1` keeps
-- tracebacks in order with prints on the one pipe `M.run` streams from.
local function plan(file, dir)
  local esc = vim.fn.shellescape
  if vim.fn.filereadable(dir .. '/lc.py') == 1 then
    return dir .. '/cases.txt', ('cd %s && exec python3 -u lc.py test 2>&1'):format(esc(dir))
  end
  local input = dir .. '/input.txt'
  return input, ('exec python3 -u %s < %s 2>&1'):format(esc(file), esc(input))
end

local MAX_BYTES = 200 * 1024 -- per run; a printing infinite loop in a plain script would otherwise flood the pane

-- Put every window showing `buf` on its last line (tail -f).
local function follow(buf)
  local last = vim.api.nvim_buf_line_count(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    vim.api.nvim_win_set_cursor(win, { last, 0 })
  end
end

-- Where one run's output goes: appended to output.txt and to its buffer as each chunk arrives.
-- `push` is called from the job's stdout callback (a fast event, no API calls), so it only queues and schedules
-- a `flush`, which does the writing on the main loop; a flood of chunks costs one flush per loop turn.
local function sink(output)
  local self = { file = assert(io.open(output, 'w')), pending = {}, bytes = 0, cut = false, scheduled = false }
  local buf = vim.fn.bufnr(output)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.bo[buf].modified = false
  end

  function self.flush()
    self.scheduled = false
    if not self.file or #self.pending == 0 then
      return
    end
    local text = table.concat(self.pending)
    self.pending = {}
    self.file:write(text)
    self.file:flush()
    buf = vim.fn.bufnr(output) -- the pane may have been closed or reopened mid-run
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      local row = vim.api.nvim_buf_line_count(buf) - 1
      local col = #vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
      vim.api.nvim_buf_set_text(buf, row, col, row, col, vim.split(text, '\n', { plain = true }))
      vim.bo[buf].modified = false -- it matches the file; we're writing both
      follow(buf)
    end
  end

  function self.push(data)
    if self.cut then
      return
    end
    if self.bytes + #data > MAX_BYTES then
      data = data:sub(1, MAX_BYTES - self.bytes) .. ('\n... output cut at %dKB\n'):format(MAX_BYTES / 1024)
      self.cut = true
    end
    self.bytes = self.bytes + #data
    table.insert(self.pending, data)
    if not self.scheduled then
      self.scheduled = true
      vim.schedule(self.flush)
    end
  end

  -- Flush what's left, close the file, and re-read it into the buffer so Neovim's idea of the file is current
  -- (no "file changed since editing" warning later).
  function self.close()
    self.flush()
    if self.file then
      self.file:close()
      self.file = nil
    end
    buf = vim.fn.bufnr(output)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_call(buf, function()
        vim.cmd 'silent! edit!'
      end)
      follow(buf)
    end
  end

  return self
end

-- The run in flight, if any: { job, sink, note, started }. A new run kills it first so only one writes output.txt.
local running
local TIMEOUT_MS = 15000 -- backstop for plain scripts; lc.py already times out each case on its own
local NOTE = { title = 'pyrun' }

local function note(msg, level, opts)
  return vim.notify(msg, level, vim.tbl_extend('force', NOTE, opts or {}))
end

--- Save, run (see `plan`), and stream stdout+stderr into output.txt and its pane as it's written.
M.run = function()
  local origin_win = vim.api.nvim_get_current_win()
  local file = vim.fn.expand '%:p'
  local dir = vim.fn.fnamemodify(file, ':h')
  local input, cmd = plan(file, dir)
  local output = dir .. '/output.txt'

  vim.cmd.write()
  ensure_file(input)
  ensure_file(output)
  save_if_modified(input)
  ensure_panes(input, output, origin_win)

  local previous = running
  running = nil
  if previous then
    previous.job:kill 'sigkill'
    previous.job:wait(1000)
    previous.sink.file:close()
    previous.sink.file = nil -- its queued flushes become no-ops
  end

  local run = { started = vim.uv.hrtime(), sink = sink(output) }
  -- timeout=false keeps it up until the result replaces it; replacing the superseded run's note avoids a pile-up
  run.note = note(('running %s…'):format(vim.fs.basename(file)), vim.log.levels.INFO,
    { timeout = false, replace = previous and previous.note })

  run.job = vim.system({ 'sh', '-c', cmd }, {
    timeout = TIMEOUT_MS,
    stdout = function(_, data)
      if data then
        run.sink.push(data)
      end
    end,
  }, function(res)
    vim.schedule(function()
      if running ~= run then
        return -- superseded by a newer run, which owns output.txt (and the notification) now
      end
      running = nil
      run.sink.close()
      local secs = (vim.uv.hrtime() - run.started) / 1e9
      local opts = { timeout = 3000, replace = run.note }
      if res.code == 124 then
        note(('killed after %ds — infinite loop?'):format(TIMEOUT_MS / 1000), vim.log.levels.WARN, opts)
      elseif res.code ~= 0 then
        note(('exited %d after %.1fs — see output.txt'):format(res.code, secs), vim.log.levels.WARN, opts)
      else
        note(('done in %.1fs'):format(secs), vim.log.levels.INFO, opts)
      end
    end)
  end)
  running = run
end

-- Wide-screen layout for a tab holding the runner panes and/or the solve coach pane (`solve-companion://…`):
-- the code window gets CODE_FRAC of the width (clamped to CODE_MIN..CODE_MAX columns) and everything else goes to
-- the right — split IO_SHARE : rest between the input/output column and the coach when both are open, else all to
-- the one that is. The input pane gets INPUT_FRAC of the column height (output below gets the rest). The side panes
-- are winfixwidth so 'equalalways' stops reshuffling them; the layout is re-applied whenever a window opens or closes
-- and on VimResized. Other windows (file tree, …) keep their width.
local CODE_FRAC, CODE_MIN, CODE_MAX = 0.36, 90, 120
local IO_SHARE, INPUT_FRAC = 0.42, 0.35

local function classify(tab)
  local w = { others = {} }
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      local base = vim.fs.basename(name)
      if name:match '^solve%-companion://' then
        w.coach = w.coach or win
      elseif base == 'output.txt' then
        w.output = w.output or win
      elseif base == 'cases.txt' or base == 'input.txt' then
        w.input = w.input or win
      elseif name:match '%.py$' and not w.code then
        w.code = win
      else
        table.insert(w.others, win)
      end
    end
  end
  return w
end

--- Apply the layout to the current tab; a no-op unless it has a .py window plus a runner or coach pane.
M.layout = function()
  local w = classify(vim.api.nvim_get_current_tabpage())
  local io = w.input or w.output
  if not w.code or not (io or w.coach) then
    return
  end
  local avail = vim.o.columns
  for _, win in ipairs(w.others) do
    -- only windows beside the code (full-height columns such as a file tree) take width away
    if vim.api.nvim_win_get_height(win) >= vim.api.nvim_win_get_height(w.code) then
      avail = avail - vim.api.nvim_win_get_width(win) - 1
    end
  end
  local code = math.max(CODE_MIN, math.min(CODE_MAX, math.floor(vim.o.columns * CODE_FRAC)))
  local right = avail - code - (io and 1 or 0) - (w.coach and 1 or 0) -- one separator per side pane
  if right < 40 then
    return -- screen too narrow for this layout; leave it alone
  end
  local io_w = io and (w.coach and math.floor(right * IO_SHARE) or right) or 0
  for _, pair in ipairs { { w.coach, right - io_w }, { io, io_w } } do
    local win, width = pair[1], pair[2]
    if win then
      vim.wo[win].winfixwidth = true
      vim.api.nvim_win_set_width(win, width)
    end
  end
  if w.input and w.output then
    local total = vim.api.nvim_win_get_height(w.input) + vim.api.nvim_win_get_height(w.output)
    vim.wo[w.input].winfixheight = true
    vim.api.nvim_win_set_height(w.input, math.max(3, math.floor(total * INPUT_FRAC)))
  end
end

local scheduled = false
local function relayout()
  if not scheduled then
    scheduled = true
    vim.schedule(function()
      scheduled = false
      M.layout()
    end)
  end
end

vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinClosed', 'VimResized' }, {
  group = vim.api.nvim_create_augroup('pyrun_layout', { clear = true }),
  callback = relayout,
  desc = 'pyrun: keep the solve tab layout (code | input/output | coach)',
})

-- Tab page number whose windows include `path`, or nil.
local function find_tab(path)
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
      if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == path then
        return vim.api.nvim_tabpage_get_number(tab)
      end
    end
  end
end

--- Toggle between the solve tab and a tab showing `problem.md` (next to the current file).
--- From `problem.md` it returns to the tab holding `solve.py`; from anywhere else it opens or jumps to the problem tab.
M.description = function()
  local dir = vim.fn.expand '%:p:h'
  local md, solve = dir .. '/problem.md', dir .. '/solve.py'

  if vim.fn.expand '%:p' == md then
    local tab = find_tab(solve) or vim.fn.tabpagenr '#'
    if tab > 0 then
      vim.cmd.tabnext(tab)
    end
    return
  end

  if vim.fn.filereadable(md) == 0 then
    vim.notify('no problem.md here (run `make start` first)', vim.log.levels.WARN)
    return
  end

  local tab = find_tab(md)
  if tab then
    vim.cmd.tabnext(tab)
    return
  end

  vim.cmd('tabnew ' .. vim.fn.fnameescape(md))
  vim.wo.wrap, vim.wo.linebreak = true, true
  -- same key toggles back from the problem tab
  vim.keymap.set('n', '<leader>rd', M.description, { buffer = true, desc = 'back to solve tab' })
end

return M

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
local function plan(file, dir)
  local esc = vim.fn.shellescape
  if vim.fn.filereadable(dir .. '/lc.py') == 1 then
    return dir .. '/cases.txt', ('cd %s && python3 lc.py test'):format(esc(dir))
  end
  local input = dir .. '/input.txt'
  return input, ('python3 %s < %s'):format(esc(file), esc(input))
end

--- Save, run (see `plan`) with stdout+stderr → output.txt, and refresh the output pane.
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

  cmd = ('%s > %s 2>&1'):format(cmd, vim.fn.shellescape(output))
  vim.system({ 'sh', '-c', cmd }, {}, function(res)
    vim.schedule(function()
      local out_buf = vim.fn.bufnr(output)
      if out_buf ~= -1 then
        vim.api.nvim_buf_call(out_buf, function()
          vim.cmd 'silent! edit!'
        end)
      end
      if res.code ~= 0 then
        vim.notify(('exited %d — see output.txt'):format(res.code), vim.log.levels.WARN)
      end
    end)
  end)
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

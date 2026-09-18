-- Two-pane runner for plain Python practice files: `input.txt` feeds stdin, `output.txt` collects
-- stdout+stderr. Both live next to the .py file and sit in a 25%-wide right column (input on top).
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
end

--- Save, run `python3 <file> < input.txt > output.txt 2>&1`, and refresh the output pane.
M.run = function()
  local origin_win = vim.api.nvim_get_current_win()
  local file = vim.fn.expand '%:p'
  local dir = vim.fn.fnamemodify(file, ':h')
  local input, output = dir .. '/input.txt', dir .. '/output.txt'

  vim.cmd.write()
  ensure_file(input)
  ensure_file(output)
  save_if_modified(input)
  ensure_panes(input, output, origin_win)

  local cmd = ('python3 %s < %s > %s 2>&1'):format(vim.fn.shellescape(file), vim.fn.shellescape(input), vim.fn.shellescape(output))
  vim.system({ 'sh', '-c', cmd }, {}, function(res)
    vim.schedule(function()
      local out_buf = vim.fn.bufnr(output)
      if out_buf ~= -1 then
        vim.api.nvim_buf_call(out_buf, function()
          vim.cmd 'silent! edit!'
        end)
      end
      if res.code ~= 0 then
        vim.notify(('python3 exited %d — see output.txt'):format(res.code), vim.log.levels.WARN)
      end
    end)
  end)
end

return M

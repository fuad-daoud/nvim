-- Run the current file in a 25%-wide vertical toggleterm split (plain .py practice files; leetcode.nvim has its own :Leet run).
-- Uses the Lua API rather than :TermExec — its argument parser can't handle a quoted path inside cmd="...".
-- Dedicated terminal id so it never reuses the <C-\> float.
local RUN_TERM_ID = 9

vim.keymap.set('n', '<leader>rp', function()
  vim.cmd.write()
  local cmd = 'python3 ' .. vim.fn.shellescape(vim.fn.expand '%:p')
  require('toggleterm').exec(cmd, RUN_TERM_ID, math.floor(vim.o.columns * 0.25), nil, 'vertical')
end, { buffer = true, desc = '[R]un [P]ython file' })

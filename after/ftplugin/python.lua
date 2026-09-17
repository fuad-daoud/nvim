-- Run the current file in the toggleterm float (plain .py practice files; leetcode.nvim has its own :Leet run).
-- Uses the Lua API rather than :TermExec — its argument parser can't handle a quoted path inside cmd="...".
vim.keymap.set('n', '<leader>rp', function()
  vim.cmd.write()
  require('toggleterm').exec('python3 ' .. vim.fn.shellescape(vim.fn.expand '%:p'), nil, nil, nil, 'float')
end, { buffer = true, desc = '[R]un [P]ython file' })

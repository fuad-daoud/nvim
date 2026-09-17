-- Run the current file in the toggleterm float (plain .py practice files; leetcode.nvim has its own :Leet run).
vim.keymap.set('n', '<leader>rp', function()
  vim.cmd.write()
  vim.cmd(string.format('TermExec cmd="python3 %s" direction=float', vim.fn.shellescape(vim.fn.expand '%:p')))
end, { buffer = true, desc = '[R]un [P]ython file' })

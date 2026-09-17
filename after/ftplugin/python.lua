-- Two-pane runner (input.txt → stdin, stdout+stderr → output.txt); see lua/pyrun.lua.
vim.keymap.set('n', '<leader>rp', function()
  require('pyrun').run()
end, { buffer = true, desc = '[R]un [P]ython file with input.txt → output.txt' })

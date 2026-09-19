-- Two-pane runner (input.txt → stdin, stdout+stderr → output.txt); see lua/pyrun.lua.
vim.keymap.set('n', '<leader>rp', function()
  require('pyrun').run()
end, { buffer = true, desc = '[R]un [P]ython file with input.txt → output.txt' })

-- lc.py workbench: Socratic coach (lua/solve_companion.lua). Only where lc.py sits next to the file; <leader>a is free.
if vim.fn.filereadable(vim.fn.expand '%:p:h' .. '/lc.py') == 1 then
  require('solve_companion').setup()
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = true, silent = true, desc = desc })
  end
  map({ 'n', 'x' }, '<leader>aa', ':SolveAsk<CR>', 'Co[a]ch: [a]sk about selection')
  map('n', '<leader>ah', ':SolveHint<CR>', 'Co[a]ch: next [h]int')
  map('n', '<leader>ar', ':SolveReview<CR>', 'Co[a]ch: [r]eview my attempt')
  map('n', '<leader>ad', ':SolveDebrief<CR>', 'Co[a]ch: [d]ebrief (reveals solution)')
  map('n', '<leader>at', ':Solve toggle<CR>', 'Co[a]ch: [t]oggle pane')
  map('n', '<leader>ac', ':SolveChat<CR>', 'Co[a]ch: terminal [c]hat')
end

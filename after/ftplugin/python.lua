-- Two-pane runner: input.txt → stdin (or `lc.py test` in a workbench dir), stdout+stderr → output.txt; see lua/pyrun.lua.
-- Loading it registers the layout autocmds (code | input/output | coach widths) before any pane opens.
require 'pyrun'
vim.keymap.set('n', '<leader>rp', function()
  require('pyrun').run()
end, { buffer = true, desc = '[R]un [P]ython file (input.txt / lc.py test) → output.txt' })

-- lc.py workbench: toggle to a dedicated tab holding problem.md (the statement); see lua/pyrun.lua.
vim.keymap.set('n', '<leader>rd', function()
  require('pyrun').description()
end, { buffer = true, desc = '[R]ead problem [D]escription (problem.md) in its own tab' })

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
  map('n', '<leader>av', ':SolveVerify<CR>', 'Co[a]ch: [v]erify optimal approach implemented correctly')
  map('n', '<leader>at', ':Solve toggle<CR>', 'Co[a]ch: [t]oggle pane')
  map('n', '<leader>ac', ':SolveChat<CR>', 'Co[a]ch: terminal [c]hat')
  map('n', '<leader>am', ':Solve model<CR>', 'Co[a]ch: pick engine / [m]odel / effort (claude or agy)')
end

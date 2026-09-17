-- `nvim leetcode.nvim` from the shell opens straight into the dashboard; otherwise load on :Leet.
local leet_arg = 'leetcode.nvim'

return {
  'kawre/leetcode.nvim',
  build = ':TSUpdate html',
  dependencies = {
    'nvim-telescope/telescope.nvim',
    'nvim-lua/plenary.nvim',
    'MunifTanjim/nui.nvim',
  },
  cmd = 'Leet',
  lazy = leet_arg ~= vim.fn.argv(0, -1),
  keys = {
    { '<leader>ll', '<cmd>Leet list<CR>', desc = '[L]eetcode: problem [L]ist' },
    { '<leader>lr', '<cmd>Leet run<CR>', desc = '[L]eetcode: [R]un tests' },
    { '<leader>ls', '<cmd>Leet submit<CR>', desc = '[L]eetcode: [S]ubmit' },
    { '<leader>ld', '<cmd>Leet desc<CR>', desc = '[L]eetcode: toggle [D]escription' },
    { '<leader>lc', '<cmd>Leet console<CR>', desc = '[L]eetcode: [C]onsole' },
    { '<leader>lm', '<cmd>Leet<CR>', desc = '[L]eetcode: start / [M]enu' },
  },
  opts = {
    arg = leet_arg,
    lang = 'python3',
    image_support = false,
    -- Let :Leet start from a normal session (default refuses if any listed buffer is open).
    plugins = { non_standalone = true },
    -- Prepend the imports LeetCode's runtime provides implicitly so stubs run locally without edits.
    injector = {
      python3 = {
        before = {
          'from typing import *',
          'from collections import *',
          'import heapq, math, bisect, itertools, functools',
        },
      },
    },
  },
}

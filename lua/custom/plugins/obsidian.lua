return {
  'epwalsh/obsidian.nvim',
  version = '*',
  lazy = false,
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  opts = {
    workspaces = {
      {
        name = 'personal',
        path = '~/vaults/personal',
      },
      {
        name = 'work',
        path = '~/vaults/progressoft',
      },
    },
  },
  config = function(_, opts)
    require('obsidian').setup(opts)

    vim.keymap.set('n', '<leader>ot', function()
      vim.cmd 'ObsidianToday'
    end, { desc = '[O]bsidian [T]oday' })

    vim.keymap.set('n', '<leader>om', function()
      vim.cmd 'ObsidianTomorrow'
    end, { desc = '[O]bsidian To[m]orrow' })

    vim.keymap.set('n', '<leader>oy', function()
      vim.cmd 'ObsidianYesterday'
    end, { desc = '[O]bsidian [Y]esterday' })

    vim.keymap.set('n', '<leader>od', function()
      vim.cmd 'ObsidianDailies'
    end, { desc = '[O]bsidian [D]ailies' })

    vim.keymap.set('n', '<leader>os', function()
      vim.cmd 'ObsidianSearch'
    end, { desc = '[O]bsidian [S]earch' })

    vim.keymap.set('n', '<leader>oqs', function()
      vim.cmd 'ObsidianQuickSwitch'
    end, { desc = '[O]bsidian [Q]uick [S]witch' })

    vim.keymap.set('n', '<leader>ow', function()
      vim.cmd 'ObsidianWorkspace'
    end, { desc = '[O]bsidian [W]orkspace' })
  end,
}

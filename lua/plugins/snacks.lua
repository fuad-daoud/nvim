---@diagnostic disable: undefined-global
return {
  'folke/snacks.nvim',
  priority = 1000,
  lazy = false,
  opts = {
    bigfile = { enabled = true },
    quickfile = { enabled = true },
    dashboard = {
      preset = {
        header = [[
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⣰⣾⠁⠀⢦⣾⣤⠆⠀⠻⣧⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⢠⣼⠏⠀⠀⠀⠀⣿⡇⠀⠀⠀⠈⢷⣄⠀⠀⠀⠀
⠀⠀⢀⣸⣿⠃⠀⠀⠀⠀⠀⣿⡇⠀⠀⠀⠀⠀⢿⣧⡀⠀⠀
⠀⢰⣾⣿⡁⠀⠀⠀⠀⠀⠀⣿⡇⠀⠀⠀⠀⠀⢀⣿⣿⠖⠀
⠀⠀⠈⠻⣿⣦⣄⠀⠀⠀⠀⣿⡇⠀⠀⠀⢀⣴⣿⠟⠁⠀⠀
⠀⠀⠀⠀⠈⠻⢿⣷⣄⡀⠀⣿⡇⠀⣠⣾⣿⠟⠁⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⣦⣿⣧⣾⣿⠟⠁⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⢙⣿⣿⣿⣿⡀⠀⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⣿⣿⣿⣿⣦⡀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁⣻⣿⠈⠙⢿⣿⣦⡀⠀⠀⠀⠀
⠀⠀⠀⢀⣴⣿⡿⠋⠀⠀⠀⣽⣿⠀⠀⠀⠙⢿⣿⣦⣄⠀⠀
⠀⣠⣴⣿⡿⠋⠀⠀⠀⠀⠀⢼⣿⠀⠀⠀⠀⠀⠈⢻⣿⣷⣄
⠈⠙⢿⣿⣦⣄⠀⠀⠀⠀⠀⢸⣿⠀⠀⠀⠀⠀⣠⣾⣿⠟⠁
⠀⠀⠀⠙⢿⣿⣷⣄⠀⠀⠀⢸⣿⠀⠀⠀⣠⣾⣿⠟⠁⠀⠀
⠀⠀⠀⠀⠀⠙⢻⣿⣷⡄⠀⢸⣿⠀⠀⣼⣿⣿⠃⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠈⠻⢿⣿⣦⣸⣿⣠⣾⣿⠟⠁⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠈⠙⢿⣿⣿⣿⡿⠁⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⠿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀
]],
        keys = {
          { icon = ' ', key = 'r', desc = 'Recent Files', action = ":lua Snacks.dashboard.pick('oldfiles')" },
          { icon = '🏌️', key = 'l', desc = 'Golf Today', action = ':Golf Today' },
          { icon = '󰈙 ', key = 'n', desc = 'New File', action = ':ene | startinsert' },
          { icon = '󰈙 ', key = 'f', desc = 'File explorer', action = ':lua Snacks.explorer()' },
          { icon = '󰈙 ', key = 'p', desc = 'Projects', action = ':lua Snacks.picker.projects()' },
          { icon = '󰂺 ', key = 't', desc = 'Obsidian Today', action = ':ObsidianToday' },
          { icon = '󰂺 ', key = 'y', desc = 'Obsidian Yesterday', action = ':ObsidianYesterday' },
          { icon = '󰂺 ', key = 'g', desc = 'General Thoughts', action = ':edit ~/vaults/personal/general-thoughts.md' },
          { icon = ' ', key = 'c', desc = 'Config', action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.stdpath('config')})" },
          { icon = '󰒲 ', key = 'z', desc = 'Lazy', action = ':Lazy', enabled = package.loaded.lazy ~= nil },
          { icon = ' ', key = 'q', desc = 'Quit', action = ':qa' },
        },
      },
      sections = {
        { section = 'header' },
        { section = 'keys', padding = 2 },
        -- { section = "startup" },
      },
    },
    indent = {
      scope = {
        animate = {
          enabled = true,
        },
      },
    },
    lazygit = {},
    words = {},
    scroll = { enabled = false },
  },
  keys = {
    {
      '<leader>gg',
      function()
        Snacks.lazygit()
      end,
      desc = 'Lazygit',
    },
    {
      '<leader>gb',
      function()
        Snacks.git.blame_line()
      end,
      desc = 'Git Blame Line',
    },
    {
      '<leader>gf',
      function()
        Snacks.lazygit.log_file()
      end,
      desc = 'Lazygit Current File History',
    },
    {
      '<leader>gl',
      function()
        Snacks.lazygit.log()
      end,
      desc = 'Lazygit Log (cwd)',
    },
  },
  init = function()
    vim.keymap.set('n', '<leader>hb', function()
      vim.cmd 'silent! %bdelete'
      vim.cmd 'enew'
      vim.cmd 'lua Snacks.dashboard()'
      vim.cmd 'normal! \x1b'
    end, { desc = 'Return to Snacks Dashboard' })
    vim.api.nvim_create_autocmd('User', {
      pattern = 'VeryLazy',
      callback = function()
        Snacks.toggle.option('spell', { name = 'Spelling' }):map '\\s'
        Snacks.toggle.option('wrap', { name = 'Wrap' }):map '\\w'
        Snacks.toggle.option('cursorline', { name = 'Cursorline' }):map '\\c'
        Snacks.toggle.option('list', { name = 'List' }):map '\\l'
        Snacks.toggle.option('ignorecase', { name = 'Ignorecase' }):map '\\g'
        Snacks.toggle.option('relativenumber', { name = 'Relative Number' }):map '\\r'
        Snacks.toggle.diagnostics():map '\\d'
        Snacks.toggle.line_number():map '\\n'
        Snacks.toggle.option('conceallevel', { off = 0, on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2 }):map '\\-'
        Snacks.toggle.treesitter():map '\\/'
        Snacks.toggle.option('background', { off = 'light', on = 'dark', name = 'Dark Background' }):map '\\b'
        Snacks.toggle.inlay_hints():map '\\h'
        Snacks.toggle.indent():map '\\i'
        Snacks.toggle.zen():map '\\z'
        Snacks.toggle.words():map '\\o'
        Snacks.toggle({
          name = 'AutoPairs',
          get = function()
            return not vim.b.minipairs_disable
          end,
          set = function(enabled)
            vim.b.minipairs_disable = not enabled
          end,
        }):map '\\p'
        Snacks.toggle({
          name = 'Trails Removal',
          get = function()
            return vim.b.remove_trails_enabled ~= false
          end,
          set = function(enabled)
            vim.b.remove_trails_enabled = enabled
          end,
        }):map '\\T'
      end,
    })
  end,
}

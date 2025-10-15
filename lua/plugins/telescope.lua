return {
  {
    'nvim-telescope/telescope-file-browser.nvim',
    dependencies = { 'nvim-telescope/telescope.nvim', 'nvim-lua/plenary.nvim' },
  },
  {
    'nvim-telescope/telescope-project.nvim',
    dependencies = {
      'nvim-telescope/telescope.nvim',
    },
  },
  { -- Fuzzy Finder (files, lsp, etc)
    'nvim-telescope/telescope.nvim',
    event = 'VimEnter',
    branch = '0.1.x',
    dependencies = {
      'nvim-lua/plenary.nvim',
      {
        'nvim-telescope/telescope-fzf-native.nvim',
        build = 'make',
        cond = function()
          return vim.fn.executable 'make' == 1
        end,
      },
      { 'nvim-telescope/telescope-ui-select.nvim' },

      { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
    },
    config = function()
      require('telescope').setup {
        defaults = {
          layout_config = {
            horizontal = {
              height = 0.9,
              preview_cutoff = 180,
              prompt_position = 'bottom',
              width = 0.9,
            },
          },
          mappings = {
            i = { ['<c-enter>'] = 'to_fuzzy_refine' },
          },
        },
        extensions = {
          file_browser = {
            theme = 'ivy',
            hijack_netrw = false,
            mappings = {
              ['i'] = {
                -- your custom insert mode mappings
              },
              ['n'] = {
                -- your custom normal mode mappings
              },
            },
          },
          ['ui-select'] = {
            require('telescope.themes').get_dropdown(),
          },
          project = {
            display_type = 'full',
            base_dirs = {
              '~/projects/',
              '~/.config/nvim',
              '~/.config/sway',
              '~/.config/ghostty',
              '~/.config/waybar',
              '~/.config/rofi',
              '~/.config/clipse',
            },
            ignore_missing_dirs = true,
            theme = 'dropdown',
            order_by = 'asc',
            search_by = { 'title', 'path' },
            hidden_files = true,
            sync_with_nvim_tree = true,
            on_project_selected = function(prompt_bufnr)
              require('telescope._extensions.project.actions').change_working_directory(prompt_bufnr, false)
              vim.cmd.Ex {}
              local cwd = vim.fn.getcwd()
              local osc7_cwd = string.format('\027]7;file://%s%s\027\\', vim.fn.hostname(), cwd)
              io.write(osc7_cwd)
            end,
            i = {
              ['<c-d>'] = require('telescope._extensions.project.actions').delete_project,
              ['<c-v>'] = require('telescope._extensions.project.actions').rename_project,
              ['<c-a>'] = require('telescope._extensions.project.actions').add_project,
              ['<c-A>'] = require('telescope._extensions.project.actions').add_project_cwd,
              ['<c-f>'] = require('telescope._extensions.project.actions').find_project_files,
              ['<c-b>'] = require('telescope._extensions.project.actions').browse_project_files,
              ['<c-s>'] = require('telescope._extensions.project.actions').search_in_project_files,
              ['<c-r>'] = require('telescope._extensions.project.actions').recent_project_files,
              ['<c-l>'] = require('telescope._extensions.project.actions').change_working_directory,
              ['<c-o>'] = require('telescope._extensions.project.actions').next_cd_scope,
            },
          },
        },
      }

      pcall(require('telescope').load_extension, 'fzf')
      pcall(require('telescope').load_extension, 'ui-select')
      pcall(require('telescope').load_extension, 'file_browser')

      local builtin = require 'telescope.builtin'
      vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
      vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
      vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
      vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
      vim.keymap.set('n', '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
      vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
      vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
      vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
      vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
      vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })
      vim.keymap.set('n', '<C-p>', builtin.git_files, { desc = 'Search files not ignored by git' })
      vim.keymap.set('n', '<leader>pt', function()
        require('telescope').extensions.pomodori.timers()
      end, { desc = 'Manage Pomodori Timers' })
      vim.keymap.set('n', '<leader>sp', require('telescope').extensions.project.project, { desc = '[S]earch [P]rojects' })
      vim.keymap.set('n', '<leader>st', '<cmd>TodoTelescope<cr>', { desc = 'Search Todos' })
      vim.keymap.set('n', '<leader>/', function()
        builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 0,
          previewer = false,
          layout_config = {
            height = 0.6,
            preview_cutoff = 150,
            prompt_position = 'top',
            width = 0.7,
          },
        })
      end, { desc = '[/] Fuzzily search in current buffer' })

      vim.keymap.set('n', '<leader>s/', function()
        builtin.live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end, { desc = '[S]earch [/] in Open Files' })

      -- Shortcut for searching your Neovim configuration files
      vim.keymap.set('n', '<leader>sn', function()
        builtin.find_files { cwd = vim.fn.stdpath 'config' }
      end, { desc = '[S]earch [N]eovim files' })
      vim.keymap.set('n', '<space>fb', function()
        require('telescope').extensions.file_browser.file_browser()
      end)
    end,
  },
}

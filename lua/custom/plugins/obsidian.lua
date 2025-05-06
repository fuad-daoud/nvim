return {
  'epwalsh/obsidian.nvim',
  version = '*', -- recommended, use latest release instead of latest commit
  lazy = false,
  -- ft = 'markdown',
  -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
  -- event = {
  --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
  --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
  --   -- refer to `:h file-pattern` for more examples
  --   "BufReadPre path/to/my-vault/*.md",
  --   "BufNewFile path/to/my-vault/*.md",
  -- },
  dependencies = {
    'nvim-lua/plenary.nvim',

    -- see below for full list of optional dependencies 👇
  },
  opts = {
    workspaces = {
      {
        name = 'personal',
        path = '~/vaults/personal',
      },
    },
    -- see below for full list of options 👇
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
      vim.cmd 'ObsidianYesterday'
    end, { desc = '[O]bsidian [D]ailies' })

    vim.keymap.set('n', '<leader>os', function()
      vim.cmd 'ObsidianYesterday'
    end, { desc = '[O]bsidian [S]earch' })

    vim.keymap.set('n', '<leader>oc', function()
      -- Define all obsidian commands with descriptions
      local commands = {
        { name = 'ObsidianOpen', desc = 'Open note in Obsidian app' },
        { name = 'ObsidianNew', desc = 'Create a new note' },
        { name = 'ObsidianQuickSwitch', desc = 'Quickly switch to another note' },
        { name = 'ObsidianFollowLink', desc = 'Follow link under cursor' },
        { name = 'ObsidianBacklinks', desc = 'Show backlinks to current note' },
        { name = 'ObsidianToday', desc = "Open/create today's daily note" },
        { name = 'ObsidianYesterday', desc = "Open/create yesterday's daily note" },
        { name = 'ObsidianTomorrow', desc = "Open/create tomorrow's daily note" },
        { name = 'ObsidianTemplate', desc = 'Insert a template' },
        { name = 'ObsidianSearch', desc = 'Search notes by content' },
        { name = 'ObsidianPasteImg', desc = 'Paste image into vault' },
        { name = 'ObsidianWorkspace', desc = 'Switch workspace' },
        -- Add any other obsidian commands here
      }

      -- Create entries for telescope
      local entries = {}
      for _, cmd in ipairs(commands) do
        table.insert(entries, {
          ordinal = cmd.name,
          display = cmd.name .. ' - ' .. cmd.desc,
          command = cmd.name,
        })
      end

      -- Create and run the picker
      local pickers = require 'telescope.pickers'
      local finders = require 'telescope.finders'
      local conf = require('telescope.config').values
      local actions = require 'telescope.actions'
      local action_state = require 'telescope.actions.state'

      pickers
        .new({}, {
          prompt_title = 'Obsidian Commands',
          finder = finders.new_table {
            results = entries,
            entry_maker = function(entry)
              return {
                value = entry,
                display = entry.display,
                ordinal = entry.ordinal,
              }
            end,
          },
          sorter = conf.generic_sorter {},
          attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              vim.cmd(selection.value.command)
            end)
            return true
          end,
        })
        :find()
    end, { desc = '[O]bsidian [C]ommands' })
  end,
}

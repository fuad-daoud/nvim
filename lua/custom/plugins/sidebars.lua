-- local sidebar = {}

-- sidebar.sidebar = {
--   side = 'left',
--   -- open = vim.o.columns >= 150, --vim.fn.argc() ~= 0,
--   open = false,
--   section_separator = { ' ', ' ' },
--   sections = {
--     'git',
--     'datetime',
--     'files',
--     -- 'symbols',
--     'diagnostics',
--     'todos',
--     'containers',
--   },
--   datetime = {
--     icon = '󱛡',
--   },
-- }

local M = {
  'sidebar-nvim/sidebar.nvim',
  cmd = {
    'SidebarNvimOpen',
    'SidebarNvimToggle',
    'SidebarNvimFocus',
  },
  opts = function()
    return {
      side = 'left',
      -- open = vim.o.columns >= 150, --vim.fn.argc() ~= 0,
      open = false,
      section_separator = { ' ', ' ' },
      sections = {
        'git',
        'datetime',
        'files',
        -- 'symbols',
        'diagnostics',
        'todos',
        'containers',
      },
      datetime = {
        icon = '󱛡',
      },
    }
  end,
}
return M

-- sidebar.neotree = {
--   source_selector = {
--     winbar = false,
--   },
--   sources = {
--     'filesystem',
--     'buffers',
--     'git_status',
--     'diagnostics',
--   },
--   filesystem = {
--     hijack_netrw_behavior = 'disabled',
--   },
-- }

-- sidebar.aerial = {
--   layout = {
--     default_direction = 'left',
--     placement = 'edge',
--   },
--   attach_mode = 'global',
-- }

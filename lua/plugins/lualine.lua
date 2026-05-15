---@diagnostic disable: undefined-global
local function lsp_clients()
  local clients = vim.lsp.get_clients { bufnr = 0 }
  if #clients == 0 then
    return ''
  end
  local names = vim.tbl_map(function(c)
    return c.name
  end, clients)
  return ' ' .. table.concat(names, ' ')
end

local function noice_mode()
  return package.loaded['noice'] and require('noice').api.statusline.mode.get() or ''
end

local function noice_mode_cond()
  return package.loaded['noice'] and require('noice').api.statusline.mode.has() or false
end

return {
  'nvim-lualine/lualine.nvim',
  dependencies = { 'nvim-tree/nvim-web-devicons' },
  opts = {
    options = {
      theme = 'rose-pine',
      component_separators = { left = '', right = '' },
      section_separators = { left = '', right = '' },
      globalstatus = true,
      disabled_filetypes = {
        statusline = { 'dashboard', 'alpha' },
        winbar = {},
      },
    },
    sections = {
      lualine_a = { 'mode' },
      lualine_b = {
        'branch',
        {
          'diff',
          colored = true,
          symbols = { added = ' ', modified = ' ', removed = ' ' },
        },
        {
          'diagnostics',
          sources = { 'nvim_diagnostic' },
          symbols = { error = ' ', warn = ' ', info = ' ', hint = ' ' },
        },
      },
      lualine_c = {
        {
          'filename',
          path = 1,
          symbols = {
            modified = ' ●',
            readonly = ' ',
            unnamed = '[No Name]',
            newfile = '[New]',
          },
        },
        {
          noice_mode,
          cond = noice_mode_cond,
          color = { fg = '#eb6f92', gui = 'bold' }, -- rose-pine rose
        },
      },
      lualine_x = {
        { lsp_clients, color = { fg = '#9ccfd8' } }, -- rose-pine foam
        'filetype',
      },
      lualine_y = { 'searchcount', 'progress' },
      lualine_z = { 'location' },
    },
    inactive_sections = {
      lualine_a = {},
      lualine_b = {},
      lualine_c = { 'filename' },
      lualine_x = { 'location' },
      lualine_y = {},
      lualine_z = {},
    },
    extensions = {
      'toggleterm',
      'fugitive',
      'lazy',
    },
  },
}

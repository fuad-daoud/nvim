---@diagnostic disable: undefined-global
return {
  'akinsho/bufferline.nvim',
  version = '*',
  lazy = false,
  dependencies = 'nvim-tree/nvim-web-devicons',
  opts = {
    highlights = {
      -- transparent everywhere; only fg changes signal state
      fill = { bg = 'NONE' },
      background = { fg = '#6e6a86', bg = 'NONE', italic = false },
      buffer_visible = { fg = '#908caa', bg = 'NONE', italic = false },
      buffer_selected = { fg = '#e0def4', bg = 'NONE', bold = true, italic = false },
      tab = { fg = '#6e6a86', bg = 'NONE' },
      tab_selected = { fg = '#e0def4', bg = 'NONE', bold = true },
      tab_separator = { fg = '#393552', bg = 'NONE' },
      tab_separator_selected = { fg = '#393552', bg = 'NONE' },
      -- foam underline on the active tab
      indicator_selected = { fg = '#9ccfd8', bg = 'NONE' },
      -- unsaved: iris dot for inactive, foam for active
      modified = { fg = '#c4a7e7', bg = 'NONE' },
      modified_visible = { fg = '#c4a7e7', bg = 'NONE' },
      modified_selected = { fg = '#9ccfd8', bg = 'NONE' },
      -- thin dividers use overlay colour
      separator = { fg = '#393552', bg = 'NONE' },
      separator_selected = { fg = '#393552', bg = 'NONE' },
      separator_visible = { fg = '#393552', bg = 'NONE' },
      -- diagnostics
      error = { fg = '#eb6f92', bg = 'NONE' },
      error_selected = { fg = '#eb6f92', bg = 'NONE', bold = true },
      error_diagnostic = { fg = '#eb6f92', bg = 'NONE' },
      warning = { fg = '#f6c177', bg = 'NONE' },
      warning_selected = { fg = '#f6c177', bg = 'NONE', bold = true },
      warning_diagnostic = { fg = '#f6c177', bg = 'NONE' },
      info = { fg = '#9ccfd8', bg = 'NONE' },
      info_selected = { fg = '#9ccfd8', bg = 'NONE', bold = true },
      hint = { fg = '#c4a7e7', bg = 'NONE' },
      hint_selected = { fg = '#c4a7e7', bg = 'NONE', bold = true },
      diagnostic = { fg = '#6e6a86', bg = 'NONE' },
      diagnostic_selected = { fg = '#e0def4', bg = 'NONE' },
    },
    options = {
      mode = 'buffers',
      separator_style = 'thin',
      indicator = { style = 'underline' },
      show_buffer_close_icons = false,
      show_close_icon = false,
      modified_icon = '●',
      color_icons = true,
      diagnostics = 'nvim_lsp',
      diagnostics_indicator = function(count, level)
        local icons = { error = ' ', warning = ' ', info = ' ' }
        return (icons[level] or '') .. count
      end,
    },
  },
  keys = {
    { '<S-h>', '<cmd>BufferLineCyclePrev<cr>', desc = 'Prev buffer' },
    { '<S-l>', '<cmd>BufferLineCycleNext<cr>', desc = 'Next buffer' },
  },
}

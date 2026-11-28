---@diagnostic disable: undefined-global
return {
  'akinsho/bufferline.nvim',
  version = '*',
  lazy = false,
  dependencies = 'nvim-tree/nvim-web-devicons',
  opts = {
    -- The colours are the system's picked theme (lua/scripts/zen_theme.lua).
    -- A function, so they are read again whenever the colour scheme is set.
    highlights = function()
      local c = require('scripts.zen_theme').colors()
      return {
        -- transparent everywhere; only fg changes signal state
        fill = { bg = 'NONE' },
        background = { fg = c.muted, bg = 'NONE', italic = false },
        buffer_visible = { fg = c.subtle, bg = 'NONE', italic = false },
        buffer_selected = { fg = c.text, bg = 'NONE', bold = true, italic = false },
        tab = { fg = c.muted, bg = 'NONE' },
        tab_selected = { fg = c.text, bg = 'NONE', bold = true },
        tab_separator = { fg = c.overlay, bg = 'NONE' },
        tab_separator_selected = { fg = c.overlay, bg = 'NONE' },
        -- foam underline on the active tab
        indicator_selected = { fg = c.foam, bg = 'NONE' },
        -- unsaved: iris dot for inactive, foam for active
        modified = { fg = c.iris, bg = 'NONE' },
        modified_visible = { fg = c.iris, bg = 'NONE' },
        modified_selected = { fg = c.foam, bg = 'NONE' },
        -- thin dividers use overlay colour
        separator = { fg = c.overlay, bg = 'NONE' },
        separator_selected = { fg = c.overlay, bg = 'NONE' },
        separator_visible = { fg = c.overlay, bg = 'NONE' },
        -- diagnostics
        error = { fg = c.love, bg = 'NONE' },
        error_selected = { fg = c.love, bg = 'NONE', bold = true },
        error_diagnostic = { fg = c.love, bg = 'NONE' },
        warning = { fg = c.gold, bg = 'NONE' },
        warning_selected = { fg = c.gold, bg = 'NONE', bold = true },
        warning_diagnostic = { fg = c.gold, bg = 'NONE' },
        info = { fg = c.foam, bg = 'NONE' },
        info_selected = { fg = c.foam, bg = 'NONE', bold = true },
        hint = { fg = c.iris, bg = 'NONE' },
        hint_selected = { fg = c.iris, bg = 'NONE', bold = true },
        diagnostic = { fg = c.muted, bg = 'NONE' },
        diagnostic_selected = { fg = c.text, bg = 'NONE' },
      }
    end,
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

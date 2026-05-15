return {
  'folke/noice.nvim',
  event = 'VeryLazy',
  dependencies = { 'MunifTanjim/nui.nvim', 'rcarriga/nvim-notify' },
  opts = {
    lsp = {
      override = {
        ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
        ['vim.lsp.util.stylize_markdown'] = true,
      },
      hover = { enabled = true },
      signature = { enabled = false }, -- autocmd.lua handles this with CursorHoldI
      progress = { enabled = true },
    },
    routes = {
      { filter = { event = 'msg_show', kind = '', find = 'written' }, opts = { skip = true } },
      { filter = { event = 'msg_show', kind = '', find = 'search hit' }, opts = { skip = true } },
    },
    presets = {
      bottom_search = true,
      command_palette = true,
      long_message_to_split = true,
      lsp_doc_border = true,
    },
    views = {
      cmdline_popup = {
        position = { row = '78%', col = '50%' },
      },
      popupmenu = {
        relative = 'editor',
        position = { row = '78%', col = '50%' },
        size = { width = 60, height = 10 },
        border = { style = 'rounded', padding = { 0, 1 } },
      },
    },
  },
}

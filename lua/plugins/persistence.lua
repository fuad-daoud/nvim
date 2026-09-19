-- diffview://, pr-*:// and solve-companion:// buffers are scratch (no file behind them). If a session saves them they
-- come back as broken empty tabs and gopls floods `-32700 DocumentURI scheme is not 'file'`. Tear them down before
-- every save.
local function drop_review_buffers()
  local ok, lib = pcall(require, 'diffview.lib')
  if ok then
    local tabs = {}
    for _, view in ipairs(lib.views) do
      tabs[#tabs + 1] = view.tabpage
    end
    for _, tp in ipairs(tabs) do
      pcall(require('diffview').close, tp)
    end
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(b)
    if
      name:find '^diffview://'
      or name:find '^pr%-companion://'
      or name:find '^pr%-merge://'
      or name:find '^pr%-review%-summary://'
      or name:find '^solve%-companion://'
    then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

return {
  'folke/persistence.nvim',
  event = 'BufReadPre',
  opts = {},
  init = function()
    vim.api.nvim_create_autocmd('User', { pattern = 'PersistenceSavePre', callback = drop_review_buffers })
  end,
  keys = {
    {
      '<leader>rs',
      function()
        require('persistence').load()
      end,
      desc = 'Restore Session',
    },
    {
      '<leader>rls',
      function()
        require('persistence').load { last = true }
      end,
      desc = 'Restore Last Session',
    },
    {
      '<leader>ns',
      function()
        require('persistence').stop()
      end,
      desc = "Don't Save Current Session",
    },
  },
}

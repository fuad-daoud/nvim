vim.api.nvim_create_autocmd('TextYankPost', {
  desc = 'Highlight when yanking (copying) text',
  group = vim.api.nvim_create_augroup('highlight-yank', { clear = true }),
  callback = function()
    vim.highlight.on_yank()
  end,
})

vim.api.nvim_create_autocmd('User', {
  pattern = 'TelescopePreviewerLoaded',
  callback = function()
    vim.opt.number = true
  end,
})

vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('GoFormat', { clear = true }),
  pattern = '*.go',
  callback = function()
    vim.lsp.buf.code_action {
      context = { only = { 'source.organizeImports' } },
      apply = true,
    }
  end,
})
vim.api.nvim_create_autocmd('CursorHoldI', {
  group = vim.api.nvim_create_augroup('lsp-signature', { clear = true }),
  callback = function()
    vim.lsp.buf.signature_help()
  end,
})

vim.api.nvim_create_autocmd('BufWritePre', {
  group = vim.api.nvim_create_augroup('remove-trails', { clear = true }),
  callback = function()
    if vim.b.remove_trails_enabled ~= false then
      local save = vim.fn.winsaveview()
      vim.cmd [[%s/\s\+$//e]]
      vim.fn.winrestview(save)
    end
  end,
})

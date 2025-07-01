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

local obsidian_sync_group = vim.api.nvim_create_augroup('ObsidianSync', { clear = true })
local sync_script = '/home/fuad/.config/nvim/sync.sh'

vim.api.nvim_create_autocmd({ 'BufReadPost' }, {
  group = obsidian_sync_group,
  pattern = { '*.md', '*.markdown' }, -- Added specific patterns for markdown files
  callback = function()
    local file_path = vim.fn.expand '%:p'

    if string.match(file_path, '^' .. vim.fn.expand '~/vaults') then
      local old_statusline = vim.o.statusline
      vim.o.statusline = '%=%#WarningMsg# SYNCING OBSIDIAN... %#Normal#%='
      vim.cmd 'redraw'

      local result = vim.fn.system(sync_script)
      local exit_code = vim.v.shell_error

      vim.o.statusline = old_statusline
      vim.cmd 'redraw'

      if exit_code == 0 then
        vim.notify('Obsidian sync with Contabo completed successfully', vim.log.levels.INFO)
        local cursor_pos = vim.api.nvim_win_get_cursor(0)
        vim.cmd 'edit!'
        pcall(vim.api.nvim_win_set_cursor, 0, cursor_pos)
        vim.notify('Buffer refreshed with latest content', vim.log.levels.INFO)
      else
        vim.notify('Obsidian sync with Contabo failed with code: ' .. exit_code, vim.log.levels.ERROR)
        if result and result ~= '' then
          vim.notify('Error: ' .. result:gsub('%s+', ' '):sub(1, 100) .. (result:len() > 100 and '...' or ''), vim.log.levels.ERROR)
        end
      end
    end
  end,
  desc = 'Sync Obsidian files with Contabo before opening a file in ~/vaults',
})
vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
  group = obsidian_sync_group,
  pattern = { '*.md', '*.markdown' },
  callback = function()
    local file_path = vim.fn.expand '%:p'

    if string.match(file_path, '^' .. vim.fn.expand '~/vaults') then
      local old_statusline = vim.o.statusline
      vim.o.statusline = '%=%#WarningMsg# SYNCING OBSIDIAN... %#Normal#%='
      vim.cmd 'redraw'
      local result = vim.fn.system(sync_script)
      local exit_code = vim.v.shell_error
      vim.o.statusline = old_statusline
      vim.cmd 'redraw'
      if exit_code == 0 then
        vim.notify('Obsidian sync with Contabo completed successfully', vim.log.levels.INFO)
      else
        vim.notify('Obsidian sync with Contabo failed with code: ' .. exit_code, vim.log.levels.ERROR)
        -- Show condensed error details if there are any
        if result and result ~= '' then
          vim.notify('Error: ' .. result:gsub('%s+', ' '):sub(1, 100) .. (result:len() > 100 and '...' or ''), vim.log.levels.ERROR)
        end
      end
    end
  end,
  desc = 'Sync Obsidian files with Contabo after saving a file in ~/vaults',
})


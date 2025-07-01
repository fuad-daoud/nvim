local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not vim.uv.fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end ---@diagnostic disable-next-line: undefined-field
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  {
    'm4xshen/hardtime.nvim',
    lazy = false,
    dependencies = { 'MunifTanjim/nui.nvim' },
    opts = {},
  },
  {
    'm00qek/baleia.nvim',
    version = '*',
    config = function()
      vim.g.baleia = require('baleia').setup {}

      -- Command to colorize the current buffer
      vim.api.nvim_create_user_command('BaleiaColorize', function()
        vim.g.baleia.once(vim.api.nvim_get_current_buf())
      end, { bang = true })

      -- Command to show logs
      vim.api.nvim_create_user_command('BaleiaLogs', vim.g.baleia.logger.show, { bang = true })
    end,
  },
  'registerGen/clock.nvim',
  {
    'folke/todo-comments.nvim',
    dependencies = { 'nvim-lua/plenary.nvim' },
  },
  'tpope/vim-sleuth', -- Detect tabstop and shiftwidth automatically

  {
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        { path = 'luvit-meta/library', words = { 'vim%.uv' } },
      },
    },
  },
  { 'Bilal2453/luvit-meta', lazy = true },
  { -- Autoformat
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>f',
        function()
          local conform = require 'conform'

          conform.format { async = true, lsp_format = 'fallback' }
        end,
        mode = '',
        desc = '[F]ormat buffer',
      },
    },
    opts = {
      notify_on_error = false,
      format_on_save = function(bufnr)
        local disable_filetypes = { c = true, cpp = true }
        local lsp_format_opt

        if disable_filetypes[vim.bo[bufnr].filetype] then
          return nil
        else
          return {
            timeout_ms = 500,
            lsp_format = lsp_format_opt,
          }
        end
      end,
      -- formatters = {
      --   mix = {
      --     command = 'mix',
      --     args = { 'format', '-' },
      --     stdin = true,
      --   },
      -- },
      formatters_by_ft = {
        lua = { 'stylua' },
        css = { 'prettied', 'prettier' },
        graphql = { 'prettied', 'prettier' },
        html = { 'prettied', 'prettier' },
        javascript = { 'prettied', 'prettier' },
        javascriptreact = { 'prettied', 'prettier' },
        json = { 'prettied', 'prettier' },
        markdown = { 'prettied', 'prettier' },
        python = { 'isort', 'black' },
        sql = { 'sql-formatter' },
        svelte = { 'prettied', 'prettier' },
        typescript = { 'prettied', 'prettier', 'sql-formatter' },
        typescriptreact = { 'prettied', 'prettier' },
        yaml = { 'prettied' },
        elixir = { 'prettied' },
        -- elixir = { 'mix' },
        -- eelixir = { 'mix' },
        -- heex = { 'mix' },
      },
    },
  },
  { 'vuciv/golf' },
  { 'rcarriga/nvim-notify' },
  {
    'rose-pine/neovim',
    name = 'rose-pine',
    opts = {
      variant = 'moon',
      dark_variant = 'moon',
      dim_inactive_windows = true,
      extend_background_behind_borders = true,

      styles = {
        bold = true,
        italic = true,
        transparency = true,
      },
      highlight_groups = {
        Cursor = { fg = 'base', bg = 'rose' },
        LineNr = { fg = 'muted', bold = false },
        CursorLineNr = { fg = 'rose', bold = true },
        Search = { bg = 'gold', fg = 'base', bold = true },
        IncSearch = { bg = 'iris', fg = 'base', bold = true },
        Visual = { bg = 'highlight_med', blend = 10 },
        Comment = { fg = 'muted', italic = true },
        String = { fg = 'foam', italic = false },
        StatusLine = { fg = 'text', bg = 'surface' },
        StatusLineNC = { fg = 'subtle', bg = 'surface' },
      },
      groups = {

        border = 'muted',
        link = 'iris',
        panel = 'surface',

        error = 'love',
        hint = 'iris',
        info = 'foam',
        note = 'pine',
        todo = 'rose',
        warn = 'gold',

        git_add = 'foam',
        git_change = 'rose',
        git_delete = 'love',
        git_dirty = 'rose',
        git_ignore = 'muted',
        git_merge = 'iris',
        git_rename = 'pine',
        git_stage = 'iris',
        git_text = 'rose',
        git_untracked = 'subtle',

        h1 = 'iris',
        h2 = 'foam',
        h3 = 'rose',
        h4 = 'gold',
        h5 = 'pine',
        h6 = 'foam',
      },
      palette = {
        -- Override the builtin palette per variant
        moon = {
          rose = '#000000',
          overlay = '#363738',
        },
      },
    },
    config = function()
      vim.cmd 'colorscheme rose-pine'
    end,
  },
  {
    'catgoose/nvim-colorizer.lua',
    event = 'BufReadPre',
    opts = { -- set to setup table
    },
  },
  { import = 'plugins' },
}, {
  ui = {
    -- If you are using a Nerd Font: set icons to an empty table which will use the
    -- default lazy.nvim defined Nerd Font icons, otherwise define a unicode icons table
    icons = vim.g.have_nerd_font and {} or {
      cmd = '⌘',
      config = '🛠',
      event = '📅',
      ft = '📂',
      init = '⚙',
      keys = '🗝',
      plugin = '🔌',
      runtime = '💻',
      require = '🌙',
      source = '📄',
      start = '🚀',
      task = '📌',
      lazy = '💤 ',
    },
  },
})

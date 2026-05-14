return {
  {
    'mfussenegger/nvim-jdtls',
    ft = 'java',
    config = function()
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'java',
        callback = function()
          local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ':p:h:t')
          local workspace_dir = vim.fn.expand '~/.local/share/eclipse/' .. project_name

          require('jdtls').start_or_attach {
            cmd = { 'jdtls', '-data', workspace_dir },
            root_dir = vim.fs.root(0, { '.git', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'settings.gradle', 'settings.gradle.kts' }),
            capabilities = require('blink.cmp').get_lsp_capabilities(),
          }
        end,
      })
    end,
  },
}

return {
  {
    'neovim/nvim-lspconfig',
    dependencies = {
      { 'j-hui/fidget.nvim', opts = {} },
    },
    config = function()
      require('lspconfig.ui.windows').default_options = { border = 'rounded' }

      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
        callback = function(event)
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          map('gd', require('telescope.builtin').lsp_definitions, '[G]oto [D]efinition')
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
          map('gi', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')
          map('<leader>gd', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
          map('gt', require('telescope.builtin').lsp_type_definitions, '[G]oto T[y]pe Definition')
          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
          map('<leader>h', vim.lsp.buf.hover, '[H]over')

          map('<leader>pd', function()
            vim.diagnostic.jump { count = -1 }
          end, 'Previous [D]iagnostic')
          map('<leader>nd', function()
            vim.diagnostic.jump { count = 1 }
          end, 'Next [D]iagnostic')
          map('<leader>e', function()
            vim.diagnostic.open_float(nil, { focus = true, scope = 'cursor' })
          end, 'Show diagnostic [E]rror')

          local client = vim.lsp.get_client_by_id(event.data.client_id)

          ---@diagnostic disable-next-line: param-type-mismatch
          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight, { bufnr = event.buf }) then
            local highlight_augroup = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })
            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })
          end

          ---@diagnostic disable-next-line: param-type-mismatch
          if client and client.supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint, { bufnr = event.buf }) then
            vim.lsp.inlay_hint.enable(true, { bufnr = event.buf })
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end
        end,
      })

      local capabilities = require('blink.cmp').get_lsp_capabilities()

      local servers = {
        lua_ls = {
          settings = {
            Lua = {
              completion = { callSnippet = 'Replace' },
              diagnostics = { disable = { 'missing-fields' } },
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
        gopls = {
          settings = {
            gopls = {
              analyses = { unusedparams = true, shadow = true },
              staticcheck = true,
              gofumpt = true,
            },
          },
        },
        zls = {},
        tailwindcss = {},
        html = {},
        cssls = {},
        jsonls = {},
        yamlls = {},
        bashls = {},
      }

      for server, config in pairs(servers) do
        config.capabilities = capabilities
        require('lspconfig')[server].setup(config)
      end

      vim.diagnostic.config {
        virtual_text = {
          prefix = '●',
          spacing = 4,
          source = 'if_many',
        },
        update_in_insert = false,
        virtual_lines = false,
        severity_sort = true,
        float = {
          border = 'rounded',
          source = true,
          header = 'Diagnostics',
          prefix = '● ',
          focusable = true,
        },
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = '✘',
            [vim.diagnostic.severity.WARN] = '▲',
            [vim.diagnostic.severity.HINT] = '⚑',
            [vim.diagnostic.severity.INFO] = '»',
          },
        },
      }

      -- Auto-show diagnostics in floating window on cursor hold
      vim.api.nvim_create_autocmd('CursorHold', {
        group = vim.api.nvim_create_augroup('float-diagnostic', { clear = true }),
        callback = function()
          vim.diagnostic.open_float(nil, { focus = false, scope = 'cursor' })
        end,
      })
    end,
  },
}

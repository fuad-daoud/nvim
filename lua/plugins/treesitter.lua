return {
  { -- Highlight, edit, and navigate code
    'nvim-treesitter/nvim-treesitter',
    build = ':TSUpdate',
    opts = {
      ensure_installed = {
        'bash',
        'c',
        'diff',
        'html',
        'lua',
        'luadoc',
        'markdown',
        'markdown_inline',
        'query',
        'vim',
        'vimdoc',
        'go',
        'rust',
        'zig',
        'dockerfile',
      },
      -- Autoinstall languages that are not installed
      auto_install = true,
      highlight = {
        enable = true,
        -- Some languages depend on vim's regex highlighting system (such as Ruby) for indent rules.
        --  If you are experiencing weird indenting issues, add the language to
        --  the list of additional_vim_regex_highlighting and disabled languages for indent.
        additional_vim_regex_highlighting = { 'markdown' },
      },
      indent = { enable = true, disable = { 'ruby' } },
    },
    config = function(_, opts)
      ---@diagnostic disable-next-line: missing-fields
      require('nvim-treesitter.configs').setup(opts)

      -- nvim-treesitter is archived and its set-lang-from-info-string! directive assumes
      -- match[id] is a bare TSNode, but Neovim 0.11+ passes (TSNode|nil)[] — patch it.
      vim.treesitter.query.add_directive('set-lang-from-info-string!', function(match, _, bufnr, pred, metadata)
        local nodes = match[pred[2]]
        local node = type(nodes) == 'table' and nodes[1] or nodes
        if not node then
          return
        end
        local text = vim.treesitter.get_node_text(node, bufnr)
        if text then
          metadata['injection.language'] = text:lower()
        end
      end, { force = true })

      local parser_config = require('nvim-treesitter.parsers').get_parser_configs()
      parser_config.templ = {
        install_info = {
          url = 'https://github.com/virschmann/tree-sitter-templ.git',
          files = { 'src/parser.c', 'src/scanner.c' },
          branch = 'master',
        },
      }
      vim.treesitter.language.register('templ', 'templ')
    end,
  },
}

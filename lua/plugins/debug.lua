return {
  'mfussenegger/nvim-dap',
  dependencies = {
    'rcarriga/nvim-dap-ui',
    'nvim-neotest/nvim-nio',
    'leoluz/nvim-dap-go',
  },
  keys = function(_, keys)
    local dap = require 'dap'
    local dapui = require 'dapui'
    return {
      { '<F5>', dap.continue, desc = 'Debug: Start/Continue' },
      { '<F1>', dap.step_into, desc = 'Debug: Step Into' },
      { '<F2>', dap.step_over, desc = 'Debug: Step Over' },
      { '<F3>', dap.step_out, desc = 'Debug: Step Out' },
      { '<leader>b', dap.toggle_breakpoint, desc = 'Debug: Toggle Breakpoint' },
      {
        '<leader>B',
        function()
          dap.set_breakpoint(vim.fn.input 'Breakpoint condition: ')
        end,
        desc = 'Debug: Set Breakpoint',
      },
      { '<F7>', dapui.toggle, desc = 'Debug: See last session result.' },
      { '<leader>dr', dap.restart, desc = 'Debug: [R]estart' },
      { '<leader>dt', dap.terminate, desc = 'Debug: [T]erminate' },
      {
        '<leader>dh',
        function()
          require('dap.ui.widgets').hover()
        end,
        desc = 'Debug: Hover [H]',
      },
      {
        '<leader>dk',
        function()
          local widgets = require 'dap.ui.widgets'
          widgets.centered_float(widgets.scopes)
        end,
        desc = 'Debug: Show Scopes [K]',
      },
      {
        '<leader>dp',
        function()
          require('dap.ui.widgets').preview()
        end,
        desc = 'Debug: [P]review value',
      },
      {
        '<leader>da',
        function()
          require('dap').run {
            type = 'delve',
            name = 'Attach to dlv',
            mode = 'remote',
            request = 'attach',
            substitutePath = {
              { from = '${workspaceFolder}', to = vim.fn.getcwd() },
            },
          }
        end,
        desc = 'Debug: [A]ttach to dlv',
      },
      unpack(keys),
    }
  end,
  config = function()
    local dap = require 'dap'
    local dapui = require 'dapui'
    dap.set_log_level 'WARN'

    -- Define breakpoint signs with line highlighting
    vim.fn.sign_define('DapBreakpoint', {
      text = '●',
      texthl = 'DapBreakpoint',
      linehl = 'DapBreakpointLine', -- Highlight entire line
      numhl = 'DapBreakpoint', -- Also highlight line number
    })

    vim.fn.sign_define('DapBreakpointCondition', {
      text = '◆',
      texthl = 'DapBreakpoint',
      linehl = 'DapBreakpointLine',
      numhl = 'DapBreakpoint',
    })

    vim.fn.sign_define('DapStopped', {
      text = '→',
      texthl = 'DapStopped',
      linehl = 'DapStoppedLine',
      numhl = 'DapStopped',
    })
    vim.fn.sign_define('DapBreakpointRejected', {
      text = '○',
      texthl = 'DapBreakpointRejected',
      linehl = '',
      numhl = '',
    })
    local rose_pine = require 'rose-pine.palette'

    vim.api.nvim_set_hl(0, 'DapBreakpoint', { fg = rose_pine.love })
    vim.api.nvim_set_hl(0, 'DapBreakpointRejected', { fg = rose_pine.muted })
    vim.api.nvim_set_hl(0, 'DapStopped', { fg = rose_pine.foam })
    vim.api.nvim_set_hl(0, 'DapStoppedLine', { bg = rose_pine.highlight_med, bold = true })
    vim.api.nvim_set_hl(0, 'DapBreakpointLine', { bg = '#5e3548' }) -- Subtle rose-pine overlay

    dapui.setup {
      icons = { expanded = '▾', collapsed = '▸', current_frame = '*' },
      mappings = {
        expand = { '<CR>' },
        open = 'o',
        remove = 'd',
        edit = 'e',
        repl = 'r',
        toggle = 't',
      },
      layouts = {
        {
          elements = {
            { id = 'scopes', size = 0.75 },
            { id = 'breakpoints', size = 0.25 },
          },
          size = 15,
          position = 'bottom',
        },
      },
      floating = {
        border = 'rounded',
        mappings = {
          close = { 'q', '<Esc>' },
        },
      },
    }

    dap.listeners.after.event_initialized['dapui_config'] = dapui.open
    dap.listeners.before.event_terminated['dapui_config'] = dapui.close
    dap.listeners.before.event_exited['dapui_config'] = dapui.close

    require('dap-go').setup {
      delve = {
        detached = vim.fn.has 'win32' == 0,
      },
    }
    dap.adapters.delve = {
      type = 'server',
      host = '127.0.0.1',
      port = 2345,
    }
  end,
}

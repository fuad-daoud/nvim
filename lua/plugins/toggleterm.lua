return {
  'akinsho/toggleterm.nvim',
  version = '*',
  opts = {
    size = function(term)
      if term.direction == 'horizontal' then
        return 15
      elseif term.direction == 'vertical' then
        return vim.o.columns * 0.4
      end
    end,
    open_mapping = [[<c-\>]],
    hide_numbers = true,
    shade_terminals = false,
    start_in_insert = true,
    direction = 'float',
    float_opts = {
      border = 'single',
      width = vim.o.columns - 10,
      height = vim.o.lines - 5,
    },
    close_on_exit = true,
  },
  config = function(_, opts)
    require('toggleterm').setup(opts)
    vim.keymap.set('n', '<leader>tt', '<cmd>ToggleTerm direction=horizontal<CR>', { desc = 'Toggle Terminal (Horizontal)' })
    vim.keymap.set('n', '<leader>tv', '<cmd>ToggleTerm direction=vertical<CR>', { desc = 'Toggle Terminal (Vertical)' })
    vim.keymap.set('n', '<leader>tf', function()
      local term_width = vim.o.columns - 30
      local term_height = vim.o.lines - 15

      vim.cmd(string.format('ToggleTerm size=%d direction=float', term_height))

      local term_buf = vim.api.nvim_get_current_buf()

      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == term_buf then
          vim.api.nvim_win_set_config(win, {
            relative = 'editor',
            width = term_width,
            height = term_height,
            row = 5,
            col = 12,
          })
          break
        end
      end
    end, { desc = 'Toggle Large Terminal' })

    vim.api.nvim_set_keymap('t', '<A-h>', '<C-\\><C-n><C-w>h', { noremap = true, desc = 'Move to window left from terminal' })
    vim.api.nvim_set_keymap('t', '<A-j>', '<C-\\><C-n><C-w>j', { noremap = true, desc = 'Move to window below from terminal' })
    vim.api.nvim_set_keymap('t', '<A-k>', '<C-\\><C-n><C-w>k', { noremap = true, desc = 'Move to window above from terminal' })
    vim.api.nvim_set_keymap('t', '<A-l>', '<C-\\><C-n><C-w>l', { noremap = true, desc = 'Move to window right from terminal' })

    vim.api.nvim_set_keymap('n', '<A-h>', '<C-w>h', { noremap = true, desc = 'Move to window left' })
    vim.api.nvim_set_keymap('n', '<A-j>', '<C-w>j', { noremap = true, desc = 'Move to window below' })
    vim.api.nvim_set_keymap('n', '<A-k>', '<C-w>k', { noremap = true, desc = 'Move to window above' })
    vim.api.nvim_set_keymap('n', '<A-l>', '<C-w>l', { noremap = true, desc = 'Move to window right' })
  end,
}

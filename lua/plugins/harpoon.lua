return {
  'ThePrimeagen/harpoon',
  config = function()
    vim.keymap.set('n', '<leader>ha', require('harpoon.mark').add_file)

    local harpoon_ui = require 'harpoon.ui'

    vim.keymap.set('n', '<leader>he', harpoon_ui.toggle_quick_menu)
    for number = 1, 6 do
      vim.keymap.set('n', '<leader>' .. number, function()
        harpoon_ui.nav_file(number)
      end)
    end

    vim.keymap.set('n', '<leader>hp', harpoon_ui.nav_prev)

    vim.keymap.set('n', '<leader>hn', harpoon_ui.nav_next)
  end,
}

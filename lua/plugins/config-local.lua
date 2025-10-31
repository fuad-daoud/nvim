return {
  'klen/nvim-config-local',
  config = function()
    require('config-local').setup {
      config_files = { '.nvim.lua', '.nvimrc' },
      hashfile = vim.fn.stdpath 'data' .. '/config-local',
    }
  end,
}

-- The editor wears the system's theme.
--
-- ~/.dotfiles/build-configs.go writes the picked theme's colours to
-- ~/.config/look/nvim-palette.lua, under the names the Rosé Pine plugin uses.
-- apply() hands them to the plugin as its palette and sets the colour scheme
-- again. It runs once at start (lua/scripts/lazy.lua) and again whenever
-- ~/.local/bin/theme-sync asks every open Neovim to, after a theme is picked
-- in the Settings menu. Without that file (another machine, a first start)
-- the plugin's own Rosé Pine is used, as before.
local M = {}

M.path = vim.env.ZEN_NVIM_PALETTE or vim.fn.expand '~/.config/look/nvim-palette.lua'

-- The colours from the file, or nil when it is missing or not a table of them.
function M.palette()
  local ok, p = pcall(dofile, M.path)
  if ok and type(p) == 'table' and type(p.base) == 'string' then
    return p
  end
  return nil
end

function M.apply()
  local p = M.palette()
  -- The same colours for both dark variants: whichever the plugin picks, it is the system's theme.
  require('rose-pine').setup { palette = p and { main = p, moon = p } or {} }
  -- The status line's theme keeps the colours it read when it was first loaded.
  package.loaded['lualine.themes.rose-pine'] = nil
  vim.cmd.colorscheme 'rose-pine'
  if package.loaded['lualine'] then
    pcall(function()
      require('lualine').setup(require('lualine').get_config())
    end)
  end
  return p ~= nil
end

return M

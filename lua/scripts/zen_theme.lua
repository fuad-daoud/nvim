-- The editor wears the system's theme.
--
-- ~/.dotfiles/build-configs.go writes the picked theme's colours to
-- ~/.config/look/nvim-palette.lua, under the names the Rosé Pine plugin uses.
-- apply() hands them to the plugin as its palette, tells the editor whether
-- the theme is light or dark, and sets the colour scheme again. It runs once at start (lua/scripts/lazy.lua) and again whenever
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

-- Rosé Pine's own colours, used where the system's file is missing.
M.rose_pine = {
  base = '#191724',
  surface = '#1f1d2e',
  overlay = '#26233a',
  muted = '#6e6a86',
  subtle = '#908caa',
  text = '#e0def4',
  love = '#eb6f92',
  gold = '#f6c177',
  rose = '#ea9a97',
  pine = '#3e8fb0',
  foam = '#9ccfd8',
  iris = '#c4a7e7',
  leaf = '#b3cfa1',
  highlight_low = '#2a283e',
  highlight_med = '#44415a',
  highlight_high = '#56526e',
}

-- The picked theme's colours by name, for the parts of the editor that set
-- their own (the buffer line, the status line): every name always has a value.
function M.colors()
  local p = M.palette() or {}
  local c = {}
  for name, own in pairs(M.rose_pine) do
    c[name] = type(p[name]) == 'string' and p[name] or own
  end
  return c
end

function M.apply()
  local p = M.palette()
  local light = false
  if p then
    light = p._mode == 'light'
    p._mode = nil
  end
  -- The same colours for every variant: whichever the plugin picks, it is the system's theme.
  require('rose-pine').setup { palette = p and { main = p, moon = p, dawn = p } or {} }
  if p then
    -- A light theme needs the editor to know its background is light: the plugin
    -- picks its light variant from this, and other plugins read it too.
    vim.o.background = light and 'light' or 'dark'
  end
  -- The status line's theme keeps the colours it read when it was first loaded.
  package.loaded['lualine.themes.rose-pine'] = nil
  vim.cmd.colorscheme 'rose-pine'
  -- The terminal inside the editor wears the same sixteen colours as the one outside
  -- (set after the colour scheme, which sets its own).
  local c = M.colors()
  for i, colour in ipairs { c.overlay, c.love, c.leaf, c.gold, c.pine, c.iris, c.foam, c.text } do
    vim.g['terminal_color_' .. (i - 1)] = colour
    vim.g['terminal_color_' .. (i + 7)] = colour
  end
  vim.g.terminal_color_8 = c.muted
  if package.loaded['lualine'] then
    pcall(function()
      require('lualine').setup(require('lualine').get_config())
    end)
  end
  return p ~= nil
end

return M

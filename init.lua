-- luarocks (lua 5.1 / LuaJIT) — needed for magick (image.nvim)
package.path = package.path .. ';' .. vim.fn.expand '~/.luarocks/share/lua/5.1/?.lua'
package.path = package.path .. ';' .. vim.fn.expand '~/.luarocks/share/lua/5.1/?/init.lua'
package.cpath = package.cpath .. ';' .. vim.fn.expand '~/.luarocks/lib/lua/5.1/?.so'

require 'scripts.setup'
require 'scripts.lazy'

require 'scripts.autocmd'
require 'scripts.keymaps'
require 'scripts.opt'

-- need to install these in order for it to work on fresh machines have script that does that for you
-- pacman -S git neovim npm unzip go zig

# Core LSPs
sudo pacman -S lua-language-server gopls clang yaml-language-server bash-language-server

# AUR LSPs
yay -S zls tailwindcss-language-server

# Python (LSP + formatter/linter for leetcode.nvim and plain .py files)
sudo pacman -S pyright ruff

# Formatters/Linters
sudo pacman -S prettier stylua shfmt shellcheck yamllint
yay -S prettierd actionlint jq

# Markdown / image rendering (for mermaid diagrams via image.nvim)
sudo pacman -S luarocks lua51 imagemagick  # lua51 is required for --lua-version 5.1
luarocks --lua-version 5.1 install magick --local  # LuaJIT-compatible binding
npm install -g --allow-scripts=puppeteer @mermaid-js/mermaid-cli  # postinstall downloads Chromium

# Go tools
go install golang.org/x/tools/cmd/goimports@latest
go install github.com/segmentio/golines@latest
go install github.com/fatih/gomodifytags@latest
go install github.com/go-delve/delve/cmd/dlv@latest

# Templ
go install github.com/a-h/templ/cmd/templ@latest



yay -S delv

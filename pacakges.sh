# Core LSPs
sudo pacman -S lua-language-server gopls clang yaml-language-server bash-language-server

# AUR LSPs
yay -S zls tailwindcss-language-server

# Formatters/Linters
sudo pacman -S prettier stylua shfmt shellcheck yamllint
yay -S prettierd actionlint jq

# Go tools
go install golang.org/x/tools/cmd/goimports@latest
go install github.com/segmentio/golines@latest
go install github.com/fatih/gomodifytags@latest
go install github.com/go-delve/delve/cmd/dlv@latest

# Templ
go install github.com/a-h/templ/cmd/templ@latest

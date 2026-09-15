# shellcheck shell=bash
# Arch base layer: everything that comes from pacman/yay. Tools shared with
# Ubuntu (go install / npm -g / luarocks) live in shared.sh.

log 'arch: pacman packages'
# nodejs is deliberately absent here: npm depends on a nodejs provider, so it
# pulls one in on a fresh machine, and any provider already installed (e.g.
# nodejs-lts-*) satisfies that dependency. An explicit `nodejs` conflicts with
# the LTS packages and aborts the whole transaction under --noconfirm.
sudo pacman -S --needed --noconfirm \
  git curl unzip base-devel \
  ripgrep fd fzf jq shellcheck yamllint \
  clang imagemagick luarocks lua51 \
  github-cli lazygit \
  neovim go zig npm \
  stylua lua-language-server

if ! have zls; then
  have yay || die 'yay is required to install zls from the AUR'
  log 'arch: aur packages'
  yay -S --needed --noconfirm zls
fi

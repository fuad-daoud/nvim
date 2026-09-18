# shellcheck shell=bash
# Arch base layer: everything that comes from pacman. Tools shared with Ubuntu
# (go install / npm -g / luarocks / zls release tarball) live in shared.sh.

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
  neovim go zig npm python \
  stylua lua-language-server

# zls must match zig's minor and the AUR package lags behind zig, so shared.sh
# installs the matching GitHub release into /usr/local/bin, which precedes
# /usr/bin on PATH and therefore shadows a leftover AUR build.
if pacman -Q zls >/dev/null 2>&1; then
  warn 'AUR zls is installed but lags zig; zls now comes from GitHub releases — remove it with: yay -Rns zls'
fi

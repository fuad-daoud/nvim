# shellcheck shell=bash
# Single source of truth for pinned versions and the binaries the config needs.

NVIM_VERSION=0.12.5
GO_VERSION=1.27.0
export ZIG_VERSION=0.16.0
export ZLS_VERSION=0.16.0 # must match ZIG_VERSION's minor
export LUA_LS_VERSION=3.19.1
export STYLUA_VERSION=2.5.2
export LAZYGIT_VERSION=0.65.1
export RUFF_VERSION=0.16.8
NODE_MAJOR=22

# Everything that must be on PATH for the config to work. Checked by
# `install.sh --check`; see the spec for which plugin needs each one.
declare -ax REQUIRED_BINS=(
  # core / lazy.nvim / native builds
  nvim git unzip curl make cc
  # pickers, git tooling
  rg fd fzf gh lazygit
  # go
  go gopls goimports golines gomodifytags dlv templ
  # zig / lua / c
  zig zls lua-language-server stylua clangd
  # node + npm-installed LSPs and formatters
  node npm yaml-language-server bash-language-server tailwindcss-language-server prettier prettierd
  # typescript / react (vscode-langservers-extracted provides the eslint/html/css/json servers)
  vtsls tsc vscode-eslint-language-server vscode-html-language-server vscode-css-language-server vscode-json-language-server
  # python
  python3 pyright-langserver ruff
  # linters / formatters
  shfmt shellcheck yamllint actionlint jq
  # markdown rendering
  luarocks mmdc
)

# Binaries that also have a minimum version (checked with bin_version).
declare -Ax MIN_VERSION=(
  [nvim]="$NVIM_VERSION"
  [go]="$GO_VERSION"
  [node]="$NODE_MAJOR.0.0"
  [zig]="$ZIG_VERSION"
  [zls]="$ZLS_VERSION"
)

export MAGICK_ROCK="$HOME/.luarocks/share/lua/5.1/magick"

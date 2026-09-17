# shellcheck shell=bash
# Ubuntu (22.04+) base layer. apt for what it ships fresh enough, NodeSource for
# node, GitHub's repo for gh, and pinned release tarballs under /opt for the rest.

export DEBIAN_FRONTEND=noninteractive

# Per-tool naming of the CPU architecture in release asset URLs.
case "$ARCH" in
  x86_64) GOARCH=amd64 NVIM_ARCH=x86_64 LUALS_ARCH=x64 LAZYGIT_ARCH=x86_64 ;;
  aarch64) GOARCH=arm64 NVIM_ARCH=arm64 LUALS_ARCH=arm64 LAZYGIT_ARCH=arm64 ;;
esac

log 'ubuntu: apt packages'
sudo apt-get update -qq
sudo apt-get install -y -qq \
  git curl unzip build-essential ca-certificates gnupg \
  ripgrep fd-find fzf jq shellcheck yamllint \
  clangd imagemagick libmagickwand-dev \
  luarocks lua5.1 liblua5.1-dev
# Ubuntu ships fd as fdfind
have fd || sudo ln -sfn "$(command -v fdfind)" /usr/local/bin/fd

if ! have gh; then
  log 'ubuntu: gh (GitHub apt repo)'
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg |
    sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" |
    sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y -qq gh
fi

if ! have_version node "$NODE_MAJOR.0.0"; then
  log "ubuntu: node $NODE_MAJOR (NodeSource)"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
  sudo apt-get install -y -qq nodejs
fi

if ! have_version nvim "$NVIM_VERSION"; then
  install_release nvim \
    "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz" \
    1 bin/nvim
fi

if ! have_version go "$GO_VERSION"; then
  log "installing go $GO_VERSION to /usr/local/go"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/go.tgz" "https://go.dev/dl/go${GO_VERSION}.linux-${GOARCH}.tar.gz"
  tar -tzf "$tmp/go.tgz" >/dev/null
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$tmp/go.tgz"
  sudo ln -sfn /usr/local/go/bin/go /usr/local/bin/go
  sudo ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -rf "$tmp"
fi

if ! have_version zig "$ZIG_VERSION"; then
  install_release zig \
    "https://ziglang.org/download/${ZIG_VERSION}/zig-${ARCH}-linux-${ZIG_VERSION}.tar.xz" \
    1 zig
fi

if ! have_version zls "$ZLS_VERSION"; then
  install_release zls \
    "https://github.com/zigtools/zls/releases/download/${ZLS_VERSION}/zls-${ARCH}-linux.tar.xz" \
    0 zls
fi

if ! have_version lua-language-server "$LUA_LS_VERSION"; then
  install_release lua-language-server \
    "https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-linux-${LUALS_ARCH}.tar.gz" \
    0 bin/lua-language-server
fi

if ! have_version stylua "$STYLUA_VERSION"; then
  install_release stylua \
    "https://github.com/JohnnyMorganz/StyLua/releases/download/v${STYLUA_VERSION}/stylua-linux-${ARCH}.zip" \
    0 stylua
fi

if ! have_version lazygit "$LAZYGIT_VERSION"; then
  install_release lazygit \
    "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_${LAZYGIT_ARCH}.tar.gz" \
    0 lazygit
fi

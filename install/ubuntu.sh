# shellcheck shell=bash
# Ubuntu (22.04+) base layer. apt for what it ships fresh enough, NodeSource for
# node, GitHub's repo for gh, and pinned release tarballs under /opt for the rest.

export DEBIAN_FRONTEND=noninteractive

# Per-tool naming of the CPU architecture in release asset URLs.
case "$ARCH" in
  x86_64) GOARCH=amd64 NVIM_ARCH=x86_64 LUALS_ARCH=x64 LAZYGIT_ARCH=x86_64 ;;
  aarch64) GOARCH=arm64 NVIM_ARCH=arm64 LUALS_ARCH=arm64 LAZYGIT_ARCH=arm64 ;;
esac

# apt_name <var> <candidate>... -> sets <var> to the first name apt can install.
# Ubuntu 24.04 renamed several libraries with a t64 suffix and dropped the old
# names, so the headless-chrome deps below are looked up per release. Sets a
# variable rather than printing so that die() aborts the script (it would only
# leave a command substitution). Captures apt-cache output instead of piping into
# grep -q: under pipefail an early grep exit would fail the pipeline.
apt_name() {
  local var=$1 n out
  shift
  for n in "$@"; do
    out=$(apt-cache policy "$n" 2>/dev/null)
    case "$out" in
      *'Candidate: '[0-9]*)
        printf -v "$var" '%s' "$n"
        return
        ;;
    esac
  done
  die "apt: none of these packages is available: $*"
}

log 'ubuntu: apt packages'
sudo apt-get update -qq
apt_name ASOUND libasound2t64 libasound2
apt_name ATK libatk1.0-0t64 libatk1.0-0
apt_name ATK_BRIDGE libatk-bridge2.0-0t64 libatk-bridge2.0-0
apt_name CUPS libcups2t64 libcups2
# The last three lines are the runtime deps of puppeteer's headless chrome, which
# mmdc uses to render diagrams (see ensure_mmdc_browser in shared.sh).
sudo apt-get install -y -qq \
  git curl unzip build-essential ca-certificates gnupg \
  ripgrep fd-find fzf jq shellcheck yamllint \
  clangd imagemagick libmagickwand-dev \
  luarocks lua5.1 liblua5.1-dev python3 \
  fonts-liberation libnss3 libdrm2 libxkbcommon0 libxcomposite1 libxdamage1 \
  libxfixes3 libxrandr2 libgbm1 libpango-1.0-0 libcairo2 \
  "$ASOUND" "$ATK" "$ATK_BRIDGE" "$CUPS"
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

if ! have_version node "$NODE_MAJOR.0.0" || ! have npm; then
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
  tmp=$(mktemp -d -p "$INSTALL_TMP")
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

if ! have_version lua-language-server "$LUA_LS_VERSION"; then
  install_release lua-language-server \
    "https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-linux-${LUALS_ARCH}.tar.gz" \
    0 bin/lua-language-server
  # LuaLS defaults --metapath/--logpath to <root>/meta and <root>/log; a user can't
  # create those under root-owned /opt, and LuaLS then silently skips loading its
  # builtin (stdlib) definitions. Replace the symlink with a wrapper that points
  # both at the user's cache, like Arch's /usr/bin/lua-language-server does.
  # rm first: tee on the symlink would overwrite the real binary in /opt.
  sudo rm -f /usr/local/bin/lua-language-server
  sudo tee /usr/local/bin/lua-language-server >/dev/null <<'EOF'
#!/usr/bin/env sh
# LuaLS writes meta/log next to its binary by default; /opt is root-owned, so point them at the user's cache.
cache="${XDG_CACHE_HOME:-$HOME/.cache}/lua-language-server"
mkdir -p "$cache/log" "$cache/meta"
exec /opt/lua-language-server/bin/lua-language-server --logpath="$cache/log" --metapath="$cache/meta" "$@"
EOF
  sudo chmod +x /usr/local/bin/lua-language-server
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

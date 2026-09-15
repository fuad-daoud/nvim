# Cross-distro Install Script Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Arch-only `pacakges.sh` with an idempotent `install.sh` that brings Arch and Ubuntu (22.04+) to identical tool parity and has a `--check` mode that reports drift.

**Architecture:** `install.sh` detects distro + CPU arch, runs one distro base layer (`install/arch.sh` or `install/ubuntu.sh`), then the distro-agnostic `install/shared.sh` (go/npm/luarocks), then a check against the binary list in `install/manifest.sh`. Ubuntu gets tools apt can't provide as pinned release tarballs under `/opt/<tool>` symlinked into `/usr/local/bin`. The Lua config is untouched. Spec: `docs/superpowers/specs/2026-09-15-cross-distro-install-design.md`.

**Tech Stack:** bash (`set -euo pipefail`), `curl`, `tar`/`unzip`, `sudo`, pacman/yay, apt, NodeSource, `go install`, `npm -g`, `luarocks`. Docker (`ubuntu:22.04`, `ubuntu:24.04`) for testing the Ubuntu path.

## Global Constraints

- Pinned versions (from spec): `NVIM_VERSION=0.12.5 GO_VERSION=1.27.0 ZIG_VERSION=0.16.0 ZLS_VERSION=0.16.0 LUA_LS_VERSION=3.19.1 STYLUA_VERSION=2.5.2 LAZYGIT_VERSION=0.65.1 NODE_MAJOR=22`.
- Supported: `ID=arch`; `ID=ubuntu` or `ID_LIKE` containing `debian`; `x86_64` and `aarch64`. Anything else → error before touching the system.
- Every install step skips if the tool is already present at an acceptable version; re-running is always safe.
- Release tarballs: download to a temp dir, verify (`tar -t` / `unzip -t`), only then replace `/opt/<name>`. Go goes to `/usr/local/go`.
- The scripts never edit shell rc files; they only warn if `$(go env GOPATH)/bin` isn't on `PATH`.
- Every script passes `bash -n` and `shellcheck`. Scripts under `install/` are sourced (not executed); they start with `# shellcheck shell=bash` and have no shebang or `set -e` of their own.
- `magick` rock lives at `$HOME/.luarocks/share/lua/5.1/magick` (pure-Lua FFI binding; `libMagickWand` comes from the system imagemagick).
- Commits end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

---

### Task 1: Manifest, helpers, entry point with `--check`

**Files:**
- Create: `install/manifest.sh`, `install/common.sh`, `install.sh`

**Interfaces:**
- Produces (used by Tasks 2–4): variables `NVIM_VERSION GO_VERSION ZIG_VERSION ZLS_VERSION LUA_LS_VERSION STYLUA_VERSION LAZYGIT_VERSION NODE_MAJOR`, array `REQUIRED_BINS`, `MAGICK_ROCK`, `ARCH` (`x86_64`|`aarch64`), `DISTRO` (`arch`|`ubuntu`); functions `log warn die have version_ge bin_version have_version install_release`.

- [ ] **Step 1: Write `install/manifest.sh`**

```bash
# shellcheck shell=bash
# Single source of truth for pinned versions and the binaries the config needs.

NVIM_VERSION=0.12.5
GO_VERSION=1.27.0
ZIG_VERSION=0.16.0
ZLS_VERSION=0.16.0 # must match ZIG_VERSION's minor
LUA_LS_VERSION=3.19.1
STYLUA_VERSION=2.5.2
LAZYGIT_VERSION=0.65.1
NODE_MAJOR=22

# Everything that must be on PATH for the config to work. Checked by
# `install.sh --check`; see the spec for which plugin needs each one.
REQUIRED_BINS=(
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
  # linters / formatters
  shfmt shellcheck yamllint actionlint jq
  # markdown rendering
  luarocks mmdc
)

# Binaries that also have a minimum version (checked with bin_version).
declare -A MIN_VERSION=(
  [nvim]="$NVIM_VERSION"
  [go]="$GO_VERSION"
  [node]="$NODE_MAJOR.0.0"
)

MAGICK_ROCK="$HOME/.luarocks/share/lua/5.1/magick"
```

- [ ] **Step 2: Write `install/common.sh`**

```bash
# shellcheck shell=bash
# Helpers shared by install.sh and the install/*.sh layers.

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

# version_ge 1.2.3 1.2.0 -> true when $1 >= $2 (semver-ish, via sort -V)
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

# bin_version <bin> -> prints the installed version normalized to X.Y.Z
bin_version() {
  case "$1" in
    nvim) nvim --version | head -n1 | sed -E 's/^NVIM v([0-9.]+).*/\1/' ;;
    go) go version | sed -E 's/^go version go([0-9.]+).*/\1/' ;;
    node) node --version | sed 's/^v//' ;;
    zig) zig version ;;
    zls) zls --version ;;
    stylua) stylua --version | awk '{print $2}' ;;
    lazygit) lazygit --version | sed -E 's/.*version=([0-9.]+).*/\1/' ;;
    lua-language-server) lua-language-server --version | sed -E 's/^[^0-9]*([0-9.]+).*/\1/' ;;
    *) die "bin_version: no version parser for '$1'" ;;
  esac
}

# have_version <bin> <min> -> true when <bin> is on PATH at version >= <min>
have_version() { have "$1" && version_ge "$(bin_version "$1")" "$2"; }

# detect_distro -> prints arch|ubuntu, dies otherwise. OS_RELEASE overrides the file (tests).
detect_distro() {
  local f="${OS_RELEASE:-/etc/os-release}" id like
  [ -r "$f" ] || die "cannot read $f"
  # shellcheck disable=SC1090
  read -r id like < <(. "$f" && printf '%s %s\n' "${ID:-}" "${ID_LIKE:-}")
  case " $id $like " in
    *" arch "*) echo arch ;;
    *" ubuntu "* | *" debian "*) echo ubuntu ;;
    *) die "unsupported distro '$id' (supported: arch, ubuntu/debian-like)" ;;
  esac
}

# detect_arch -> prints x86_64|aarch64, dies otherwise
detect_arch() {
  case "$(uname -m)" in
    x86_64) echo x86_64 ;;
    aarch64 | arm64) echo aarch64 ;;
    *) die "unsupported architecture '$(uname -m)' (supported: x86_64, aarch64)" ;;
  esac
}

# install_release <name> <url> <strip-components> <bin-relpath>...
# Download an archive, verify it, unpack into /opt/<name> (replacing any previous
# install) and symlink each listed binary into /usr/local/bin. A failed download
# or corrupt archive dies before /opt is touched.
install_release() {
  local name=$1 url=$2 strip=$3
  shift 3
  local tmp
  tmp=$(mktemp -d)
  log "installing $name from $url"
  curl -fsSL -o "$tmp/archive" "$url"
  mkdir "$tmp/root"
  case "$url" in
    *.zip)
      unzip -tq "$tmp/archive" >/dev/null
      unzip -q "$tmp/archive" -d "$tmp/root"
      ;;
    *.tar.xz)
      tar -tJf "$tmp/archive" >/dev/null
      tar -xJf "$tmp/archive" -C "$tmp/root" --strip-components="$strip"
      ;;
    *.tar.gz)
      tar -tzf "$tmp/archive" >/dev/null
      tar -xzf "$tmp/archive" -C "$tmp/root" --strip-components="$strip"
      ;;
    *) die "install_release: unknown archive type in $url" ;;
  esac
  sudo rm -rf "/opt/$name"
  sudo mv "$tmp/root" "/opt/$name"
  sudo chown -R root:root "/opt/$name"
  local rel
  for rel in "$@"; do
    sudo chmod +x "/opt/$name/$rel"
    sudo ln -sfn "/opt/$name/$rel" "/usr/local/bin/$(basename "$rel")"
  done
  rm -rf "$tmp"
}
```

- [ ] **Step 3: Write `install.sh`**

```bash
#!/usr/bin/env bash
# Install every external tool the Neovim config depends on, on Arch or Ubuntu.
#   ./install.sh          install what is missing, then check
#   ./install.sh --check  only report what is missing (exit 1 if anything is)
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=install/common.sh
. "$HERE/install/common.sh"
# shellcheck source=install/manifest.sh
. "$HERE/install/manifest.sh"

check() {
  local ok=1 bin want got
  printf '%-28s %s\n' 'tool' 'status'
  for bin in "${REQUIRED_BINS[@]}"; do
    if ! have "$bin"; then
      printf '%-28s \033[31m✗ missing\033[0m\n' "$bin"
      ok=0
    elif [ -n "${MIN_VERSION[$bin]:-}" ]; then
      want=${MIN_VERSION[$bin]}
      got=$(bin_version "$bin")
      if version_ge "$got" "$want"; then
        printf '%-28s \033[32m✓\033[0m %s\n' "$bin" "$got"
      else
        printf '%-28s \033[31m✗ %s < %s\033[0m\n' "$bin" "$got" "$want"
        ok=0
      fi
    else
      printf '%-28s \033[32m✓\033[0m\n' "$bin"
    fi
  done
  if [ -d "$MAGICK_ROCK" ]; then
    printf '%-28s \033[32m✓\033[0m\n' 'magick (luarock)'
  else
    printf '%-28s \033[31m✗ missing (%s)\033[0m\n' 'magick (luarock)' "$MAGICK_ROCK"
    ok=0
  fi
  [ "$ok" = 1 ]
}

main() {
  if [ "${1:-}" = --check ]; then
    check
    return
  fi
  [ $# -eq 0 ] || die "usage: $0 [--check]"

  DISTRO=$(detect_distro)
  ARCH=$(detect_arch)
  export DISTRO ARCH
  log "distro=$DISTRO arch=$ARCH"
  sudo -v

  # shellcheck disable=SC1090
  . "$HERE/install/$DISTRO.sh"
  # shellcheck source=install/shared.sh
  . "$HERE/install/shared.sh"

  log 'checking'
  check
}

main "$@"
```

- [ ] **Step 4: Create empty layer stubs so `install.sh` can be sourced end-to-end**

Create `install/arch.sh`, `install/ubuntu.sh`, `install/shared.sh` each containing only:

```bash
# shellcheck shell=bash
```

(Tasks 2–4 fill them in.)

- [ ] **Step 5: Syntax check and run `--check`**

Run: `chmod +x install.sh && bash -n install.sh install/*.sh && ./install.sh --check; echo "exit=$?"`
Expected: a table with ✓ for `nvim git go gopls stylua jq rg fd fzf gh lazygit make cc luarocks …` and ✗ for `lua-language-server zls yaml-language-server bash-language-server tailwindcss-language-server prettier prettierd shfmt shellcheck yamllint actionlint mmdc`; `magick (luarock)` ✓; `exit=1`.

- [ ] **Step 6: Test distro/arch detection**

Run:
```bash
printf 'ID=ubuntu\nID_LIKE=debian\n' > /tmp/claude-1000/os-ubuntu
printf 'ID=fedora\n' > /tmp/claude-1000/os-fedora
bash -c '. install/common.sh; OS_RELEASE=/tmp/claude-1000/os-ubuntu detect_distro; detect_distro; OS_RELEASE=/tmp/claude-1000/os-fedora detect_distro'; echo "exit=$?"
```
Expected: `ubuntu`, `arch`, then `error: unsupported distro 'fedora' …`, `exit=1`.

- [ ] **Step 7: Commit**

```bash
git add install.sh install/
git commit -m "feat: install.sh entry point with manifest and --check mode"
```

---

### Task 2: Arch base layer + shellcheck all scripts

**Files:**
- Modify: `install/arch.sh`

**Interfaces:**
- Consumes: `log have` from `common.sh`.
- Produces: on Arch, everything apt/pacman-provided in the manifest; `shellcheck` becomes available for linting the scripts.

- [ ] **Step 1: Write `install/arch.sh`**

```bash
# shellcheck shell=bash
# Arch base layer: everything that comes from pacman/yay. Tools shared with
# Ubuntu (go install / npm -g / luarocks) live in shared.sh.

log 'arch: pacman packages'
sudo pacman -S --needed --noconfirm \
  git curl unzip base-devel \
  ripgrep fd fzf jq shellcheck yamllint \
  clang imagemagick luarocks lua51 \
  github-cli lazygit \
  neovim go zig nodejs npm \
  stylua lua-language-server

if ! have zls; then
  have yay || die 'yay is required to install zls from the AUR'
  log 'arch: aur packages'
  yay -S --needed --noconfirm zls
fi
```

- [ ] **Step 2: Run the full installer on this machine**

Run: `./install.sh 2>&1 | tail -40; echo "exit=${PIPESTATUS[0]}"`
Expected: pacman installs the missing packages (`shellcheck yamllint lua-language-server …`), yay installs `zls`, the stub `shared.sh` does nothing, and the check table now shows ✗ only for the shared-layer tools (`yaml-language-server bash-language-server tailwindcss-language-server prettier prettierd shfmt actionlint mmdc`). Exit `1` (shared layer not written yet).

- [ ] **Step 3: shellcheck every script**

Run: `shellcheck -x install.sh install/*.sh; echo "exit=$?"`
Expected: no output, `exit=0`. Fix any warning by changing the code, not by adding `disable` directives (except the existing `SC1090` in `detect_distro`, which is inherent to sourcing a variable path).

- [ ] **Step 4: Commit**

```bash
git add install/arch.sh
git commit -m "feat: arch base layer for install.sh"
```

---

### Task 3: Shared layer (go / npm / luarocks)

**Files:**
- Modify: `install/shared.sh`

**Interfaces:**
- Consumes: `log warn have` from `common.sh`, `MAGICK_ROCK` from `manifest.sh`.
- Produces: the `go install`, `npm -g`, and `luarocks` tools; the final `--check` passes on Arch.

- [ ] **Step 1: Write `install/shared.sh`**

```bash
# shellcheck shell=bash
# Distro-agnostic layer: tools installed through go, npm and luarocks so that
# Arch and Ubuntu get byte-identical versions. Runs after the base layer.

log 'shared: go tools'
GOBIN=$(go env GOPATH)/bin
# Remember whether the user's own PATH has GOBIN before we prepend it for this run.
case ":$PATH:" in
  *":$GOBIN:"*) GOBIN_ON_PATH=1 ;;
  *) GOBIN_ON_PATH=0 ;;
esac
export PATH="$GOBIN:$PATH"
go_tool() { # go_tool <binary> <module path>
  have "$1" || go install "$2@latest"
}
go_tool gopls golang.org/x/tools/gopls
go_tool goimports golang.org/x/tools/cmd/goimports
go_tool golines github.com/segmentio/golines
go_tool gomodifytags github.com/fatih/gomodifytags
go_tool dlv github.com/go-delve/delve/cmd/dlv
go_tool templ github.com/a-h/templ/cmd/templ
go_tool shfmt mvdan.cc/sh/v3/cmd/shfmt
go_tool actionlint github.com/rhysd/actionlint/cmd/actionlint

log 'shared: npm packages'
npm_tool() { # npm_tool <binary> <package> [extra npm flags...]
  local bin=$1 pkg=$2
  shift 2
  have "$bin" || sudo npm install -g "$@" "$pkg"
}
npm_tool prettier prettier
npm_tool prettierd @fsouza/prettierd
npm_tool yaml-language-server yaml-language-server
npm_tool bash-language-server bash-language-server
npm_tool tailwindcss-language-server @tailwindcss/language-server
# --allow-scripts is required or puppeteer skips its Chromium download and mmdc fails at runtime
npm_tool mmdc @mermaid-js/mermaid-cli --allow-scripts=puppeteer

log 'shared: magick luarock'
[ -d "$MAGICK_ROCK" ] || luarocks --lua-version 5.1 install magick --local

[ "$GOBIN_ON_PATH" = 1 ] || warn "add $GOBIN to your PATH (go-installed tools live there)"
```

`shared.sh` prepends `$GOBIN` for its own run so the final check passes; the warning is about the user's shell PATH, hence the capture before prepending.

- [ ] **Step 2: Run the installer on this machine**

Run: `./install.sh 2>&1 | tail -45; echo "exit=${PIPESTATUS[0]}"`
Expected: `go install` and `npm install -g` lines for each missing tool, luarocks skipped (already present), every row ✓, `exit=0`.

- [ ] **Step 3: Re-run to prove idempotence**

Run: `time ./install.sh 2>&1 | grep -cE 'go install|npm install|luarocks'`
Expected: `0` (nothing re-installed), completes in a few seconds, exit 0.

- [ ] **Step 4: Confirm Neovim actually picks the tools up**

Run: `nvim --headless "+lua for _,b in ipairs{'lua-language-server','zls','prettierd','mmdc','shfmt'} do print(b, vim.fn.exepath(b)) end" +q 2>&1 | grep -v deprecated`
Expected: a non-empty path for each of the five.

- [ ] **Step 5: shellcheck and commit**

Run: `shellcheck -x install.sh install/*.sh`
Expected: clean.

```bash
git add install/shared.sh
git commit -m "feat: shared go/npm/luarocks layer for install.sh"
```

---

### Task 4: Ubuntu base layer, tested in Docker

**Files:**
- Modify: `install/ubuntu.sh`

**Interfaces:**
- Consumes: `log have have_version install_release` from `common.sh`; all `*_VERSION`, `NODE_MAJOR`; `ARCH` exported by `install.sh`.
- Produces: on Ubuntu, everything the manifest needs that `shared.sh` doesn't install.

- [ ] **Step 1: Write `install/ubuntu.sh`**

```bash
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
```

Archive layouts (verified against the real releases, which is why `strip` differs): nvim and zig have a single top-level directory (`strip=1`); zls, lazygit, stylua are flat; lua-language-server is flat with `bin/`.

- [ ] **Step 2: shellcheck**

Run: `shellcheck -x install.sh install/*.sh`
Expected: clean. (`GOARCH` etc. are assigned in a `case` — shellcheck may flag SC2034 for any that end up unused; every one above is used.)

- [ ] **Step 3: Write the Docker test runner**

Create `ubuntu-test.sh` in the session scratchpad directory with:

```bash
#!/usr/bin/env bash
# usage: ubuntu-test.sh <ubuntu tag>   — fresh install + check + nvim smoke test
set -euo pipefail
tag=$1
docker run --rm -v "$HOME/.config/nvim:/src:ro" "ubuntu:$tag" bash -euxo pipefail -c '
  apt-get update -qq && apt-get install -y -qq sudo git >/dev/null
  mkdir -p /root/.config && cp -r /src /root/.config/nvim && cd /root/.config/nvim
  ./install.sh
  export PATH="$HOME/go/bin:$PATH"
  ./install.sh --check
  nvim --headless "+Lazy! sync" +qa
  nvim --headless "+lua for _,b in ipairs{\"lua-language-server\",\"zls\",\"gopls\",\"prettierd\",\"mmdc\",\"shfmt\",\"clangd\",\"gh\",\"lazygit\"} do assert(vim.fn.exepath(b) ~= \"\", b .. \" not found\") end; assert(pcall(require, \"magick\"), \"magick rock not loadable\"); print(\"smoke ok\")" +qa
'
```

The repo is mounted read-only at `/src` and copied, because lazy.nvim writes `lazy-lock.json` into the config dir and that must not leak back into the repo.

- [ ] **Step 4: Run on Ubuntu 24.04**

Run: `bash <scratchpad>/ubuntu-test.sh 24.04 2>&1 | tail -60; echo "exit=${PIPESTATUS[0]}"`
Expected: every check row ✓, `smoke ok`, `exit=0`. First run takes several minutes (Chromium download for puppeteer, Go toolchain, go installs).

- [ ] **Step 5: Run on Ubuntu 22.04**

Run: `bash <scratchpad>/ubuntu-test.sh 22.04 2>&1 | tail -60; echo "exit=${PIPESTATUS[0]}"`
Expected: same as 24.04. Known differences to watch: 22.04's `imagemagick` is v6 (fine — `magick` rock uses `libMagickWand-6`), `luarocks` may need `lua5.1` selected via `--lua-version 5.1` (already passed).

- [ ] **Step 6: Idempotence on Ubuntu**

Run a variant of the runner that calls `./install.sh` twice and greps the second run:
`docker run --rm -v "$HOME/.config/nvim:/src:ro" ubuntu:24.04 bash -euo pipefail -c 'apt-get update -qq && apt-get install -y -qq sudo git >/dev/null; mkdir -p /root/.config && cp -r /src /root/.config/nvim && cd /root/.config/nvim; ./install.sh >/dev/null 2>&1; export PATH="$HOME/go/bin:$PATH"; ./install.sh 2>&1 | grep -cE "installing|go install|npm install"'`
Expected: `0`.

- [ ] **Step 7: Commit**

```bash
git add install/ubuntu.sh
git commit -m "feat: ubuntu base layer for install.sh"
```

---

### Task 5: Docs and removal of `pacakges.sh`

**Files:**
- Delete: `pacakges.sh`
- Modify: `CLAUDE.md:16-27` ("Fresh Machine Setup"), `lua/plugins/README.md:11`, `lua/plugins/README.md:311`, `init.lua:13-14`

- [ ] **Step 1: Delete the old script**

Run: `git rm pacakges.sh`

- [ ] **Step 2: Replace the "Fresh Machine Setup" section in `CLAUDE.md`**

Replace everything from `## Fresh Machine Setup` up to (not including) `## Architecture` with:

````markdown
## Fresh Machine Setup

```sh
./install.sh          # Arch or Ubuntu 22.04+; idempotent, safe to re-run
./install.sh --check  # audit: ✓/✗ per required tool, exit 1 if anything is missing
```

`install.sh` detects the distro and runs `install/arch.sh` (pacman/yay) or `install/ubuntu.sh` (apt + NodeSource + pinned release tarballs under `/opt`), then `install/shared.sh` (`go install`, `npm -g`, `luarocks`) so both distros get the same tools. Pinned versions and the required-binary list live in `install/manifest.sh`.

Gotchas the script already handles, kept here for context:
- `luarocks --lua-version 5.1 install magick --local` — the `magick` rock must be built for Lua 5.1 so LuaJIT can load it (`init.lua` adds `~/.luarocks` to `package.path`).
- `npm install -g --allow-scripts=puppeteer @mermaid-js/mermaid-cli` — without the flag puppeteer skips its Chromium download and `mmdc` fails at runtime.
- On Ubuntu, `~/go/bin` is usually not on `PATH`; the script warns if so.

Lazy.nvim bootstraps itself on first launch. LSP servers are installed by the script, not by Mason — **Mason is not used**.

````

- [ ] **Step 3: Update `lua/plugins/README.md`**

Line 11: change `LSP servers are installed manually via system packages — **Mason is not used**.` to `LSP servers are installed by `./install.sh` (see the root `CLAUDE.md`) — **Mason is not used**.`

Line 311: change the trailing `mmdc` parenthetical from `(`npm install -g @mermaid-js/mermaid-cli`)` to `(`npm install -g --allow-scripts=puppeteer @mermaid-js/mermaid-cli`)`, and append the sentence: `All three are installed by `./install.sh`.`

- [ ] **Step 4: Update the `init.lua` comment**

Replace lines 13–14:
```lua
-- need to install these in order for it to work on fresh machines have script that does that for you
-- pacman -S git neovim npm unzip go zig
```
with:
```lua
-- External tools (LSPs, formatters, go/zig/node, imagemagick, ...) are installed by ./install.sh
```

- [ ] **Step 5: Verify**

Run: `stylua --check . && shellcheck -x install.sh install/*.sh && ./install.sh --check >/dev/null && grep -rn pacakges . --exclude-dir=.git; echo "exit=$?"`
Expected: stylua and shellcheck silent, check passes, grep finds nothing (`exit=1` from grep is the success case here).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs: point fresh-machine setup at install.sh, drop pacakges.sh"
```

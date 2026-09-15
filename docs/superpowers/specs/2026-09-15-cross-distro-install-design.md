# Cross-distro install script

## Goal

Make the config usable on Ubuntu (22.04+) as well as Arch with full tool
parity, and make drift visible. The Lua config already resolves every external
tool via `PATH` or `~/.luarocks`, so nothing under `lua/` changes; only the
install story does. `pacakges.sh` (Arch-only, and no longer matching what is
actually installed) is replaced by a distro-aware, idempotent `install.sh`
with a `--check` mode.

## Layout

```
install.sh              entry point
install/
  manifest.sh           pinned versions + list of required binaries
  common.sh             helpers: log, have, version_ge, fetch_tar, install_release
  arch.sh               base layer: pacman + yay
  ubuntu.sh             base layer: apt + NodeSource + release tarballs into /opt
  shared.sh             go install / npm -g / luarocks magick
```

`pacakges.sh` is deleted.

## Flow

`./install.sh`:

1. Source `manifest.sh`; detect distro from `/etc/os-release` — `ID=arch` →
   arch, `ID=ubuntu` or `ID_LIKE` containing `debian` → ubuntu, else exit with
   an error naming the supported distros. Detect `uname -m` → `x86_64` or
   `aarch64`, else error.
2. Run the base layer for the distro.
3. Run `shared.sh`.
4. Run the check (below); exit non-zero if anything is missing.

`./install.sh --check` runs only step 4.

Every install step is guarded ("skip if already on `PATH` at an acceptable
version"), so re-running after a partial failure is safe.

## Manifest (`install/manifest.sh`)

Pinned versions as variables, one line each to bump:

```
NVIM_VERSION=0.12.5   GO_VERSION=1.27.0   ZIG_VERSION=0.16.0   ZLS_VERSION=0.16.0
LUA_LS_VERSION=3.19.1 STYLUA_VERSION=2.5.2 LAZYGIT_VERSION=0.65.1 NODE_MAJOR=22
```

Required binaries (used by the check, and the reason each exists):

| Binary | Needed by |
|---|---|
| `nvim` (≥ NVIM_VERSION), `git`, `unzip`, `curl` | core / lazy.nvim |
| `make`, `cc` | telescope-fzf-native build, treesitter parsers |
| `rg`, `fd`, `fzf` | telescope / snacks pickers |
| `gh`, `lazygit` | pr_review, pr_companion, pr_review_notes, lazygit plugin |
| `go` (≥ GO_VERSION), `gopls`, `goimports`, `golines`, `gomodifytags`, `dlv`, `templ` | Go LSP/format/debug |
| `zig`, `zls` | Zig LSP |
| `lua-language-server`, `stylua` | Lua LSP/format |
| `clangd` | C LSP |
| `node` (≥ NODE_MAJOR), `npm` | npm tools, `mmdc` |
| `yaml-language-server`, `bash-language-server`, `tailwindcss-language-server` | LSPs |
| `prettier`, `prettierd`, `shfmt`, `shellcheck`, `yamllint`, `actionlint`, `jq` | conform / nvim-lint |
| `luarocks`, `magick` rock at `~/.luarocks/lib/lua/5.1/magick`, `convert` (imagemagick), `mmdc` | image.nvim + mermaid |

## Arch base layer (`install/arch.sh`)

`pacman -S --needed`: `git curl unzip base-devel ripgrep fd fzf jq shellcheck
yamllint clang imagemagick luarocks lua51 github-cli lazygit neovim go zig
nodejs npm stylua lua-language-server`.
`yay -S --needed zls`.

Everything else comes from the shared layer. `gopls`, `shfmt`, `actionlint`,
`prettier`, `prettierd` move out of pacman/yay so Arch and Ubuntu get them the
same way.

## Ubuntu base layer (`install/ubuntu.sh`)

**apt**: `git curl unzip build-essential ripgrep fd-find fzf jq shellcheck
yamllint clangd imagemagick libmagickwand-dev luarocks lua5.1 liblua5.1-dev`.
Symlink `/usr/local/bin/fd → fdfind`. `gh` from GitHub's official apt repo.
`node` from NodeSource `setup_${NODE_MAJOR}.x`.

**Pinned release tarballs**, unpacked to `/opt/<tool>` with symlinks into
`/usr/local/bin` (Go goes to `/usr/local/go` per Go's documented layout):

| Tool | Source |
|---|---|
| `nvim` | `github.com/neovim/neovim/releases` `nvim-linux-<arch>.tar.gz` |
| `go` | `go.dev/dl/go<ver>.linux-<arch>.tar.gz` |
| `zig` | `ziglang.org/download/<ver>/zig-<arch>-linux-<ver>.tar.xz` |
| `zls` | `github.com/zigtools/zls/releases` (version pinned with zig) |
| `lua-language-server` | `github.com/LuaLS/lua-language-server/releases` |
| `stylua` | `github.com/JohnnyMorganz/StyLua/releases` zip |
| `lazygit` | `github.com/jesseduffield/lazygit/releases` |

`install_release <name> <url> <bin-relative-path>` downloads to a temp dir,
verifies with `tar -t` (or `unzip -t`), then `rm -rf /opt/<name>` and moves
the verified tree in — a failed download never leaves a half-installed tool.
Skipped when the binary exists at ≥ the pinned version.

## Shared layer (`install/shared.sh`)

Each step skipped if its binary is already on `PATH`.

- `go install`: `golang.org/x/tools/gopls`, `golang.org/x/tools/cmd/goimports`,
  `github.com/segmentio/golines`, `github.com/fatih/gomodifytags`,
  `github.com/go-delve/delve/cmd/dlv`, `github.com/a-h/templ/cmd/templ`,
  `mvdan.cc/sh/v3/cmd/shfmt`, `github.com/rhysd/actionlint/cmd/actionlint`
  (all `@latest`).
- `npm install -g`: `prettier @fsouza/prettierd yaml-language-server
  bash-language-server @tailwindcss/language-server`, and
  `npm install -g --allow-scripts=puppeteer @mermaid-js/mermaid-cli` (the flag
  is required or puppeteer skips its Chromium download).
- `luarocks --lua-version 5.1 install magick --local`, guarded by the rock's
  directory existing.
- If `$(go env GOPATH)/bin` is not on `PATH`, print a warning telling the user
  to add it. The script never edits shell rc files.

## Check mode

For each manifest entry: `command -v`; for `nvim`, `go`, `node` also compare
versions against the pins; check the `magick` rock path. Print a ✓/✗ table,
exit 1 on any ✗. No auto-fix beyond what the install steps already do.

## Error handling

`set -euo pipefail` in every script. Unsupported distro/arch → clear error
before anything is touched. `sudo` is required and requested up front
(`sudo -v`) so the run doesn't stall mid-way.

## Docs

- `CLAUDE.md` "Fresh Machine Setup" → run `./install.sh`, `./install.sh
  --check` to audit; keep the luarocks/puppeteer gotchas as notes.
- `lua/plugins/README.md` install sections → same.
- `init.lua` line 14 comment → point at `install.sh`.

## Testing

- Ubuntu 22.04 and 24.04 in Docker (`docker run --rm -v "$PWD:/nvim" ubuntu:<tag>`):
  fresh `./install.sh`, then `./install.sh --check` must pass, then
  `nvim --headless "+Lazy! sync" +qa` and `:checkhealth` to confirm LSPs and
  `magick` resolve.
- Arch (this machine): `./install.sh --check` must list the currently missing
  tools; `./install.sh` then brings it to parity and `--check` passes.
- `shellcheck` on all scripts.

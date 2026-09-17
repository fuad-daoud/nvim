# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Formatting

All Lua files are formatted with **stylua** (config in `.stylua.toml`: 160-col, 2-space indent, single quotes, no call parentheses).

```sh
stylua --check .   # check
stylua .           # fix
```

CI runs stylua on PRs via `.github/workflows/stylua.yml`.

## Fresh Machine Setup

```sh
./install.sh          # Arch or Ubuntu 22.04+; idempotent, safe to re-run
./install.sh --check  # audit: ✓/✗ per required tool, exit 1 if anything is missing
```

`install.sh` detects the distro and runs `install/arch.sh` (pacman) or `install/ubuntu.sh` (apt + NodeSource + pinned release tarballs under `/opt`), then `install/shared.sh` (`go install`, `npm -g`, `luarocks`, and the `zls` GitHub release) so both distros get the same tools. Pinned versions and the required-binary list live in `install/manifest.sh`.

Gotchas the script already handles, kept here for context:
- `luarocks --lua-version 5.1 install magick --local` — the `magick` rock must be built for Lua 5.1 so LuaJIT can load it (`init.lua` adds `~/.luarocks` to `package.path`).
- `mmdc` renders through puppeteer, whose browser lives in `~/.cache/puppeteer`. Installing mermaid-cli under `sudo npm -g` cannot provide it (a root-run postinstall lands the browser under `/root`), so the script probes with a real render and, if that fails, runs puppeteer's `install.mjs` as the user. On Ubuntu the apt layer also installs headless chrome's runtime libraries (`libnss3`, `libgbm1`, `libasound2[t64]`, …).
- `zls` must match `zig`'s minor version and distro packages (the AUR one in particular) lag, so both distros install the matching GitHub release into `/usr/local/bin`; on Arch the script warns if an AUR `zls` is still installed (`yay -Rns zls`).
- On Ubuntu, `lua-language-server` is a wrapper that points LuaLS's meta/log dirs at `~/.cache/lua-language-server`; the tarball's default is next to the root-owned binary under `/opt`, which silently disables the builtin stdlib definitions.
- `go install` puts tools in `$GOBIN` (default `~/go/bin`), which is often not on `PATH`; the script warns if so.

Lazy.nvim bootstraps itself on first launch. LSP servers are installed by the script, not by Mason — **Mason is not used**.

## Architecture

### Load Order (`init.lua`)

```
scripts/setup.lua   → globals: mapleader, maplocalleader, have_nerd_font
scripts/lazy.lua    → bootstraps lazy.nvim; registers inline plugins + imports lua/plugins/
scripts/autocmd.lua → autocommands
scripts/keymaps.lua → global keymaps
scripts/opt.lua     → vim options
```

See `lua/scripts/CLAUDE.md` for details on each script.

### Plugin Layout

Plugins live in two places:
- **Inline in `lua/scripts/lazy.lua`**: colorscheme (rose-pine), conform, hardtime, colorizer, todo-comments, lazydev, notify, baleia, clock
- **`lua/plugins/*.lua`**: one spec per file, all auto-imported via `{ import = 'plugins' }`

See `lua/plugins/CLAUDE.md` for details on each plugin file.

### Markdown Notes

`init.lua` prepends luarocks Lua 5.1 paths to `package.path`/`package.cpath` so Neovim (LuaJIT) can load the `magick` LuaRock needed by `image.nvim`.

`lua/plugins/treesitter.lua` patches the `set-lang-from-info-string!` treesitter directive with `{ force = true }` because nvim-treesitter (archived) was written for an older Neovim API where `match[id]` returned a bare `TSNode`; Neovim 0.11+ passes `(TSNode|nil)[]`. The patch unwraps the array form safely.

### Shared Utilities

`lua/utils.lua` — small module for helpers shared across plugin specs. Currently exports `emit_osc7(cwd?)` which writes an OSC 7 terminal CWD notification (used by snacks project picker).

`lua/pr_review.lua` — PR review on top of diffview: `:PrReview` open flow and GitHub-synced "viewed" marks (see `lua/plugins/CLAUDE.md` → diffview.lua).

`lua/pr_companion.lua` — per-PR headless Claude Code review companion (`:PrCompanion`, `:PrAsk`, `:PrChat`); sessions and pane transcripts under `stdpath('data')/pr_review/`.

`lua/pr_review_notes.lua` — draft and submit a GitHub review from diffview (`:PrNote`, `:PrNoteDelete`, `:PrReviewSubmit`, `:PrReviewDiscard`; see `lua/plugins/CLAUDE.md` → diffview.lua → Review notes).

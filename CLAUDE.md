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

1. Install system packages from `pacakges.sh`:
   - Core LSPs via pacman: `lua-language-server gopls clang yaml-language-server bash-language-server`
   - AUR LSPs: `zls tailwindcss-language-server`
   - Formatters: `prettier stylua shfmt shellcheck yamllint prettierd actionlint jq`
   - Go tools: `goimports`, `golines`, `gomodifytags`, `dlv`, `templ` via `go install`

2. Base system prereqs (from `init.lua` comment): `pacman -S git neovim npm unzip go zig`

Lazy.nvim bootstraps itself on first launch. LSP servers are installed manually — **Mason is not used**.

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

### Shared Utilities

`lua/utils.lua` — small module for helpers shared across plugin specs. Currently exports `emit_osc7(cwd?)` which writes an OSC 7 terminal CWD notification (used by snacks project picker).

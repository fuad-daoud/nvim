# CLAUDE.md — lua/scripts/

Core runtime scripts loaded directly by `init.lua`. These run before any plugin config.

## setup.lua

Sets three globals that plugins depend on:
- `vim.g.mapleader` / `vim.g.maplocalleader` → `' '` (space)
- `vim.g.have_nerd_font` → `true`

Must load before `lazy.lua` since lazy.nvim uses `mapleader` at setup time.

## opt.lua

Vim options. Notable non-defaults:
- `scrolloff = 20` — keeps cursor well away from screen edges
- `guicursor = 'n-v-i-c:block'` — block cursor in all modes
- `clipboard = 'unnamedplus,unnamed'` — system clipboard by default
- `conceallevel = 1` — needed for Obsidian rendering
- `vim.notify = require 'notify'` — replaces the built-in notify with nvim-notify (must load after plugins)

## keymaps.lua

Global keymaps (buffer-local LSP keymaps are in `lua/plugins/lsp.lua`).

| Key | Action |
|-----|--------|
| `<leader>pv` | Open netrw (`:Ex`) |
| `<leader>u` | Toggle undotree |
| `<C-hjkl>` | Window navigation |
| `<Esc>` | Clear search highlight |
| `<leader>q` | Populate loclist with diagnostics |
| `<Esc><Esc>` (terminal) | Exit terminal mode |
| `J` / `K` (visual) | Move selected lines down/up |
| `J` / `K` (normal) | Move current line down/up |

## autocmd.lua

| Autocmd | Trigger | Effect |
|---------|---------|--------|
| `highlight-yank` | `TextYankPost` | Flash yanked region |
| TelescopePreviewerLoaded | `User` | Force line numbers in preview |
| ObsidianSync (read) | `BufReadPost *.md` in `~/vaults/` | Runs `sync.sh`, reloads buffer |
| ObsidianSync (write) | `BufWritePost *.md` in `~/vaults/` | Runs `sync.sh` |
| GoFormat | `BufWritePre *.go` | Applies `source.organizeImports` via LSP code action |
| lsp-signature | `CursorHoldI` | Shows signature help in insert mode |

The Obsidian sync autocmds call `/home/fuad/.config/nvim/sync.sh` (rsync to Contabo). The path is hardcoded — update it if the config moves.

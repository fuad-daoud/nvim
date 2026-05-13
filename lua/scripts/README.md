# Scripts

These files are loaded directly by `init.lua` before any plugin config runs. They form the foundation of the editor's behaviour.

---

## setup.lua

Sets three globals consumed throughout the rest of the config:

| Global | Value | Purpose |
|--------|-------|---------|
| `vim.g.mapleader` | `' '` | Space as leader key |
| `vim.g.maplocalleader` | `' '` | Space as local leader |
| `vim.g.have_nerd_font` | `true` | Enables icon sets in plugins |

Must load before `lazy.lua` — lazy.nvim reads `mapleader` at setup time when registering plugin keymaps.

---

## opt.lua

### Editor Behaviour

| Option | Value | Effect |
|--------|-------|--------|
| `number` | true | Show line numbers |
| `relativenumber` | true | Relative line numbers |
| `mouse` | `'a'` | Mouse support in all modes |
| `undofile` | true | Persistent undo across sessions |
| `updatetime` | 250ms | Faster CursorHold triggers |
| `timeoutlen` | 300ms | Shorter wait for key sequences |
| `scrolloff` | 20 | Keeps cursor far from screen edges |
| `wrap` | false | No line wrapping |
| `conceallevel` | 1 | Enables Obsidian/markdown conceals |

### Search

| Option | Value | Effect |
|--------|-------|--------|
| `ignorecase` | true | Case-insensitive search by default |
| `smartcase` | true | Case-sensitive when uppercase used |
| `inccommand` | `'split'` | Live preview of `:s` substitutions |

### Splits & Windows

| Option | Value | Effect |
|--------|-------|--------|
| `splitright` | true | Vertical splits open to the right |
| `splitbelow` | true | Horizontal splits open below |
| `signcolumn` | `'yes'` | Always show sign column (no layout shift) |

### Appearance

| Option | Value | Effect |
|--------|-------|--------|
| `showmode` | false | Mode hidden (shown in lualine instead) |
| `cursorline` | false | No cursorline highlight |
| `guicursor` | `n-v-i-c:block` | Block cursor in all modes |
| `termguicolors` | true | 24-bit colour support |
| `list` | true | Show invisible characters |
| `listchars` | tab `» `, trail `·`, nbsp `␣` | Visible whitespace markers |
| `breakindent` | true | Wrapped lines preserve indent |

### Clipboard & Wildcards

| Option | Value | Effect |
|--------|-------|--------|
| `clipboard` | `unnamedplus,unnamed` | All yank/paste uses system clipboard |
| `wildignore` | `*node_modules/**` | Excluded from file completion |

### Terminal Colours

Rose-pine moon palette wired into terminal colours 0–7 (black, red, green, yellow, blue, magenta, cyan, white).

### Notify Override

`vim.notify` is replaced with `require 'notify'` (nvim-notify) so all notifications use the floating UI. This runs in `opt.lua` which loads after `lazy.lua` so the plugin is available.

---

## keymaps.lua

Global keymaps. Buffer-local LSP keymaps live in `lua/plugins/lsp.lua`.

### Navigation

| Key | Mode | Action |
|-----|------|--------|
| `<C-h/j/k/l>` | Normal | Move focus between windows |
| `<A-h/j/k/l>` | Normal/Terminal | Move focus between windows (also set in toggleterm) |
| `<Esc>` | Normal | Clear search highlight |
| `<Esc><Esc>` | Terminal | Exit terminal mode |

### File & Editing

| Key | Mode | Action |
|-----|------|--------|
| `<leader>pv` | Normal | Open netrw (`:Ex`) |
| `<leader>u` | Normal | Toggle undotree |
| `J` / `K` | Visual | Move selected lines down / up |
| `J` / `K` | Normal | Move current line down / up |
| `<leader>q` | Normal | Open diagnostics in loclist |

Arrow keys in normal mode are disabled with a hint message to use `h/j/k/l`.

---

## autocmd.lua

### Yank Highlight

Flashes the yanked region after every yank (`TextYankPost`). Uses the built-in `vim.highlight.on_yank`.

### Telescope Preview

Forces `number = true` in Telescope previewer windows (`User TelescopePreviewerLoaded`).

### Obsidian Sync

Triggers `sync.sh` (rclone bisync to Contabo) for any `*.md` / `*.markdown` file opened or saved under `~/vaults/`.

- **On open** (`BufReadPost`): syncs then reloads the buffer to show remote changes, restoring cursor position.
- **On save** (`BufWritePost`): syncs after writing.

Both show a statusline message while syncing and notify on success or failure. The sync script path is hardcoded to `/home/fuad/.config/nvim/sync.sh`.

`sync.sh` runs `rclone bisync` between `contabo:obsidian` and `~/vaults` with conflict resolution favouring the newer file.

### Go Import Organisation

On `BufWritePre` for `*.go` files, fires `source.organizeImports` via LSP code action (`apply = true`) to keep imports sorted automatically.

### LSP Signature Help

On `CursorHoldI` (any buffer), calls `vim.lsp.buf.signature_help()` to show function signatures while typing arguments.

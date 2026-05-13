# Plugins

All files in this directory return a lazy.nvim plugin spec and are auto-imported by `{ import = 'plugins' }` in `lua/scripts/lazy.lua`. Some smaller plugins are defined inline in `lazy.lua` itself — see the [Inline Plugins](#inline-plugins) section at the bottom.

---

## LSP — `lsp.lua`

**Plugin:** `neovim/nvim-lspconfig` + `j-hui/fidget.nvim`

LSP servers are installed manually via system packages — **Mason is not used**. Capabilities are sourced from blink.cmp so completion and LSP share the same capability set.

### Configured Servers

| Server | Language |
|--------|----------|
| `lua_ls` | Lua (with `callSnippet = Replace`, missing-fields disabled) |
| `gopls` | Go (with `unusedparams`, `shadow`, `staticcheck`, `gofumpt`) |
| `zls` | Zig |
| `tailwindcss` | Tailwind CSS |
| `html` | HTML |
| `cssls` | CSS |
| `jsonls` | JSON |
| `yamlls` | YAML |
| `bashls` | Bash |

### LSP Keymaps (buffer-local, set on `LspAttach`)

| Key | Action |
|-----|--------|
| `gd` | Go to definition (Telescope) |
| `gr` | Go to references (Telescope) |
| `gi` | Go to implementation (Telescope) |
| `gt` | Go to type definition (Telescope) |
| `<leader>gd` | Go to declaration |
| `<leader>ds` | Document symbols (Telescope) |
| `<leader>ws` | Workspace symbols (Telescope) |
| `<leader>ca` | Code action (normal + visual) |
| `<leader>rn` | Rename symbol |
| `<leader>h` | Hover documentation |
| `<leader>pd` | Jump to previous diagnostic |
| `<leader>nd` | Jump to next diagnostic |
| `<leader>e` | Open focused diagnostic float |
| `<leader>th` | Toggle inlay hints |

### Diagnostics Display

- Virtual text: `●` prefix, shows source when multiple servers are active
- Floating window on `CursorHold` (unfocused, cursor-scoped)
- Signs: `✘` error · `▲` warn · `⚑` hint · `»` info
- Rounded borders on all floats

---

## Completion — `blink.lua`

**Plugin:** `saghen/blink.cmp` + `rafamadriz/friendly-snippets`

Replaces nvim-cmp. Sources in priority order: LSP → path → snippets → buffer. Default keymap preset. Nerd Font mono variant for icons.

---

## Debugging — `debug.lua`

**Plugins:** `mfussenegger/nvim-dap` + `rcarriga/nvim-dap-ui` + `leoluz/nvim-dap-go`

Go debugging uses delve. `<leader>da` attaches to a delve instance already running on `127.0.0.1:2345` (useful for debugging running services or containers).

DAP UI opens automatically when a session starts and closes on terminate/exit. Layout:
- **Bottom (15 lines):** Scopes (75%) + Breakpoints (25%)
- **Right (50 cols):** REPL

### Debug Keymaps

| Key | Action |
|-----|--------|
| `<F5>` | Start / Continue |
| `<F1>` | Step Into |
| `<F2>` | Step Over |
| `<F3>` | Step Out |
| `<F7>` | Toggle DAP UI |
| `<leader>b` | Toggle breakpoint |
| `<leader>B` | Set conditional breakpoint |
| `<leader>dr` | Restart session |
| `<leader>dt` | Terminate session |
| `<leader>da` | Attach to running dlv (port 2345) |
| `<leader>dh` | Hover value |
| `<leader>dk` | Show scopes float |
| `<leader>dp` | Preview value |

Breakpoint signs are styled with rose-pine colours: `●` for active, `◆` for conditional, `→` for stopped line, `○` for rejected.

---

## UI Hub — `snacks.lua`

**Plugin:** `folke/snacks.nvim`

Central plugin providing the dashboard, file explorer, project picker, lazygit integration, indent guides, word highlighting, and all toggle mappings.

### Dashboard

Opens on launch. Quick-access keys:

| Key | Action |
|-----|--------|
| `r` | Recent files |
| `n` | New file |
| `f` | File explorer |
| `p` | Project picker |
| `t` | Obsidian Today |
| `y` | Obsidian Yesterday |
| `g` | General thoughts note |
| `c` | Browse neovim config files |
| `z` | Open Lazy |
| `q` | Quit |

Return to dashboard from anywhere: `<leader>hb` (closes all buffers, reopens dashboard).

### Git Keymaps

| Key | Action |
|-----|--------|
| `<leader>gg` | Open lazygit |
| `<leader>gb` | Blame current line |
| `<leader>gf` | Current file history in lazygit |
| `<leader>gl` | Full log in lazygit |

### Toggle Keymaps (`\<key>`)

All set on `VeryLazy` event:

| Key | Toggles |
|-----|---------|
| `\s` | Spell checking |
| `\w` | Line wrap |
| `\c` | Cursorline |
| `\l` | List characters (whitespace markers) |
| `\g` | Ignorecase |
| `\r` | Relative line numbers |
| `\d` | Diagnostics |
| `\n` | Line numbers |
| `\-` | Conceallevel (0 ↔ 2) |
| `\/` | Treesitter |
| `\b` | Dark/light background |
| `\h` | Inlay hints |
| `\i` | Indent guides |
| `\z` | Zen mode |
| `\o` | Word highlighting |
| `\p` | Auto-pairs (mini.pairs) |
| `\T` | Trailing whitespace removal |

### Project Picker

When a project is selected, snacks: changes cwd with `vim.cmd('cd ...')`, emits an OSC 7 escape sequence so the terminal emulator follows the directory, then opens netrw.

---

## Fuzzy Finder — `telescope.lua`

**Plugins:** `nvim-telescope/telescope.nvim` + fzf-native + ui-select + file-browser + project extensions

Layout: 90% width/height, prompt at bottom, preview cuts off at 180 cols.

### Keymaps

| Key | Action |
|-----|--------|
| `<leader>sf` | Find files |
| `<leader>sg` | Live grep |
| `<leader>sw` | Grep word under cursor |
| `<C-p>` | Git-tracked files only |
| `<leader>sh` | Help tags |
| `<leader>sk` | Keymaps |
| `<leader>sd` | Diagnostics |
| `<leader>sr` | Resume last picker |
| `<leader>s.` | Recent files |
| `<leader>ss` | Browse all Telescope pickers |
| `<leader><leader>` | Open buffers |
| `<leader>/` | Fuzzy search in current buffer |
| `<leader>s/` | Live grep across open files |
| `<leader>sn` | Search neovim config files |
| `<leader>sp` | Project switcher |
| `<leader>st` | Search TODO comments |
| `<leader>pt` | Pomodoro timer picker |
| `<space>fb` | File browser |

### Project Switcher

Base directories scanned: `~/projects/`, `~/.config/nvim`, `~/.config/sway`, `~/.config/ghostty`, `~/.config/waybar`, `~/.config/rofi`, `~/.config/clipse`.

On project selection: cds into the project and emits OSC 7 so the terminal follows.

In-picker project actions: `<c-a>` add · `<c-v>` rename · `<c-d>` delete · `<c-f>` find files · `<c-b>` browse files · `<c-s>` search in project · `<c-r>` recent files · `<c-l>` change working dir.

---

## Syntax — `treesitter.lua`

**Plugin:** `nvim-treesitter/nvim-treesitter`

`auto_install = true` — parsers install automatically on first open of a new filetype.

Pre-installed parsers: `bash`, `c`, `diff`, `html`, `lua`, `luadoc`, `markdown`, `markdown_inline`, `query`, `vim`, `vimdoc`, `go`, `rust`, `zig`, `dockerfile`.

Includes a custom **templ** parser (`virschmann/tree-sitter-templ`) for Go templating with the `a-h/templ` tool. Markdown uses additional vim regex highlighting for correct indent behaviour.

---

## Notes — `obsidian.lua`

**Plugin:** `epwalsh/obsidian.nvim`

### Workspaces

| Name | Path |
|------|------|
| `personal` | `~/vaults/personal` |
| `work` | `~/vaults/progressoft` |

Vault files sync automatically on open/save via `sync.sh` (rclone bisync to Contabo) — configured in `lua/scripts/autocmd.lua`.

### Keymaps

| Key | Action |
|-----|--------|
| `<leader>ot` | Open today's daily note |
| `<leader>om` | Open tomorrow's daily note |
| `<leader>oy` | Open yesterday's daily note |
| `<leader>od` | Browse all daily notes |
| `<leader>os` | Search vault |
| `<leader>oqs` | Quick switch between notes |
| `<leader>ow` | Switch workspace |

---

## Terminal — `toggleterm.lua`

**Plugin:** `akinsho/toggleterm.nvim`

Default mode is a large floating terminal (`<C-\>`). The `<leader>tf` keymap opens an even larger float sized to the editor dimensions.

### Keymaps

| Key | Action |
|-----|--------|
| `<C-\>` | Toggle floating terminal (default) |
| `<leader>tt` | Toggle horizontal terminal (15 lines) |
| `<leader>tv` | Toggle vertical terminal (40% width) |
| `<leader>tf` | Toggle large floating terminal |
| `<A-h/j/k/l>` | Navigate to adjacent window (normal + terminal mode) |

---

## Git Signs — `gitsigns.lua`

**Plugin:** `lewis6991/gitsigns.nvim`

Shows `┃` in the sign column for added/changed lines, `~` for changed+deleted. Staged changes shown with the same signs.

### Keymaps (buffer-local)

| Key | Action |
|-----|--------|
| `<leader>gb` | Blame current line |
| `<leader>gd` | Diff against index |
| `<leader>gD` | Diff against last commit |
| `<leader>tD` | Preview hunk inline |

---

## Session Management — `persistence.lua`

**Plugin:** `folke/persistence.nvim`

Saves and restores buffer/window layout per working directory.

| Key | Action |
|-----|--------|
| `<leader>rs` | Restore session for current directory |
| `<leader>rls` | Restore the last session (any directory) |
| `<leader>ns` | Stop saving session for this session |

---

## Undo History — `undotree.lua`

**Plugin:** `mbbill/undotree`

Visualises the full undo tree. Toggle with `<leader>u` (keymap defined in `lua/scripts/keymaps.lua`).

---

## Pomodoro — `pomo.lua`

**Plugin:** `epwalsh/pomo.nvim`

Commands: `:TimerStart <duration>`, `:TimerRepeat`, `:TimerSession pomodoro`.

Built-in pomodoro session: 25m work → 5m break → 25m work → 5m break → 25m work → 15m long break.

Notifications use nvim-notify (sticky floating alerts). System notifications sent on timer end. Browse active timers with `<leader>pt` (Telescope).

---

## Per-project Config — `config-local.lua`

**Plugin:** `klen/nvim-config-local`

Loads `.nvim.lua` or `.nvimrc` from the project root when present. Hash-verified on first load to prevent executing untrusted code. Useful for setting Go build tags, project-specific LSP overrides, etc.

Hash store location: `vim.fn.stdpath('data') .. '/config-local'`.

---

## Status Line — `lualine.lua`

**Plugin:** `nvim-lualine/lualine.nvim`

Global statusline (single bar across all windows) using the rose-pine theme.

Sections: mode | branch + diff + diagnostics | relative filename | encoding + fileformat + filetype | progress | location.

Disabled on `dashboard` and `alpha` filetypes. Extensions: toggleterm, fugitive, mason, lazy.

---

## Inline Plugins (defined in `lua/scripts/lazy.lua`)

These don't have their own file in `lua/plugins/`.

| Plugin | Purpose |
|--------|---------|
| `rose-pine/neovim` | Colorscheme (moon variant, transparent, custom palette) |
| `stevearc/conform.nvim` | Format on save (`<leader>f` to format manually) |
| `folke/lazydev.nvim` | Lua LSP improvements for Neovim API development |
| `Bilal2453/luvit-meta` | Type definitions for `vim.uv` |
| `m4xshen/hardtime.nvim` | Enforces good Vim motion habits |
| `folke/todo-comments.nvim` | Highlights and searches TODO/FIXME/HACK/etc. |
| `tpope/vim-sleuth` | Auto-detects tabstop and shiftwidth from file content |
| `catgoose/nvim-colorizer.lua` | Highlights hex colour codes inline |
| `rcarriga/nvim-notify` | Floating notification UI (replaces `vim.notify`) |
| `m00qek/baleia.nvim` | Renders ANSI escape codes in buffers (`:BaleiaColorize`) |
| `registerGen/clock.nvim` | Clock display |

### Conform Formatters by Filetype

| Filetype | Formatter(s) |
|----------|--------------|
| Lua | stylua |
| JS / TS / JSX / TSX | prettierd → prettier |
| CSS / GraphQL / JSON | prettierd → prettier |
| Svelte | prettierd → prettier |
| YAML | prettierd |
| Python | isort → black |
| SQL | sql-formatter |
| Elixir | prettierd |
| Go | LSP (gofumpt via gopls) |

Format on save runs with a 500ms timeout. C/C++ files are excluded from auto-format.

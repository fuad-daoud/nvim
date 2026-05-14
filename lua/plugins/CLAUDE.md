# CLAUDE.md — lua/plugins/

Each file returns a lazy.nvim plugin spec. All files are auto-imported by `{ import = 'plugins' }` in `lua/scripts/lazy.lua`.

## lsp.lua

Configures `nvim-lspconfig` directly — **no Mason**. Servers must be installed via system packages (see root CLAUDE.md).

Active servers: `lua_ls`, `gopls`, `zls`, `tailwindcss`, `html`, `cssls`, `jsonls`, `yamlls`, `bashls`, `kotlin_language_server`. Java uses `nvim-jdtls` (see `java.lua`) rather than this list.

`kotlin_language_server` has a known bug (v1.3.13): it crashes with `-32603` on `documentHighlight` and `documentFormatting` requests when running outside a full Gradle/Maven project (unresolved classpath). Workarounds applied:
- `on_attach` clears `documentHighlightProvider`, `documentFormattingProvider`, `documentRangeFormattingProvider` so `supports_method` returns false for all callers (including `snacks.words` which independently sends highlight requests)
- `LspAttach` callback also guards highlight autocmd with `client.name ~= 'kotlin_language_server'` as a belt-and-suspenders check
- `format_on_save` returns `nil` for kotlin (no save formatting); use `<leader>f` for ktlint instead

Capabilities come from `blink.cmp`. LSP keymaps are set in the `LspAttach` autocmd:

| Key | Action |
|-----|--------|
| `gd` | Go to definition (Telescope) |
| `gr` | Go to references (Telescope) |
| `gi` | Go to implementation (Telescope) |
| `gt` | Go to type definition (Telescope) |
| `<leader>gd` | Go to declaration |
| `<leader>ca` | Code action |
| `<leader>rn` | Rename symbol |
| `<leader>h` | Hover docs |
| `<leader>pd` / `<leader>nd` | Previous/Next diagnostic |
| `<leader>e` | Show diagnostic float (focused) |
| `<leader>th` | Toggle inlay hints |
| `<leader>ds` / `<leader>ws` | Document/Workspace symbols |

Diagnostic display: virtual text with `●` prefix, floating windows on `CursorHold` (unfocused), rounded borders.

## java.lua

Java LSP via `mfussenegger/nvim-jdtls`. Lazy-loaded on `ft = java`. A `FileType java` autocmd calls `require('jdtls').start_or_attach` with:
- `cmd = { 'jdtls', '-data', workspace_dir }` — workspace is `~/.local/share/eclipse/<project-name>` (project name derived from `getcwd()` at attach time, giving per-project isolation)
- `root_dir` — detected from `.git`, `pom.xml`, `build.gradle`, `build.gradle.kts`, `settings.gradle`, `settings.gradle.kts`
- `capabilities` from `blink.cmp`

jdtls binary installed from AUR (`yay -S jdtls`). Not wired through `vim.lsp.enable` — `nvim-jdtls` manages the lifecycle directly.

## blink.lua

Completion via `blink.cmp` (replaces nvim-cmp). Sources: LSP, path, snippets, buffer. Default preset keymap.

## debug.lua

DAP setup for Go using `nvim-dap` + `nvim-dap-ui` + `nvim-dap-go`.

Go debugger connects to delve on `127.0.0.1:2345` (remote attach mode). `<leader>da` attaches to a running dlv instance.

| Key | Action |
|-----|--------|
| `<F5>` | Start/Continue |
| `<F1>/<F2>/<F3>` | Step into/over/out |
| `<F7>` | Toggle DAP UI |
| `<leader>b` / `<leader>B` | Toggle / conditional breakpoint |
| `<leader>dr` / `<leader>dt` | Restart / Terminate |
| `<leader>da` | Attach to running dlv (port 2345) |
| `<leader>dh` / `<leader>dk` / `<leader>dp` | Hover / Scopes / Preview |

DAP UI opens automatically on session start, closes on terminate/exit. Layout: scopes+breakpoints bottom, REPL right.

## snacks.lua

Central hub for many UX features via `folke/snacks.nvim`.

**Enabled modules**: `bigfile`, `quickfile`, `picker` (with custom project confirm), `dashboard`, `indent`, `lazygit`, `words`.

**Dashboard keys**: `r` recent files, `n` new file, `f` file explorer, `p` projects, `c` config files, `z` Lazy, `q` quit.

**Git keymaps** (global):
| Key | Action |
|-----|--------|
| `<leader>gg` | Open lazygit |
| `<leader>gb` | Blame current line |
| `<leader>gf` | File history in lazygit |
| `<leader>gl` | Full log in lazygit |
| `<leader>hb` | Return to dashboard |

**Toggle keymaps** (`\<key>` — set on `VeryLazy`):

`\s` spell · `\w` wrap · `\c` cursorline · `\l` list chars · `\g` ignorecase · `\r` relative numbers · `\d` diagnostics · `\n` line numbers · `\-` conceallevel · `\/` treesitter · `\b` background · `\h` inlay hints · `\i` indent guides · `\z` zen · `\o` word highlighting · `\p` autopairs · `\T` trailing whitespace removal

**Project picker**: selecting a project calls `vim.cmd('cd ...')` and emits an OSC 7 escape sequence so the terminal follows the directory change.

## telescope.lua

Fuzzy finder. Extensions loaded: `fzf`, `ui-select`.

| Key | Action |
|-----|--------|
| `<leader>sf` | Find files |
| `<leader>sg` | Live grep |
| `<leader>sw` | Grep current word |
| `<C-p>` | Git-tracked files only |
| `<leader>sh` | Help tags |
| `<leader>sk` | Keymaps |
| `<leader>sd` | Diagnostics |
| `<leader>sr` | Resume last picker |
| `<leader>s.` | Recent files |
| `<leader><leader>` | Open buffers |
| `<leader>sp` | Project switcher (delegates to `Snacks.picker.projects()`) |
| `<leader>st` | Todo comments |
| `<leader>sn` | Search neovim config files |
| `<leader>/` | Fuzzy search current buffer |
| `<leader>s/` | Live grep open files |

## treesitter.lua

Auto-installs parsers. Pre-installed: bash, c, diff, html, lua, luadoc, markdown, query, vim, vimdoc, go, rust, zig, dockerfile. Includes a custom **templ** parser from `virschmann/tree-sitter-templ`.

## toggleterm.lua

Floating terminal via `<C-\>`. Additional keymaps:

| Key | Action |
|-----|--------|
| `<leader>tt` | Horizontal terminal |
| `<leader>tv` | Vertical terminal |
| `<leader>tf` | Large floating terminal |
| `<A-hjkl>` | Window navigation from terminal or normal mode |

## gitsigns.lua

Sign column git indicators. Keymaps (buffer-local):

| Key | Action |
|-----|--------|
| `<leader>gdi` | Diff against index |
| `<leader>gdc` | Diff against last commit |
| `<leader>tD` | Preview hunk inline |

## config-local.lua

Loads `.nvim.lua` or `.nvimrc` from the project root when present. Used for per-project settings like Go build tags. Hash-verified on first load.

## persistence.lua / undotree.lua / pomo.lua

- **persistence**: session save/restore
- **undotree**: toggle with `<leader>u` (keymap in `lua/scripts/keymaps.lua`)
- **pomo**: pomodoro timer; timers browsable via `<leader>pt` (Telescope extension)

## markdown.lua

Two plugins for markdown files:

**`render-markdown.nvim`** — visual in-editor rendering of headers, bold/italic, tables, code blocks, checkboxes, and list bullets using treesitter + extmarks. Loaded on `ft = markdown`.

**`image.nvim`** — renders images inline in the terminal via Kitty Graphics Protocol. Configured for `backend = 'kitty'`, markdown/neorg integrations disabled (rendering is handled manually). Requires the `magick` LuaRock (Lua 5.1) and `imagemagick` system package.

Mermaid diagram rendering is implemented in the `config` function of `image.nvim`:
- `find_mermaid_blocks(buf)` walks the treesitter AST via `node:iter_children()` to find `fenced_code_block` nodes with info string `mermaid`, returns `{ code, row }[]`
- `render_mermaid(buf)` writes each block to `~/.cache/nvim/mermaid/<buf>_<row>.mmd`, runs `mmdc` asynchronously, then renders the output PNG at the code block's row
- Autocmds: `BufReadPost`/`BufWritePost *.md` → render, `BufWipeout *.md` → clear
- A `vim.schedule` loop at the end of `config` catches already-open markdown buffers (because `ft`-triggered lazy-load fires after `BufReadPost` has already run)

## mini.lua

Two mini.echasnovski plugins:
- **`mini.pairs`** — auto-closes brackets, quotes, etc. Toggle with `\p` (snacks toggle reads `vim.b.minipairs_disable`).
- **`mini.surround`** — add/delete/replace surrounds. Default mappings: `sa` add · `sd` delete · `sr` replace.

## lualine.lua

Status line with rose-pine theme. Global statusline. Shows: mode, branch, diff, diagnostics, relative filename, encoding, filetype, progress, location. Extensions: toggleterm, fugitive, lazy.

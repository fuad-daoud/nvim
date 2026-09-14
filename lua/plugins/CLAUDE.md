# CLAUDE.md — lua/plugins/

Each file returns a lazy.nvim plugin spec. All files are auto-imported by `{ import = 'plugins' }` in `lua/scripts/lazy.lua`.

## lsp.lua

Configures `nvim-lspconfig` directly — **no Mason**. Servers must be installed via system packages (see root CLAUDE.md).

Active servers: `lua_ls`, `gopls`, `zls`, `tailwindcss`, `html`, `cssls`, `jsonls`, `yamlls`, `bashls`.

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

## diffview.lua

PR / branch review via `sindrets/diffview.nvim`. Lazy-loaded on its commands. File panel is 45 columns wide (`<leader>b` hides it; `<C-Left>`/`<C-Right>` resize). All logic lives in `lua/pr_review.lua`; the spec only wires keymaps, the `-` file-panel override, and the `view_closed` hook.

`:PrReview [number]` — with a number, runs `gh pr checkout <number>` first (aborts with a notification on failure). Then `gh pr view --json id,baseRefName` gives the PR node id and base (falls back to `origin/master` with no PR), fetches the base, runs `:DiffviewOpen origin/<base>...HEAD`, and asynchronously loads GitHub's per-file `viewerViewedState` via `gh api graphql`.

`:PrReview [number] --commits` — same checkout/base detection, then `:DiffviewFileHistory --range=origin/<base>...HEAD --reverse`: the PR's commits oldest-first, each expandable into its files. No viewed marks here (GitHub has no per-commit viewed state).

| Key | Action |
|-----|--------|
| `<leader>gv` | `:PrReview` — diffview of current branch vs its PR base |
| `<leader>gc` | `:PrReview --commits` — commit-by-commit history of the PR |
| `<leader>gV` | `:DiffviewClose` |
| `-` (file panel) | On a file: toggle its **Viewed** state on GitHub (`markFileAsViewed` / `unmarkFileAsViewed`) and move to the next entry. On a directory: mark every file under it, or unmark all if every one is already viewed — aliased GraphQL mutations in batches of 25 (GitHub rejects ~55+ per request with "Resource limits for this query exceeded"). Optimistic, each failed batch reverted |

Viewed files — and *collapsed* directories whose files are all viewed (matching diffview's `only_folded` folder status) — show `✓` in place of the status letter and are dimmed; the "Changes" title gets a `✓ n/total` counter. Decorations are extmarks painted by a wrapper around `FilePanel:redraw`. On a non-PR branch `-` just notifies.

Inside diffview (stock bindings): `<Tab>`/`<S-Tab>` next/prev file · `]c`/`[c` hunks · `g?` help. The right-hand side is a real buffer, so LSP (`gd`, hover) works while reading.

### AI companion (`lua/pr_companion.lua`)

One headless Claude Code session per PR (`claude -p --model opus --effort high`). **Strictly read-only**: `--restricted --tools Read,Grep,Glob,Bash` (restricted mode ignores settings files — the user's global `defaultMode = auto` would otherwise auto-approve everything — and its sandbox refuses file writes), `--allowedTools` limited to `git *` and `gh pr view|diff|checks|list`, `gh issue view`, `gh run *`, `gh search`, and `--disallowedTools` for every mutating git subcommand (`checkout`, `reset`, `stash`, `commit`, `push`, `-c`, `-C`, …). Requests are killed after 10 min; the pane placeholder shows elapsed time. Sessions keyed by PR URL in `stdpath('data')/pr_review/sessions.json`; the conversation pane is mirrored to `<owner>_<repo>_<n>.md` beside it and reloads with the PR.

- `:PrReview` on a PR with no session → `vim.ui.select` popup "Bootstrap AI companion?" — Yes runs the bootstrap (PR description + orient via `git diff`, replies with a summary into the pane); No records `declined` so it stops asking.
- `:PrCompanion [bootstrap|toggle|chat|reset]` — bare: bootstrap if none, else toggle the pane. `reset` forgets the session + pane file.
- `:PrAsk` / `<leader>ga` — visual: sends the selected lines as `File: path  lines a–b  (PR head|base <branch>)` + fenced code + your question (`vim.ui.input`); normal: question only. Answer replaces the `_thinking…_` placeholder in the pane. One request at a time.
- `<leader>gA` — toggle the pane (right split, 60 cols, markdown; `q` closes).
- `:PrChat` — toggleterm float running `claude --resume <id>` for a long conversation with the same memory.

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

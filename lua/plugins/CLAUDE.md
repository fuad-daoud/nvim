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

Two plugins: `mfussenegger/nvim-jdtls` (Java LSP) + `JavaHello/spring-boot.nvim` (Spring Boot features). Both lazy-loaded on `ft = java`.

**spring-boot.nvim** (`JavaHello/spring-boot.nvim`):
- Provides the message bridge between spring-boot-ls and jdtls (spring-boot-ls cannot talk to jdtls without this — it crashes on init with a NullPointerException on `getExecuteCommandProvider()`)
- `init` sets `vim.g.spring_boot.jdt_extensions_path = ~/.local/share/spring-boot-ls/jars` — the 5 Eclipse plugin JARs that jdtls must load as bundles
- `opts.ls_path` points to the standalone spring-boot-language-server exec JAR at `~/.local/share/spring-boot-ls/spring-boot-language-server.jar`
- **Do NOT call `require('spring_boot').java_extensions()` without a path** — it falls back to Mason/VSCode lookup and returns empty. Instead, glob `~/.local/share/spring-boot-ls/jars/*.jar` directly (see `java.lua`). The `is_bundle_jar` name filter also rejects versioned BOOT-INF names like `reactor-core-3.x.jar` vs expected `io.projectreactor.reactor-core.jar`.
- `require('spring_boot').init_lsp_commands()` called in `on_attach` registers Neovim-side handlers for Spring Boot LSP commands

**nvim-jdtls**: A `FileType java` autocmd calls `require('jdtls').start_or_attach` with:
- `cmd = { 'jdtls', '-data', workspace_dir }` — workspace is `~/.local/share/eclipse/<project-name>`
- `root_dir` — detected from `.git`, `pom.xml`, `build.gradle`, `build.gradle.kts`, `settings.gradle`, `settings.gradle.kts`
- `capabilities` from `blink.cmp`
- `init_options.bundles` — java-debug plugin JAR (`/usr/share/java-debug/com.microsoft.java.debug.plugin.jar`, from AUR `java-debug`) + spring-boot Eclipse plugin JARs
- `on_attach` — calls `setup_dap` + `setup_dap_main_class_configs` for Java debugging

jdtls binary installed from AUR (`yay -S jdtls`). Not wired through `vim.lsp.enable` — `nvim-jdtls` manages the lifecycle directly.

**5 Eclipse plugin JARs required in `~/.local/share/spring-boot-ls/jars/`** — copy from the matching STS4 VSIX `extension/jars/`:
`jdt-ls-commons.jar`, `jdt-ls-extension.jar`, `io.projectreactor.reactor-core.jar`, `org.reactivestreams.reactive-streams.jar`, `sts-gradle-tooling.jar`

**Critical**: all 5 must come from the VSIX `extension/jars/`, NOT from `BOOT-INF/lib/`. The `BOOT-INF/lib` versions have plain Maven bundle names (e.g. `reactive-streams` vs required `org.reactivestreams.reactive-streams`) which fail OSGi resolution and silently kill the classpath bridge. The VSIX version must match the jdt-ls-commons build timestamp (check `Bundle-Version` in its `META-INF/MANIFEST.MF`).

**OSGi bundle state cache**: stored at `~/.eclipse/<hash>/configuration/org.eclipse.osgi/` (hash from jdtls install path). If extension bundles fail to load after changing JARs, stale state causes higher-version failed bundles to win resolution. Clear with: `rm -rf ~/.eclipse/*/configuration/org.eclipse.osgi`. Check `~/.local/share/eclipse/<project>/.metadata/.log` for `Bundle startup failed` entries.

**Bean/endpoint pickers use ripgrep** (not spring-boot-ls `workspace/symbol`). The spring-boot-ls `@+`/`@/` queries stream results as LSP `$/progress` partial-result notifications and require the jdtls classpath bridge to be fully initialised — unreliable in practice. The rg approach is instant and has no server dependency.

**`<leader>sjh` hover** queries spring-boot-ls directly (bypasses jdtls Javadoc). Works statically once the jdtls↔spring-boot-ls classpath bridge is up — shows bean candidates on `@Autowired` fields without a running app. With actuator running it also shows live-wired bean info.

Keymaps (buffer-local, Java only):

| Key | Action |
|-----|--------|
| `<leader>sjb` | Spring beans — rg scan for `@(Component\|Service\|Repository\|Controller\|RestController\|Configuration\|Bean)` |
| `<leader>sje` | Spring endpoints — rg scan for `@(Get\|Post\|Put\|Delete\|Patch\|Request)Mapping` |
| `<leader>sjh` | Spring Boot hover — bean candidates (static) + live actuator info (spring-boot client only) |
| `<leader>sjo` | Organize imports |
| `<leader>sjv` | Extract variable |
| `<leader>sjm` | Extract method |
| `<leader>sjc` | Extract constant |
| `<leader>sjd` | Pick and debug test (DAP) |

DAP keymaps (`<F5>`, `<F1>`–`<F3>`, `<leader>b`, etc.) from `debug.lua` work for Java automatically once `setup_dap` runs.

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

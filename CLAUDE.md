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
   - AUR LSPs: `zls tailwindcss-language-server jdtls kotlin-language-server java-debug`
   - Formatters: `prettier stylua shfmt shellcheck yamllint prettierd actionlint jq google-java-format ktlint`
   - Spring Boot LS (manual): build `spring-boot-language-server-*-exec.jar` from https://github.com/spring-projects/sts4 and copy to `~/.local/share/spring-boot-ls/spring-boot-language-server.jar`. Copy the 5 Eclipse plugin JARs from the matching STS4 VSIX `extension/jars/` into `~/.local/share/spring-boot-ls/jars/`: `jdt-ls-commons.jar`, `jdt-ls-extension.jar`, `io.projectreactor.reactor-core.jar`, `org.reactivestreams.reactive-streams.jar`, `sts-gradle-tooling.jar`. Do NOT extract these from the fat JAR's `BOOT-INF/lib/` — those JARs have wrong OSGi bundle symbolic names and silently break the jdtls↔spring-boot-ls classpath bridge.
   - Go tools: `goimports`, `golines`, `gomodifytags`, `dlv`, `templ` via `go install`
   - Markdown/mermaid rendering: `imagemagick luarocks` via pacman, then `luarocks --lua-version 5.1 install magick --local` and `npm install -g @mermaid-js/mermaid-cli`

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

### Markdown Notes

`init.lua` prepends luarocks Lua 5.1 paths to `package.path`/`package.cpath` so Neovim (LuaJIT) can load the `magick` LuaRock needed by `image.nvim`.

`lua/plugins/treesitter.lua` patches the `set-lang-from-info-string!` treesitter directive with `{ force = true }` because nvim-treesitter (archived) was written for an older Neovim API where `match[id]` returned a bare `TSNode`; Neovim 0.11+ passes `(TSNode|nil)[]`. The patch unwraps the array form safely.

### Shared Utilities

`lua/utils.lua` — small module for helpers shared across plugin specs. Currently exports `emit_osc7(cwd?)` which writes an OSC 7 terminal CWD notification (used by snacks project picker).

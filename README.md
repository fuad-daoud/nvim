# My Neovim Config

A personal Neovim configuration built on a [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) foundation, with lazy.nvim for plugin management, no Mason, and a rose-pine moon colorscheme.

---

## Prerequisites

Run the installer on Arch or Ubuntu 22.04+:

```sh
./install.sh
```

This detects your distro and installs all required system packages: LSPs, formatters, Go tools, npm/Node, Lua tooling, and markdown/mermaid rendering dependencies. For details, see the root `CLAUDE.md`.

On first launch, lazy.nvim bootstraps itself and installs all plugins automatically.

---

## Structure

```
init.lua                  ← entry point
lua/
  scripts/
    setup.lua             ← globals (mapleader, nerd font)
    lazy.lua              ← lazy.nvim bootstrap + inline plugins
    autocmd.lua           ← autocommands
    keymaps.lua           ← global keymaps
    opt.lua               ← vim options
  plugins/
    *.lua                 ← one plugin spec per file
  utils.lua               ← shared helpers (OSC 7, etc.)
install.sh                ← cross-distro installer
.stylua.toml              ← Lua formatter config
```

### Load Order

`init.lua` loads scripts in this sequence:

1. **`setup.lua`** — sets `mapleader`/`maplocalleader` to `<Space>` and enables Nerd Font icons
2. **`lazy.lua`** — bootstraps lazy.nvim, registers inline plugins, imports `lua/plugins/`
3. **`autocmd.lua`** — registers all autocommands
4. **`keymaps.lua`** — registers global keymaps
5. **`opt.lua`** — sets vim options

Setup must run before lazy so that `mapleader` is set before any plugin keymaps are registered.

---

## Colorscheme

[rose-pine](https://github.com/rose-pine/neovim) **moon** variant with transparency, bold/italic styles, and a custom palette override (`rose = '#000000'`). All DAP, gitsigns, and diagnostic highlights are mapped to rose-pine palette tokens for visual consistency.

---

## Formatting

Lua files are formatted with **stylua**. CI checks formatting on PRs.

```sh
stylua --check .   # verify
stylua .           # fix
```

Config (`.stylua.toml`): 160-column, 2-space indent, single quotes, no call parentheses.

---

## Further Documentation

- [`lua/scripts/README.md`](lua/scripts/README.md) — options, keymaps, and autocmds reference
- [`lua/plugins/README.md`](lua/plugins/README.md) — every plugin, its purpose, and all keymaps

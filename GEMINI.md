# Neovim Configuration (GEMINI.md)

This directory contains a highly customized Neovim configuration, managed as a Git submodule.

## Project Overview

- **Distribution:** Based on `kickstart.nvim`.
- **Package Manager:** `lazy.nvim`.
- **Primary Goal:** A fast, full-featured development environment with a focus on LSP and performance.

## Core Architecture

- **No Mason:** LSP servers, formatters, and linters are installed via the system package manager (see `.setup/installing-pkgs.sh` or `CLAUDE.md`) rather than using Mason. This ensures consistency across the system.
- **Load Order:**
  1. `scripts/setup.lua`: Leader keys (`space`).
  2. `scripts/lazy.lua`: Plugin bootstrapping.
  3. `scripts/autocmd.lua`: Custom autocommands.
  4. `scripts/keymaps.lua`: Global keybindings.
  5. `scripts/opt.lua`: Vim options.

## Key Plugin Categories

- **LSP/Completion:** `blink.cmp` (completion), `conform.nvim` (formatting), `lspconfig`.
- **UI:** `lualine`, `bufferline`, `noice`, `snacks`, `telescope`.
- **Aesthetics:** `rose-pine` colorscheme.
- **Utilities:** `gitsigns`, `undotree`, `toggleterm`, `persistence` (session management).

## Development Conventions

- **Formatting:** Lua files are formatted with `stylua` (2-space indent, 160-col).
- **Submodules:** This entire directory is a submodule. Updates should be handled via `git submodule`.
- **LSP Config:** Located in `lua/plugins/lsp.lua`. Servers are manually configured in `lspconfig`.

## Context Reference

For extremely detailed information on specific plugins or architecture, see:
- `CLAUDE.md`: Broad overview and setup instructions.
- `lua/plugins/README.md` & `lua/plugins/CLAUDE.md`: Plugin-specific details.
- `lua/scripts/README.md` & `lua/scripts/CLAUDE.md`: Script-specific details.

# PR Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Per-PR headless Claude Code session, bootstrapped from `:PrReview`, queried about selected diff lines from a persistent markdown pane.

**Architecture:** `lua/pr_companion.lua` owns sessions (JSON on disk), the `claude -p` calls (`vim.system`, stdin prompts), the pane buffer, and its persistence. `pr_review.lua` only hands over PR metadata. Spec: `docs/superpowers/specs/2026-09-14-pr-companion-design.md`.

**Tech Stack:** Neovim 0.11 (`vim.system`, `vim.ui.select/input`), `claude` CLI 2.1.x (`-p`, `--session-id`, `--resume`, `--output-format json`), toggleterm, render-markdown.

## Global Constraints

- stylua clean before each commit.
- Read-only tool allowlist for the companion: `Read Grep Glob "Bash(git *)" "Bash(gh *)"`.
- Model `opus`, effort `high` on every call.

---

### Task 1: `pr_companion.lua` + wiring

**Files:** Create `lua/pr_companion.lua`; modify `lua/pr_review.lua` (`M.open`), `lua/plugins/diffview.lua` (keys, cmd, config).

- [ ] Step 1: write module per spec (sessions store, `offer`, `bootstrap`, `ask`, `toggle`, `chat`, `reset`, `setup` registering `:PrCompanion`, `:PrAsk`).
- [ ] Step 2: `pr_review.open` → fetch `id,baseRefName,number,title,body,url`; after `DiffviewOpen` call `require('pr_companion').offer(pr)`.
- [ ] Step 3: spec: add `PrCompanion`, `PrAsk` to `cmd`; keys `<leader>ga` (n, x), `<leader>gA`; `config` calls `require('pr_companion').setup()`.
- [ ] Step 4: `stylua --check .`; headless: commands exist, `uuid()` matches `^%x{8}-%x{4}-4%x{3}-[89ab]%x{3}-%x{12}$`.
- [ ] Step 5: live bootstrap on PR 464 (headless nvim, wait for `claude`), assert `sessions.json` has the id and the markdown file has a `## Summary`; live ask with a range, assert answer replaced the placeholder; `claude -p --resume <id> "what did I ask last?"` from shell confirms shared history.
- [ ] Step 6: commit `feat: per-PR Claude Code review companion`.

### Task 2: Docs

- [ ] `lua/plugins/CLAUDE.md` diffview section: commands, keymaps, session storage, allowlist. Root `CLAUDE.md` shared utilities: `lua/pr_companion.lua`.
- [ ] commit `docs: document PR companion`.

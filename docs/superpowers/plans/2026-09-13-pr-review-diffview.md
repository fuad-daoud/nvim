# PR Review via diffview.nvim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `sindrets/diffview.nvim` plus a `:PrReview [number]` command so a GitHub PR can be checked out and read file-by-file, side-by-side, from Neovim.

**Architecture:** One lazy.nvim spec file `lua/plugins/diffview.lua`, auto-imported like every other file in `lua/plugins/`. The spec's `config` defines a `pr_base()` helper (asks `gh` for the PR base branch, falls back to `origin/master`) and the `:PrReview` user command. Keymaps live in the spec's `keys` table so they lazy-load the plugin.

**Tech Stack:** Neovim 0.11 (`vim.system`), lazy.nvim, `gh` CLI, `sindrets/diffview.nvim`.

## Global Constraints

- All Lua formatted with stylua (`.stylua.toml`: 160-col, 2-space, single quotes, no call parentheses). `stylua --check .` must pass before every commit.
- No Mason; no new system dependencies beyond `gh` (already installed and authed).
- Keymaps `<leader>gv` / `<leader>gV` are currently unused (verified with grep).
- Spec: `docs/superpowers/specs/2026-09-13-pr-review-diffview-design.md`.

---

### Task 1: diffview.nvim spec with `pr_base()`, `:PrReview`, and keymaps

**Files:**
- Create: `lua/plugins/diffview.lua`
- Modify: `lua/plugins/CLAUDE.md` (append a `## diffview.lua` section)

**Interfaces:**
- Consumes: `gh` CLI on `$PATH`; git remote named `origin`.
- Produces: user command `:PrReview [number]`; keymaps `<leader>gv`, `<leader>gV`.

- [ ] **Step 1: Write the plugin spec**

```lua
-- lua/plugins/diffview.lua
-- Side-by-side diff review of a PR. Workflow: `:PrReview 464` → <Tab>/<S-Tab> files, ]c/[c hunks, `-` toggle viewed.

-- Base branch of the PR on the current branch (`origin/<base>`), or `origin/master` if gh can't tell.
local function pr_base()
  local res = vim.system({ 'gh', 'pr', 'view', '--json', 'baseRefName', '-q', '.baseRefName' }, { text = true }):wait()
  local base = res.code == 0 and vim.trim(res.stdout or '') or ''
  if base == '' then
    base = 'master'
  end
  return 'origin/' .. base
end

local function pr_review(opts)
  local number = opts.args
  if number ~= '' then
    local res = vim.system({ 'gh', 'pr', 'checkout', number }, { text = true }):wait()
    if res.code ~= 0 then
      vim.notify('gh pr checkout ' .. number .. ' failed:\n' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
  end
  local base = pr_base()
  vim.system({ 'git', 'fetch', 'origin', base:gsub('^origin/', '') }, { text = true }):wait()
  vim.cmd('DiffviewOpen ' .. base .. '...HEAD')
end

return {
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory', 'PrReview' },
    keys = {
      { '<leader>gv', '<cmd>PrReview<cr>', desc = '[G]it re[V]iew PR (diffview)' },
      { '<leader>gV', '<cmd>DiffviewClose<cr>', desc = '[G]it close re[V]iew' },
    },
    opts = {
      enhanced_diff_hl = true,
      view = { merge_tool = { layout = 'diff3_mixed' } },
    },
    config = function(_, opts)
      require('diffview').setup(opts)
      vim.api.nvim_create_user_command('PrReview', pr_review, { nargs = '?', desc = 'Checkout a GitHub PR (optional number) and open diffview against its base' })
    end,
  },
}
```

Note: `base:gsub(...)` returns two values; wrapping it in the table constructor as a single positional element keeps only the first, which is what we want. The `git fetch` result is deliberately ignored (non-fatal per spec).

- [ ] **Step 2: Format check**

Run: `stylua --check lua/plugins/diffview.lua`
Expected: no output, exit 0. If it fails, run `stylua lua/plugins/diffview.lua`.

- [ ] **Step 3: Headless load test**

Run:
```bash
nvim --headless "+Lazy! sync" +qa 2>&1 | tail -3
nvim --headless -c 'lua print(vim.fn.exists(":PrReview"))' -c 'lua require("diffview")' -c 'lua print(vim.fn.exists(":PrReview"))' +qa 2>&1 | tail -3
```
Expected: sync installs `diffview.nvim` without error. Second command prints `2` on the first `exists` (lazy.nvim registers the stub command) and `2` after load (real command). Any Lua error means the spec is broken.

- [ ] **Step 4: Manual test on a real PR**

In a terminal inside a repo with a GitHub remote that has an open PR: `nvim`, then `:PrReview <number>`. Expected: branch checked out, diffview tab opens with a file panel on the left and side-by-side diff. `<Tab>` moves to next file; `<leader>gV` closes. On a non-PR branch `<leader>gv` opens diffview against `origin/master`.

- [ ] **Step 5: Document in `lua/plugins/CLAUDE.md`**

Append after the `## gitsigns.lua` section:

```markdown
## diffview.lua

PR / branch review via `sindrets/diffview.nvim`. Lazy-loaded on its commands.

`:PrReview [number]` — with a number, runs `gh pr checkout <number>` first (aborts with a notification on failure). Then detects the PR base branch via `gh pr view --json baseRefName` (falls back to `origin/master`), fetches it, and runs `:DiffviewOpen origin/<base>...HEAD`.

| Key | Action |
|-----|--------|
| `<leader>gv` | `:PrReview` — diffview of current branch vs its PR base |
| `<leader>gV` | `:DiffviewClose` |

Inside diffview (stock bindings): `<Tab>`/`<S-Tab>` next/prev file · `]c`/`[c` hunks · `-` toggle viewed · `g?` help. The right-hand side is a real buffer, so LSP (`gd`, hover) works while reading.
```

- [ ] **Step 6: Commit**

```bash
stylua --check .
git add lua/plugins/diffview.lua lua/plugins/CLAUDE.md lazy-lock.json
git commit -m "feat: add diffview.nvim with :PrReview for GitHub PR review"
```

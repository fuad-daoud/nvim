# GitHub-synced Viewed State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Toggle GitHub's per-file "Viewed" state from the diffview file panel with `-`, showing `✓` + dimmed rows and a `✓ n/total` counter.

**Architecture:** New module `lua/pr_review.lua` holds PR state (`pr_id`, `viewed` set), the `:PrReview` open flow, GraphQL load/toggle via `gh api graphql`, and a `decorate()` that paints extmarks after every `FilePanel:redraw`. `lua/plugins/diffview.lua` shrinks to a spec that wires keymap/hook/setup to the module.

**Tech Stack:** Neovim 0.11 (`vim.system`, extmarks), lazy.nvim, `gh` CLI GraphQL, diffview.nvim internals (`diffview.lib`, `diffview.scene.views.diff.file_panel`, `diffview.actions`).

## Global Constraints

- stylua (`.stylua.toml`: 160-col, 2-space, single quotes, no call parentheses); `stylua --check .` before every commit. Binary: `/tmp/claude-1000/-home-fuad--config-nvim/e156e800-466b-4722-8990-a1ae25717d75/scratchpad/stylua` (not installed system-wide).
- Spec: `docs/superpowers/specs/2026-09-13-pr-viewed-state-design.md`.
- Verified facts: diffview user keymaps override defaults by `mode+lhs`; `FileEntry` has `.basename`, `DirData` has `.name`; `Panel:redraw()` is where the buffer is written; `panel.components.comp:deep_some(fn)` walks the component tree; `panel.components.working.title.comp.lstart` is the "Changes (n)" line; GraphQL `node(id:$id){ ... on PullRequest { files(first:100, after:$after){...} } }` works with the id from `gh pr view --json id`.

---

### Task 1: `lua/pr_review.lua` module + thin plugin spec

**Files:**
- Create: `lua/pr_review.lua`
- Modify: `lua/plugins/diffview.lua` (replace whole file)

**Interfaces:**
- Produces: `require('pr_review')` with `open(number?)`, `load_viewed()`, `toggle_viewed()`, `decorate(panel)`, `reset()`, `setup()`.

- [ ] **Step 1: Write the module**

```lua
-- lua/pr_review.lua
-- PR review helpers on top of diffview: `:PrReview` open flow and GitHub-synced "viewed" marks.
local M = {}

local ns = vim.api.nvim_create_namespace 'pr_review'
local state = { pr_id = nil, viewed = {} }

local function gh(args, opts, cb)
  return vim.system(vim.list_extend({ 'gh' }, args), vim.tbl_extend('force', { text = true }, opts or {}), cb)
end

local function graphql(query, vars, cb)
  local args = { 'api', 'graphql', '-f', 'query=' .. query }
  for k, v in pairs(vars) do
    table.insert(args, '-F')
    table.insert(args, k .. '=' .. v)
  end
  gh(args, nil, function(res)
    vim.schedule(function()
      cb(res.code == 0 and vim.json.decode(res.stdout) or nil, res.stderr)
    end)
  end)
end

local function current_panel()
  local view = require('diffview.lib').get_current_view()
  return view and view.panel
end

function M.reset()
  state = { pr_id = nil, viewed = {} }
end

-- Paint ✓ + dimmed rows for viewed files and a counter on the "Changes" title. Runs after every panel redraw.
function M.decorate(panel)
  local buf = panel.bufid
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not state.pr_id or not panel.components then
    return
  end
  local total, done = 0, 0
  panel.components.comp:deep_some(function(comp)
    if comp.name ~= 'file' then
      return false
    end
    total = total + 1
    if state.viewed[comp.context.path] then
      done = done + 1
      vim.api.nvim_buf_set_extmark(buf, ns, comp.lstart, 0, { virt_text = { { '✓', 'DiffviewFilePanelInsertions' } }, virt_text_pos = 'overlay' })
      local line = vim.api.nvim_buf_get_lines(buf, comp.lstart, comp.lstart + 1, false)[1] or ''
      vim.api.nvim_buf_set_extmark(buf, ns, comp.lstart, 0, { end_col = #line, hl_group = 'Comment', priority = 200 })
    end
    return false
  end)
  local title = panel.components.working.title.comp
  if title and title.lstart then
    vim.api.nvim_buf_set_extmark(buf, ns, title.lstart, 0, { virt_text = { { ' ✓ ' .. done .. '/' .. total, 'DiffviewFilePanelCounter' } }, virt_text_pos = 'eol' })
  end
end

local function redraw_panel()
  local panel = current_panel()
  if panel then
    panel:redraw()
  end
end

local files_query = [[
query($id:ID!,$after:String){ node(id:$id){ ... on PullRequest {
  files(first:100, after:$after){ pageInfo{hasNextPage endCursor} nodes{ path viewerViewedState } } } } }]]

-- Pull viewerViewedState for every file in the PR (paginated), then redraw.
function M.load_viewed()
  local pr_id = state.pr_id
  local function page(after)
    local vars = { id = pr_id }
    if after then
      vars.after = after
    end
    graphql(files_query, vars, function(data, err)
      if state.pr_id ~= pr_id then
        return -- view was closed / reopened meanwhile
      end
      local files = data and data.data and data.data.node and data.data.node.files
      if not files then
        vim.notify('pr_review: failed to load viewed state\n' .. (err or ''), vim.log.levels.WARN)
        return
      end
      for _, f in ipairs(files.nodes) do
        state.viewed[f.path] = f.viewerViewedState == 'VIEWED' or nil
      end
      if files.pageInfo.hasNextPage then
        page(files.pageInfo.endCursor)
      else
        redraw_panel()
      end
    end)
  end
  page(nil)
end

-- `-` in the file panel: flip the file under the cursor on GitHub (optimistic), then advance.
function M.toggle_viewed()
  local panel = current_panel()
  local item = panel and panel:get_item_at_cursor()
  if not item or not item.basename then
    return
  end
  if not state.pr_id then
    vim.notify('pr_review: not on a PR branch', vim.log.levels.INFO)
    return
  end
  local path, pr_id = item.path, state.pr_id
  local now_viewed = not state.viewed[path]
  state.viewed[path] = now_viewed or nil
  panel:redraw()
  require('diffview.actions').next_entry()
  local mutation = now_viewed and 'markFileAsViewed' or 'unmarkFileAsViewed'
  local query = 'mutation($id:ID!,$path:String!){ ' .. mutation .. '(input:{pullRequestId:$id,path:$path}){ clientMutationId } }'
  graphql(query, { id = pr_id, path = path }, function(data, err)
    if state.pr_id ~= pr_id then
      return
    end
    if not data or data.errors then
      state.viewed[path] = (not now_viewed) or nil
      redraw_panel()
      vim.notify('pr_review: ' .. mutation .. ' failed\n' .. (err ~= '' and err or vim.inspect(data and data.errors)), vim.log.levels.ERROR)
    end
  end)
end

-- `:PrReview [number]`: checkout, detect base, fetch, open diffview, then load viewed marks.
function M.open(number)
  if number and number ~= '' then
    local res = gh({ 'pr', 'checkout', number }):wait()
    if res.code ~= 0 then
      vim.notify('gh pr checkout ' .. number .. ' failed:\n' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
  end
  M.reset()
  local base = 'master'
  local res = gh({ 'pr', 'view', '--json', 'id,baseRefName' }):wait()
  if res.code == 0 then
    local ok, pr = pcall(vim.json.decode, res.stdout)
    if ok and pr.id then
      state.pr_id = pr.id
      base = pr.baseRefName
    end
  end
  vim.system({ 'git', 'fetch', 'origin', base }, { text = true }):wait()
  vim.cmd('DiffviewOpen origin/' .. base .. '...HEAD')
  if state.pr_id then
    M.load_viewed()
  end
end

function M.setup()
  local FilePanel = require('diffview.scene.views.diff.file_panel').FilePanel
  local redraw = FilePanel.redraw
  FilePanel.redraw = function(self, ...)
    redraw(self, ...)
    M.decorate(self)
  end
  vim.api.nvim_create_user_command('PrReview', function(opts)
    M.open(opts.args)
  end, { nargs = '?', desc = 'Checkout PR [number] and open diffview against its base' })
end

return M
```

- [ ] **Step 2: Replace the plugin spec**

```lua
-- lua/plugins/diffview.lua
-- Side-by-side PR review. `:PrReview 464` → <Tab>/<S-Tab> files, ]c/[c hunks, `-` toggles GitHub "viewed". Logic lives in lua/pr_review.lua.
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
      keymaps = {
        file_panel = {
          {
            'n',
            '-',
            function()
              require('pr_review').toggle_viewed()
            end,
            { desc = 'Toggle viewed on GitHub' },
          },
        },
      },
      hooks = {
        view_closed = function()
          require('pr_review').reset()
        end,
      },
    },
    config = function(_, opts)
      require('diffview').setup(opts)
      require('pr_review').setup()
    end,
  },
}
```

- [ ] **Step 3: Format + headless load**

Run:
```bash
/tmp/claude-1000/-home-fuad--config-nvim/e156e800-466b-4722-8990-a1ae25717d75/scratchpad/stylua --check . || /tmp/claude-1000/-home-fuad--config-nvim/e156e800-466b-4722-8990-a1ae25717d75/scratchpad/stylua .
nvim --headless -c 'lua require("diffview"); print(vim.fn.exists(":PrReview"), type(require("pr_review").toggle_viewed))' +qa 2>&1 | tail -2
```
Expected: stylua clean; prints `2 function`.

- [ ] **Step 4: Live test on PR 464**

Run headless against `~/projects/morphic` (branch `stack/1-detection` is PR 464):
```bash
cd ~/projects/morphic && nvim --headless -c 'PrReview' -c 'lua vim.defer_fn(function()
  local p = require("diffview.lib").get_current_view().panel
  local marks = vim.api.nvim_buf_get_extmarks(p.bufid, vim.api.nvim_create_namespace("pr_review"), 0, -1, { details = true })
  print("extmarks:", #marks)
  for _, m in ipairs(marks) do if m[4].virt_text_pos == "eol" then print(m[4].virt_text[1][1]) end end
  vim.cmd("qa!")
end, 4000)' 2>&1 | tail -3
```
Expected: `extmarks: ≥1` and a counter line like ` ✓ 0/159`. Then toggle one file via the API to confirm the mutation path (and revert):
```bash
cd ~/projects/morphic && nvim --headless -c 'PrReview' -c 'lua vim.defer_fn(function()
  local p = require("diffview.lib").get_current_view().panel
  local pr = require("pr_review")
  p.components.comp:deep_some(function(c) if c.name == "file" then vim.api.nvim_win_set_cursor(p.winid, { c.lstart + 1, 0 }); return true end return false end)
  local path = p:get_item_at_cursor().path
  pr.toggle_viewed()
  vim.defer_fn(function()
    local out = vim.system({ "gh", "api", "graphql", "-f", "query=query($id:ID!){node(id:$id){... on PullRequest{files(first:1){nodes{path viewerViewedState}}}}}", "-F", "id=" .. vim.system({ "gh", "pr", "view", "--json", "id", "-q", ".id" }, { text = true }):wait().stdout:gsub("%s","") }, { text = true }):wait().stdout
    print(path, out)
    vim.api.nvim_win_set_cursor(p.winid, { 1, 0 }); p.components.comp:deep_some(function(c) if c.name == "file" then vim.api.nvim_win_set_cursor(p.winid, { c.lstart + 1, 0 }); return true end return false end)
    pr.toggle_viewed()
    vim.defer_fn(function() vim.cmd("qa!") end, 3000)
  end, 3000)
end, 4000)' 2>&1 | tail -3
```
Expected: the printed JSON shows the first file with `"viewerViewedState":"VIEWED"`; the second toggle reverts it (confirm afterwards with the same `gh api graphql` query showing `UNVIEWED`).

- [ ] **Step 5: Commit**

```bash
git add lua/pr_review.lua lua/plugins/diffview.lua
git commit -m "feat: sync diffview file panel with GitHub PR viewed state"
```

### Task 2: Docs

**Files:**
- Modify: `lua/plugins/CLAUDE.md` (`## diffview.lua` section)
- Modify: `CLAUDE.md` (root, "Shared Utilities")

- [ ] **Step 1: Update `lua/plugins/CLAUDE.md`**

Replace the `## diffview.lua` section with:

```markdown
## diffview.lua

PR / branch review via `sindrets/diffview.nvim`. Lazy-loaded on its commands. All logic lives in `lua/pr_review.lua`; the spec only wires keymaps, the `-` file-panel override, and the `view_closed` hook.

`:PrReview [number]` — with a number, runs `gh pr checkout <number>` first (aborts with a notification on failure). Then `gh pr view --json id,baseRefName` gives the PR node id and base (falls back to `origin/master` with no PR), fetches the base, runs `:DiffviewOpen origin/<base>...HEAD`, and asynchronously loads GitHub's per-file `viewerViewedState` via `gh api graphql`.

| Key | Action |
|-----|--------|
| `<leader>gv` | `:PrReview` — diffview of current branch vs its PR base |
| `<leader>gV` | `:DiffviewClose` |
| `-` (file panel) | Toggle the file's **Viewed** state on GitHub (`markFileAsViewed` / `unmarkFileAsViewed`), optimistic with revert on error, then moves to the next entry |

Viewed files show `✓` in place of the status letter and are dimmed; the "Changes" title gets a `✓ n/total` counter. Decorations are extmarks painted by a wrapper around `FilePanel:redraw`. On a non-PR branch `-` just notifies.

Inside diffview (stock bindings): `<Tab>`/`<S-Tab>` next/prev file · `]c`/`[c` hunks · `g?` help. The right-hand side is a real buffer, so LSP (`gd`, hover) works while reading.
```

- [ ] **Step 2: Update root `CLAUDE.md` Shared Utilities**

Append after the `lua/utils.lua` paragraph:

```markdown
`lua/pr_review.lua` — PR review on top of diffview: `:PrReview` open flow and GitHub-synced "viewed" marks (see `lua/plugins/CLAUDE.md` → diffview.lua).
```

- [ ] **Step 3: Commit**

```bash
git add lua/plugins/CLAUDE.md CLAUDE.md
git commit -m "docs: document GitHub-synced viewed state in diffview"
```

# Directory Viewed Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `-` on a directory row in the diffview file panel marks/unmarks every file under it on GitHub in one request.

**Architecture:** Refactor `toggle_viewed` in `lua/pr_review.lua` into `collect(panel, item) → paths[]` + `set_viewed(panel, paths, viewed)`; the latter builds one aliased GraphQL mutation.

**Tech Stack:** as in `2026-09-13-pr-viewed-state.md`.

## Global Constraints

- stylua clean (`stylua --check .`); spec addendum in `2026-09-13-pr-viewed-state-design.md`.
- `DirData.path` is the full relative directory path (verified live).

---

### Task 1: directory toggle

**Files:** Modify `lua/pr_review.lua` (`M.toggle_viewed`), `lua/plugins/CLAUDE.md`.

- [ ] **Step 1:** Replace `M.toggle_viewed` with:

```lua
-- Paths of every file entry in the panel under `dir` (prefix match on the directory path).
local function files_under(panel, dir)
  local prefix, paths = dir.path .. '/', {}
  panel.components.comp:deep_some(function(comp)
    if comp.name == 'file' and vim.startswith(comp.context.path, prefix) then
      table.insert(paths, comp.context.path)
    end
    return false
  end)
  return paths
end

-- Flip `paths` to `viewed` on GitHub in one aliased mutation; optimistic, reverted on failure.
local function set_viewed(panel, paths, viewed)
  local pr_id = state.pr_id
  for _, p in ipairs(paths) do
    state.viewed[p] = viewed or nil
  end
  panel:redraw()
  local mutation = viewed and 'markFileAsViewed' or 'unmarkFileAsViewed'
  local fields = {}
  for i, p in ipairs(paths) do
    fields[i] = ('f%d: %s(input:{pullRequestId:$id,path:%s}){ clientMutationId }'):format(i, mutation, vim.json.encode(p))
  end
  local query = 'mutation($id:ID!){ ' .. table.concat(fields, ' ') .. ' }'
  graphql(query, { id = pr_id }, function(data, err)
    if state.pr_id ~= pr_id then
      return
    end
    if not data or data.errors then
      for _, p in ipairs(paths) do
        state.viewed[p] = (not viewed) or nil
      end
      redraw_panel()
      vim.notify('pr_review: ' .. mutation .. ' failed\n' .. (err ~= '' and err or vim.inspect(data and data.errors)), vim.log.levels.ERROR)
    end
  end)
end

-- `-` in the file panel. File: flip it and advance. Directory: mark all files under it, or unmark all if every one is viewed.
function M.toggle_viewed()
  local panel = current_panel()
  local item = panel and panel:get_item_at_cursor()
  if not item then
    return
  end
  if not state.pr_id then
    vim.notify('pr_review: not on a PR branch', vim.log.levels.INFO)
    return
  end
  if item.basename then
    set_viewed(panel, { item.path }, not state.viewed[item.path])
    require('diffview.actions').next_entry()
    return
  end
  local paths = files_under(panel, item)
  local all_viewed = #paths > 0
  for _, p in ipairs(paths) do
    all_viewed = all_viewed and state.viewed[p] ~= nil
  end
  if #paths > 0 then
    set_viewed(panel, paths, not all_viewed)
  end
end
```

- [ ] **Step 2:** `stylua --check .`; headless load prints `function`.
- [ ] **Step 3:** Live test in `~/projects/dexpace/morphic` (PR 464): put cursor on the `diag` directory row (2 files), call `toggle_viewed()`, confirm both files `VIEWED` via `gh api graphql`, call again, confirm `UNVIEWED`. Single-file toggle still works.
- [ ] **Step 4:** Docs: in `lua/plugins/CLAUDE.md` diffview section, change the `-` row to cover directories.
- [ ] **Step 5:** Commit `feat: toggle GitHub viewed state for whole directories`.

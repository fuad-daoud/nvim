# GitHub-synced "viewed" marks in diffview

## Goal

While reviewing a PR with `:PrReview`, mark files as viewed from the diffview
file panel, using the same state as GitHub's "Viewed" checkbox so ticks made in
Neovim show on github.com and vice-versa. Builds on
`2026-09-13-pr-review-diffview-design.md`.

## Components

### `lua/pr_review.lua` (new module)

Owns all PR logic; `lua/plugins/diffview.lua` becomes a thin spec that requires
it. Follows the `lua/utils.lua` precedent for shared modules.

State (module-local, one PR at a time):

```lua
local state = { pr_id = nil, viewed = {} }  -- viewed: { [path] = true }
```

Functions:

- `M.open(number?)` — replaces the previous `pr_review`:
  1. If `number` given: `gh pr checkout <number>`; on failure notify + return.
  2. `gh pr view --json id,baseRefName` (one call). On success set
     `state.pr_id`, base = `origin/<baseRefName>`; on failure `state.pr_id = nil`,
     base = `origin/master`.
  3. `git fetch origin <base>` (result ignored).
  4. `:DiffviewOpen <base>...HEAD`.
  5. If `state.pr_id`: `M.load_viewed()`.

- `M.load_viewed()` — async, paginated GraphQL via `vim.system` with callback:
  ```graphql
  query($id:ID!,$after:String){ node(id:$id){ ... on PullRequest {
    files(first:100, after:$after){ pageInfo{hasNextPage endCursor}
      nodes{ path viewerViewedState } } } } }
  ```
  Fills `state.viewed[path] = true` for nodes with `viewerViewedState == "VIEWED"`
  (`DISMISSED` — GitHub's "changed since you viewed it" — counts as unviewed).
  Follows `endCursor` until `hasNextPage` is false, then redraws the panel
  (`vim.schedule`). Errors → `vim.notify` warn, panel stays undecorated.

- `M.toggle_viewed()` — bound to `-` in the file panel:
  1. `panel = require('diffview.lib').get_current_view().panel`;
     `item = panel:get_item_at_cursor()`. If `item` is nil or has no `basename`
     (a directory) → return.
  2. If `state.pr_id == nil` → notify "Not on a PR branch" (info) and return.
  3. Optimistic flip: `state.viewed[path] = not state.viewed[path]`,
     `panel:redraw()`, move cursor to the next entry (`panel:highlight_next_file()`
     is not public; use `actions.next_entry()`), then run the mutation:
     `markFileAsViewed` / `unmarkFileAsViewed` with
     `input:{pullRequestId:$id, path:$path}`. On non-zero exit revert the flip,
     redraw, notify error with stderr.

- `M.decorate(panel)` — called after every panel redraw (see hook below):
  clears namespace `pr_review`, then walks
  `panel.components.comp:deep_some(...)`; for each comp with `name == "file"`
  and `state.viewed[comp.context.path]`:
  - extmark at `(comp.lstart, 0)`: `virt_text = {{ "✓", "DiffviewFilePanelInsertions" }}`,
    `virt_text_pos = "overlay"` (replaces the status letter, keeps alignment)
  - extmark `(comp.lstart, 0)`–end of line: `hl_group = "Comment"`,
    `priority = 200` (dims the row).
  Then on the `working.title` line (`panel.components.working.title.comp.lstart`)
  an eol virt text: `" ✓ <n>/<total>"` where `n` = count of viewed file comps
  and `total` = count of file comps, highlight `DiffviewFilePanelCounter`.
  When `state.pr_id == nil` the function does nothing.

- `M.setup()` — called once from the plugin `config`:
  - wraps `require('diffview.scene.views.diff.file_panel').FilePanel.redraw`:
    call original, then `M.decorate(self)`.
  - creates `:PrReview` user command.

### `lua/plugins/diffview.lua`

- `opts.keymaps.file_panel = { { 'n', '-', function() require('pr_review').toggle_viewed() end, { desc = 'Toggle viewed on GitHub' } } }`
  (overrides the default stage toggle, which is inert in a commit-range diff).
- `opts.hooks.view_closed` → `require('pr_review').reset()` clears `state`.
- `config` → `require('diffview').setup(opts)`, then `require('pr_review').setup()`.
- Keymaps `<leader>gv` / `<leader>gV` unchanged.

### Docs

Update the `## diffview.lua` section of `lua/plugins/CLAUDE.md`: `-` toggles
GitHub viewed state, `✓` + dimmed = viewed, header counter, `pr_review.lua`
mention. Update root `CLAUDE.md` "Shared Utilities" to list `lua/pr_review.lua`.

## Error handling

- `gh` not authed / API error on load → warn notification, no decorations.
- Mutation failure → revert optimistic flip, error notification.
- `-` on a non-PR branch → info notification, nothing else.
- `-` on a directory row → no-op.

## Testing

- Headless: `require('pr_review')` loads; `:PrReview` exists.
- Manual on PR 464 in `~/projects/morphic`: open, verify already-viewed files
  from the web show `✓`; press `-` on a file, verify `✓` appears and
  `gh api graphql` (or the web UI) reports `VIEWED`; press `-` again, verify it
  reverts. Toggle on a directory row does nothing. `<leader>gv` on a non-PR
  branch: no counter, `-` notifies.
- `stylua --check .` passes.

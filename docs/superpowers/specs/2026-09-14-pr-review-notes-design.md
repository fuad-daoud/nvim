# PR review notes & submission

## Goal

Leave a full GitHub review from the diffview PR view: attach draft notes to
lines/files, write a summary, submit as Comment / Approve / Request changes in
one call, and see existing review threads rendered inline. Draft-until-submit:
nothing hits GitHub until `:PrReviewSubmit`.

Builds on `pr_review.lua` (diffview open flow, `gh` helper) and reuses its
side-detection approach (`pr_companion.lua`'s `snippet`).

## Key facts (verified)

- diffview shows **real file buffers**: right pane line N == head file line N
  (`side: RIGHT`), left pane line N == base file line N (`side: LEFT`). No
  diff-hunk position mapping needed.
- One `POST /repos/{o}/{r}/pulls/{n}/reviews` with `{event, body, comments:[]}`
  creates a whole review; `comments[]` entries are `{path, line, side,
  start_line?, start_side?, body}`. `event` = `APPROVE` | `REQUEST_CHANGES` |
  `COMMENT`.
- Existing threads: GraphQL `repository.pullRequest.reviewThreads` → nodes with
  `path, line, startLine, diffSide, isResolved, isOutdated,
  comments.nodes[].{author.login, body}`.
- GitHub rejects comments on lines outside the diff; the API error names the
  file/line.

## Components

### `lua/pr_review_notes.lua` (new)

State: `current` (from `pr_review`: `{ url, number, base, root, owner, repo }`),
`review = { verdict = 'COMMENT', summary = '', notes = {} }`, `threads = {}`
(fetched). Persisted to `stdpath('data')/pr_review/<key>.review.json` (key =
same slug pr_companion uses). Loaded on `M.attach(pr)`.

- `M.attach(pr)` — called by `pr_review.open()` after `DiffviewOpen` when a PR
  is detected (alongside `pr_companion.offer`). Sets `current`, loads any saved
  pending review, fetches threads (`M.load_threads()`), installs the render
  autocmd, decorates open diff buffers.
- `note_loc()` — from the current buffer + cursor (or visual range): parse
  `diffview://…/.git/<rev>/<path>`; `side` = RIGHT if `rev` prefixes `HEAD` else
  LEFT; `line` = cursor row, `start_line` = range start (nil if single line).
  Returns nil (with a notify) for non-diff buffers.
- `M.add_note()` — `note_loc()`, then a floating markdown input (`:w` to save,
  `q` to cancel). If a pending note already covers that exact `path/side/line`,
  prefill it (edit). Append/replace in `review.notes`, persist, redraw.
- `M.delete_note()` — remove the pending note whose `path/side` matches the
  buffer and whose `line`/range contains the cursor; persist, redraw.
- `M.load_threads()` — GraphQL query above (paginated, 100/page); store by
  `{path, diffSide}`; redraw. Read-only.
- `M.decorate(buf)` — for the diff buffer's `path`+side: clear namespace, then
  for each pending note render a `▍` sign (`extmark sign_text`) on its line and
  the body as dimmed virt_lines below, prefixed `✎ (you, draft)`; for each
  existing thread on that side render `💬 <author>` + body virt_lines
  (greyed + `(resolved)`/`(outdated)` as applicable). Nothing when no PR.
- Render trigger: autocmd on the diffview diff buffers. Diffview reuses buffers;
  hook `BufWinEnter`/`BufReadPost` filtered to `diffview://` names, plus an
  explicit redraw of all diff windows after add/delete/submit.
- `M.submit()` — if `#notes == 0 and summary == ''` → notify and stop. Open a
  floating gitcommit buffer: line 1 reserved for verdict (set via `vim.ui.select`
  Comment/Approve/Request changes before the buffer opens; shown as a `#` header),
  rest is the summary. `:w` → build payload, `POST` via
  `gh api --method POST repos/<o>/<r>/pulls/<n>/reviews --input -` (JSON on
  stdin). On success: clear `review`, delete the file, `load_threads()`, notify.
  On failure: keep `review`, notify with the API error.
- `M.discard()` — clear `review` + file, redraw.
- `M.setup()` — register `:PrNote`, `:PrNoteDelete`, `:PrReviewSubmit`,
  `:PrReviewDiscard`.

### `pr_review.lua`

`M.open` already fetches `url,number,...`; extend the offer block to also call
`require('pr_review_notes').attach(pr)` (pr gains `owner`/`repo` — derive from
`url` or add to the `gh pr view --json`). No other change.

### `lua/plugins/diffview.lua`

- `cmd`: add `PrNote`, `PrNoteDelete`, `PrReviewSubmit`, `PrReviewDiscard`.
- `keys`: `<leader>gn` (n,x) → `:PrNote`; `<leader>gN` → `:PrNoteDelete`;
  `<leader>gs` → `:PrReviewSubmit`.
- `config`: `require('pr_review_notes').setup()`.

## Error handling

- Non-diff buffer for a note → notify, no-op.
- Submit with nothing → notify, no-op.
- API rejects a line / auth / not mergeable → notify with stderr, pending review
  kept intact.
- No PR (plain branch) → `attach` not called; commands notify "open a PR first".

## Testing

- Headless: module loads; commands exist; `note_loc()` returns correct
  side/line for both panes; review JSON round-trips.
- Live on a throwaway note against PR 463: add a pending note on a changed line
  (verify sign + virt_lines render), submit as COMMENT, confirm via
  `gh api .../reviews` that the review + comment exist, then (manually) that the
  thread now renders inline on reopen. Delete the test review from GitHub after.
- `stylua --check .`.

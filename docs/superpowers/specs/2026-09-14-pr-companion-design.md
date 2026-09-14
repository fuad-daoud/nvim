# PR review AI companion

## Goal

While reviewing a PR with `:PrReview`, ask a Claude Code session that already
knows the PR about selected lines, on the spot, without leaving Neovim. One
session per PR, persisted, reused for every question.

## Components

### `lua/pr_companion.lua` (new)

State: `sessions` table loaded from `stdpath('data')/pr_review/sessions.json`,
keyed by PR URL → `{ session_id?, declined? }`. `current` = `{ url, number,
title, base, root }` set by `M.offer(pr)`. `busy` flag per session.

- `M.offer(pr)` — called by `pr_review.open()` after `DiffviewOpen` with
  `pr = { url, number, title, body, baseRefName }` (from one `gh pr view --json`).
  Stores `current`. If the session has a `session_id` → open the pane (loads the
  persisted markdown). If `declined` → nothing. Else `vim.ui.select({'Yes','No'},
  { prompt = 'Bootstrap AI companion for PR #N?' })`; Yes → `M.bootstrap()`,
  No → save `declined = true`.
- `M.bootstrap()` — generate UUID (Lua `math.random`, v4 format). Run in
  `current.root`:
  `claude -p --session-id <uuid> --model opus --effort high --output-format json --allowedTools Read Grep Glob "Bash(git *)" "Bash(gh *)"`
  with the prompt on stdin (persona + PR title/number/base/url + body + "run
  `git diff origin/<base>...HEAD --stat`, read what you need, then summarize the
  PR in ≤15 lines and list what deserves careful review"). Notify start. On
  exit 0: parse JSON, save `session_id`, open pane, append `## Summary` + result,
  persist. On failure: notify error with stderr, nothing saved.
- `M.ask(opts)` — `opts.range` (from the user command / visual keymap) selects
  the snippet: buffer lines `line1..line2`; path = for `diffview://` buffers
  parse the path after the rev, side = "base <base>"; for real files
  `vim.fn.fnamemodify(name, ':.')` relative to root, side = "PR head".
  `vim.ui.input({ prompt = 'Ask companion: ' })`; empty → abort. Message:
  ```
  File: <path>  lines <a>–<b>  (<side>)
  ```<ft>
  <lines>
  ```
  Question: <q>
  ```
  (no snippet block when called without a range). Append to the pane:
  `### ❯ <q>`, the snippet fence (if any), `_thinking…_`. If `busy` → notify
  and return. Run `claude -p --resume <id> --model opus --effort high
  --output-format json --allowedTools …` with the message on stdin, cwd root.
  On result replace the `_thinking…_` line with the answer (+ blank line);
  persist. On failure replace it with `**error:** <stderr>`.
- Pane: `M.toggle()`. Scratch buffer named `pr-companion://<number>`,
  `buftype=nofile`, `bufhidden=hide`, `filetype=markdown`, `wrap`, opened with
  `botright vsplit` width 60; toggle closes the window if visible. Content is
  mirrored to `stdpath('data')/pr_review/<owner>_<repo>_<number>.md` after
  every append; opening the pane for a known session loads that file if the
  buffer is empty. Buffer-local `q` closes the pane; `<leader>ga` in the pane
  asks a follow-up.
- `M.chat()` — `require('toggleterm.terminal').Terminal:new({ cmd = 'claude --resume <id>', dir = root, direction = 'float' }):toggle()`.
- `M.reset()` — delete the session entry + markdown file; next `:PrReview`
  offers again.

### Commands / keymaps (in `lua/plugins/diffview.lua` spec + module `setup`)

- `:PrCompanion [toggle|bootstrap|chat|reset]` — no arg: bootstrap if no
  session, else toggle pane.
- `:PrAsk` (range allowed) — `M.ask`.
- `<leader>ga` visual → `:PrAsk` with range; normal → `:PrAsk` without.
- `<leader>gA` → toggle pane.

### `pr_review.lua` change

`M.open` fetches `id,baseRefName,number,title,body,url` in the existing
`gh pr view` call and, after `DiffviewOpen` (non-`--commits` path), calls
`require('pr_companion').offer(pr)`.

## Error handling

- `claude` not on PATH → bootstrap/ask notify "claude CLI not found".
- Non-zero exit → stderr in notification (bootstrap) or in the pane (ask).
- Ask with no session → notify "no companion session; run :PrCompanion".
- Concurrent asks → second one notifies "companion is busy".

## Testing

- Headless: module loads; commands exist; UUID matches v4 regex; sessions
  file round-trips.
- Live on PR 464: bootstrap (real `claude -p`), confirm `sessions.json` has the
  id and pane shows a summary; `:PrAsk` on a range in the right pane gets an
  answer; `claude --resume <id>` from the shell shows the same history.
- `stylua --check .`.

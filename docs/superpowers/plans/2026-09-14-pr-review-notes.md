# PR Review Notes & Submission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Leave a full GitHub review from the diffview PR view — draft line/file notes, a summary, and a verdict submitted in one API call, plus existing threads rendered inline.

**Architecture:** New `lua/pr_review_notes.lua` holds an in-memory pending review (persisted to JSON), derives comment locations from diffview's real file buffers (buffer line == file line), renders pending notes and fetched threads as extmarks, and submits via `gh api ... /reviews`. `pr_review.lua` calls `attach(pr)` alongside the companion; the diffview spec adds commands/keymaps.

**Tech Stack:** Neovim 0.12 (`vim.system`, extmarks/virt_lines, `vim.ui.input/select`), `gh api` + `gh api graphql`, diffview.nvim.

**Spec:** `docs/superpowers/specs/2026-09-14-pr-review-notes-design.md`

## Global Constraints

- stylua clean (`stylua --check .`) before every commit.
- Read-only where it belongs: threads are fetched and rendered, never edited/resolved in v1.
- Verified facts: diffview buffer name is `diffview://<…>/.git/<rev>/<path>`; right pane `rev` prefixes `HEAD` (`side RIGHT`, head file line), left pane is base (`side LEFT`). Review API: `POST repos/{o}/{r}/pulls/{n}/reviews` with `{event: APPROVE|REQUEST_CHANGES|COMMENT, body, comments:[{path, line, side, start_line?, start_side?, body}]}`. Threads: GraphQL `repository.pullRequest.reviewThreads.nodes[].{path, line, startLine, diffSide, isResolved, isOutdated, comments.nodes[].{author.login, body}}`.
- Data dir + key slug match `pr_companion.lua`: `stdpath('data')/pr_review/`, key = `url:gsub('^https?://github.com/',''):gsub('/pull/','_'):gsub('/','_')`.

---

### Task 1: Pure logic — location, payload, persistence

**Files:**
- Create: `lua/pr_review_notes.lua`
- Test: `lua/pr_review_notes_spec.lua` (throwaway, deleted at end of task)

**Interfaces:**
- Produces: local `parse_diff_name(name, head) -> path|nil, side|nil`; local `build_payload(review) -> {event, body, comments}`; module state `review = { verdict='COMMENT', summary='', notes={} }`; `M.key(url)`, `M.data_dir`.

- [ ] **Step 1: Write failing tests** (busted-style via `nvim -l`)

```lua
-- lua/pr_review_notes_spec.lua
local N = dofile('lua/pr_review_notes.lua')
local ok = true
local function eq(a, b, msg)
  if vim.inspect(a) ~= vim.inspect(b) then
    ok = false
    print('FAIL ' .. msg .. ': ' .. vim.inspect(a) .. ' ~= ' .. vim.inspect(b))
  end
end

local head = 'aaaaaaaaaaaa1111'
-- right pane => head file, side RIGHT
eq({ N._parse_diff_name('diffview:///repo/.git/' .. head .. '/pkg/foo.go', head) }, { 'pkg/foo.go', 'RIGHT' }, 'right side')
-- left pane => some other rev => base, side LEFT
eq({ N._parse_diff_name('diffview:///repo/.git/bbbbbbbb2222/pkg/foo.go', head) }, { 'pkg/foo.go', 'LEFT' }, 'left side')
-- non-diff buffer
eq({ N._parse_diff_name('/home/x/pkg/foo.go', head) }, {}, 'non-diff nil')

-- payload: single + multiline notes
N._state().review = {
  verdict = 'REQUEST_CHANGES',
  summary = 'needs work',
  notes = {
    { path = 'a.go', side = 'RIGHT', line = 10, body = 'x' },
    { path = 'b.go', side = 'RIGHT', line = 20, start_line = 18, body = 'y' },
  },
}
eq(N._build_payload(), {
  event = 'REQUEST_CHANGES',
  body = 'needs work',
  comments = {
    { path = 'a.go', side = 'RIGHT', line = 10, body = 'x' },
    { path = 'b.go', side = 'RIGHT', line = 20, start_line = 18, start_side = 'RIGHT', body = 'y' },
  },
}, 'payload')

-- key slug
eq(N.key('https://github.com/o/r/pull/7'), 'o_r_7', 'key slug')

print(ok and 'ALL PASS' or 'FAILED')
os.exit(ok and 0 or 1)
```

- [ ] **Step 2: Run — verify it fails**

Run: `cd /home/fuad/.config/nvim && nvim -l lua/pr_review_notes_spec.lua`
Expected: error (module/functions missing).

- [ ] **Step 3: Implement the pure core**

```lua
-- lua/pr_review_notes.lua
-- Leave a GitHub review from the diffview PR view: draft notes on lines, a summary, and a verdict in one API call.
local M = {}

M.data_dir = vim.fs.joinpath(vim.fn.stdpath 'data', 'pr_review')

local current -- { url, number, base, root, owner, repo }
local review = { verdict = 'COMMENT', summary = '', notes = {} }
local threads = {} -- { ['path\tSIDE'] = { {line, startLine, isResolved, isOutdated, comments={{login,body}}} } }

function M.key(url)
  return (url:gsub('^https?://github.com/', ''):gsub('/pull/', '_'):gsub('/', '_'))
end

-- Test hooks (underscore-prefixed): expose internals without a require dance.
function M._state()
  return { current = current, review = review, threads = threads }
end

-- diffview buffer name -> (path, side). RIGHT when the rev prefixes HEAD, else LEFT. nil for non-diff buffers.
function M._parse_diff_name(name, head)
  local rev, path = name:match '^diffview://.-/%.git/([^/]+)/(.*)$'
  if not rev then
    return nil
  end
  return path, (head and vim.startswith(head, rev)) and 'RIGHT' or 'LEFT'
end
M._parse_diff_name = M._parse_diff_name -- keep name stable

-- Build the /reviews payload from the pending review.
function M._build_payload()
  local comments = {}
  for _, n in ipairs(review.notes) do
    local c = { path = n.path, side = n.side, line = n.line, body = n.body }
    if n.start_line then
      c.start_line = n.start_line
      c.start_side = n.side
    end
    table.insert(comments, c)
  end
  return { event = review.verdict, body = review.summary, comments = comments }
end

return M
```

Note: `M._parse_diff_name = M._parse_diff_name` line is redundant — delete it; the function is defined once.

- [ ] **Step 4: Run — verify pass**

Run: `cd /home/fuad/.config/nvim && nvim -l lua/pr_review_notes_spec.lua`
Expected: `ALL PASS`, exit 0.

- [ ] **Step 5: Format + delete the throwaway spec, commit**

```bash
cd /home/fuad/.config/nvim
rm lua/pr_review_notes_spec.lua
stylua --check . || stylua .
git add lua/pr_review_notes.lua
git commit -m "feat: pr_review_notes core — diff-name parsing and review payload"
```

---

### Task 2: State, persistence, notes, rendering, threads

**Files:**
- Modify: `lua/pr_review_notes.lua`

**Interfaces:**
- Consumes: `current`, `review`, `threads`, `M._parse_diff_name`, `M.key`, `M.data_dir` from Task 1.
- Produces: `M.attach(pr)`, `M.add_note()`, `M.delete_note()`, `M.load_threads()`, `M.decorate(buf)`, `M.discard()`; local `persist()`, `note_loc()`, `redraw_all()`, `review_file()`.

- [ ] **Step 1: Add persistence + gh/graphql helpers + thread loader**

```lua
local ns = vim.api.nvim_create_namespace 'pr_review_notes'

local function review_file()
  return vim.fs.joinpath(M.data_dir, M.key(current.url) .. '.review.json')
end

local function persist()
  vim.fn.mkdir(M.data_dir, 'p')
  local f = assert(io.open(review_file(), 'w'))
  f:write(vim.json.encode(review))
  f:close()
end

local function head_rev()
  return vim.trim(vim.system({ 'git', 'rev-parse', 'HEAD' }, { text = true, cwd = current.root }):wait().stdout or '')
end

local function gh_json(args, cb)
  vim.system(vim.list_extend({ 'gh' }, args), { text = true, cwd = current.root }, function(res)
    vim.schedule(function()
      cb(res.code == 0 and vim.json.decode(res.stdout) or nil, (res.stderr or ''):gsub('%s+$', ''))
    end)
  end)
end

local THREADS_QUERY = [[
query($o:String!,$r:String!,$n:Int!,$after:String){ repository(owner:$o,name:$r){ pullRequest(number:$n){
  reviewThreads(first:100, after:$after){ pageInfo{hasNextPage endCursor}
    nodes{ path line startLine diffSide isResolved isOutdated comments(first:20){ nodes{ author{login} body } } } } } } }]]

function M.load_threads()
  local c = current
  local acc = {}
  local function page(after)
    local args = { 'api', 'graphql', '-f', 'query=' .. THREADS_QUERY, '-F', 'o=' .. c.owner, '-F', 'r=' .. c.repo, '-F', 'n=' .. c.number }
    if after then
      vim.list_extend(args, { '-F', 'after=' .. after })
    end
    gh_json(args, function(data)
      if current ~= c then
        return
      end
      local rt = data and data.data and data.data.repository and data.data.repository.pullRequest and data.data.repository.pullRequest.reviewThreads
      if not rt then
        return
      end
      for _, t in ipairs(rt.nodes) do
        local key = t.path .. '\t' .. t.diffSide
        acc[key] = acc[key] or {}
        table.insert(acc[key], t)
      end
      if rt.pageInfo.hasNextPage then
        page(rt.pageInfo.endCursor)
      else
        threads = acc
        M.redraw_all()
      end
    end)
  end
  page(nil)
end
```

- [ ] **Step 2: note location + add/delete**

```lua
-- Location from the current diff buffer + cursor/visual range. Returns {path, side, line, start_line?} or nil.
local function note_loc()
  local buf = vim.api.nvim_get_current_buf()
  local path, side = M._parse_diff_name(vim.api.nvim_buf_get_name(buf), head_rev())
  if not path then
    vim.notify('pr_review_notes: not in a diff buffer', vim.log.levels.INFO)
    return
  end
  local mode = vim.fn.mode()
  local a, b
  if mode:match '[vV]' then
    a, b = vim.fn.line 'v', vim.fn.line '.'
    if a > b then
      a, b = b, a
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  else
    a = vim.api.nvim_win_get_cursor(0)[1]
    b = a
  end
  local loc = { path = path, side = side, line = b }
  if b > a then
    loc.start_line = a
  end
  return loc
end

local function find_note(path, side, line)
  for i, n in ipairs(review.notes) do
    if n.path == path and n.side == side and (n.line == line or (n.start_line and line >= n.start_line and line <= n.line)) then
      return i
    end
  end
end

function M.add_note()
  if not current then
    return vim.notify('pr_review_notes: open a PR with :PrReview first', vim.log.levels.INFO)
  end
  local loc = note_loc()
  if not loc then
    return
  end
  local existing = find_note(loc.path, loc.side, loc.line)
  vim.ui.input({ prompt = 'Note: ', default = existing and review.notes[existing].body or '' }, function(body)
    if not body or body:match '^%s*$' then
      return
    end
    loc.body = body
    if existing then
      review.notes[existing] = loc
    else
      table.insert(review.notes, loc)
    end
    persist()
    M.redraw_all()
  end)
end

function M.delete_note()
  if not current then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local path, side = M._parse_diff_name(vim.api.nvim_buf_get_name(buf), head_rev())
  if not path then
    return
  end
  local i = find_note(path, side, vim.api.nvim_win_get_cursor(0)[1])
  if not i then
    return vim.notify('pr_review_notes: no note here', vim.log.levels.INFO)
  end
  table.remove(review.notes, i)
  persist()
  M.redraw_all()
end
```

- [ ] **Step 3: rendering**

```lua
-- Dimmed virtual lines below `row` (0-based) with a prefix; each source line wraps into its own virt_line.
local function virt_below(buf, row, prefix, body, hl)
  local lines = { { { prefix, hl } } }
  for _, l in ipairs(vim.split(body, '\n')) do
    table.insert(lines, { { '  ' .. l, hl } })
  end
  vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { virt_lines = lines })
end

function M.decorate(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not current then
    return
  end
  local path, side = M._parse_diff_name(vim.api.nvim_buf_get_name(buf), head_rev())
  if not path then
    return
  end
  local last = vim.api.nvim_buf_line_count(buf)
  for _, n in ipairs(review.notes) do
    if n.path == path and n.side == side and n.line <= last then
      local row = n.line - 1
      vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { sign_text = '▍', sign_hl_group = 'DiffviewFilePanelInsertions' })
      virt_below(buf, row, '✎ (you, draft)', n.body, 'Comment')
    end
  end
  for _, t in ipairs(threads[path .. '\t' .. side] or {}) do
    if t.line and t.line <= last then
      local hl = t.isResolved and 'NonText' or 'Comment'
      for _, cm in ipairs(t.comments.nodes) do
        local tag = '💬 ' .. (cm.author and cm.author.login or '?') .. (t.isResolved and ' (resolved)' or '') .. (t.isOutdated and ' (outdated)' or '')
        virt_below(buf, t.line - 1, tag, cm.body, hl)
      end
    end
  end
end

function M.redraw_all()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_get_name(b):find('^diffview://') and vim.api.nvim_buf_get_name(b):find('%.git/') then
      M.decorate(b)
    end
  end
end
```

- [ ] **Step 4: attach + discard + render autocmd**

```lua
function M.discard()
  review = { verdict = 'COMMENT', summary = '', notes = {} }
  os.remove(review_file())
  M.redraw_all()
end

-- pr = { url, number, baseRefName, title, body } from pr_review; owner/repo parsed from the url.
function M.attach(pr)
  local owner, repo = pr.url:match 'github.com/([^/]+)/([^/]+)/pull/'
  local root = vim.trim(vim.system({ 'git', 'rev-parse', '--show-toplevel' }, { text = true }):wait().stdout or '')
  current = { url = pr.url, number = pr.number, base = pr.baseRefName, root = root ~= '' and root or vim.fn.getcwd(), owner = owner, repo = repo }
  review = { verdict = 'COMMENT', summary = '', notes = {} }
  local f = io.open(review_file())
  if f then
    local ok, saved = pcall(vim.json.decode, f:read '*a')
    f:close()
    if ok and type(saved) == 'table' and saved.notes then
      review = saved
    end
  end
  M.load_threads()
  M.redraw_all()
end
```

- [ ] **Step 5: Live-check rendering (no submit)**

Run in `~/projects/dexpace/morphic` (headless):
```bash
cd ~/projects/dexpace/morphic && nvim --headless -c 'PrReview' -c 'lua vim.defer_fn(function()
  local N = require("pr_review_notes")
  N.attach({ url = "https://github.com/dexpace/morphic/pull/463", number = 463, baseRefName = "main" })
  -- add a pending note on the head pane of the first changed file
  local head = vim.trim(vim.system({"git","rev-parse","HEAD"},{text=true}):wait().stdout)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
    local rev = name:match("/%.git/([^/]+)/")
    if rev and vim.startswith(head, rev) then vim.api.nvim_set_current_win(w) break end
  end
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  vim.ui.input = function(o, cb) cb("test draft note") end
  N.add_note()
  vim.defer_fn(function()
    local buf = vim.api.nvim_get_current_buf()
    local marks = vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("pr_review_notes"), 0, -1, { details = true })
    io.stdout:write("\nextmarks=" .. #marks .. "\n")
    for _, m in ipairs(marks) do io.stdout:write("  row=" .. m[2] .. " sign=" .. tostring(m[4].sign_text) .. " virt=" .. tostring(m[4].virt_lines and #m[4].virt_lines) .. "\n") end
    io.stdout:write("notes persisted: " .. tostring(io.open(vim.fn.stdpath("data").."/pr_review/dexpace_morphic_463.review.json") ~= nil) .. "\n")
    vim.cmd("qa!")
  end, 800)
end, 5000)' 2>&1 | grep -v "deprecated\|image.nvim"
rm -f ~/.local/share/nvim/pr_review/dexpace_morphic_463.review.json
```
Expected: `extmarks>=1` with a sign row and a virt_lines row; persisted = true. (Existing threads count is 0 on #463 — fine.)

- [ ] **Step 6: Format + commit**

```bash
cd /home/fuad/.config/nvim
stylua --check . || stylua .
git add lua/pr_review_notes.lua
git commit -m "feat: pr_review_notes — draft notes, inline rendering, thread fetch"
```

---

### Task 3: Submit, wiring, docs

**Files:**
- Modify: `lua/pr_review_notes.lua`, `lua/pr_review.lua`, `lua/plugins/diffview.lua`, `lua/plugins/CLAUDE.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: `M._build_payload`, `review`, `current`, `M.load_threads`, `M.discard`, `M.redraw_all`.
- Produces: `M.submit()`, `M.setup()`; `:PrNote`, `:PrNoteDelete`, `:PrReviewSubmit`, `:PrReviewDiscard`.

- [ ] **Step 1: submit + setup**

```lua
local function post_review()
  local payload = M._build_payload()
  local c = current
  vim.notify(('pr_review_notes: submitting %s (%d comments)…'):format(payload.event, #payload.comments), vim.log.levels.INFO)
  vim.system(
    { 'gh', 'api', '--method', 'POST', ('repos/%s/%s/pulls/%d/reviews'):format(c.owner, c.repo, c.number), '--input', '-' },
    { text = true, cwd = c.root, stdin = vim.json.encode(payload) },
    function(res)
      vim.schedule(function()
        if res.code ~= 0 then
          return vim.notify('pr_review_notes: submit failed\n' .. ((res.stderr ~= '' and res.stderr) or res.stdout), vim.log.levels.ERROR)
        end
        vim.notify(('pr_review_notes: review submitted (%s)'):format(payload.event), vim.log.levels.INFO)
        M.discard()
        M.load_threads()
      end)
    end
  )
end

function M.submit()
  if not current then
    return vim.notify('pr_review_notes: open a PR with :PrReview first', vim.log.levels.INFO)
  end
  if #review.notes == 0 and review.summary == '' then
    return vim.notify('pr_review_notes: no notes and no summary', vim.log.levels.INFO)
  end
  vim.ui.select({ 'Comment', 'Approve', 'Request changes' }, { prompt = ('Submit review on PR #%d (%d notes)'):format(current.number, #review.notes) }, function(choice)
    if not choice then
      return
    end
    review.verdict = ({ Comment = 'COMMENT', Approve = 'APPROVE', ['Request changes'] = 'REQUEST_CHANGES' })[choice]
    -- floating summary editor
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, 'pr-review-summary://' .. current.number)
    local lines = vim.split(review.summary, '\n')
    vim.list_extend(lines, {
      '',
      ('# %s review of PR #%d · %d line notes.'):format(review.verdict, current.number, #review.notes),
      '# Text above is the review summary. :w submits · q cancels.',
    })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].buftype = 'acwrite'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'gitcommit'
    local width, height = math.min(90, vim.o.columns - 4), math.min(#lines + 4, vim.o.lines - 4)
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = 'minimal',
      border = 'rounded',
      title = (' %s review #%d '):format(review.verdict, current.number),
    })
    vim.wo[win].wrap = true
    vim.keymap.set('n', 'q', function()
      vim.api.nvim_win_close(win, true)
    end, { buffer = buf })
    vim.api.nvim_create_autocmd('BufWriteCmd', {
      buffer = buf,
      callback = function()
        local body = vim.tbl_filter(function(l)
          return not l:match '^#'
        end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
        review.summary = vim.trim(table.concat(body, '\n'))
        if review.verdict ~= 'COMMENT' and #review.notes == 0 and review.summary == '' and review.verdict == 'REQUEST_CHANGES' then
          vim.bo[buf].modified = false
          return vim.notify('pr_review_notes: request-changes needs a summary or notes', vim.log.levels.ERROR)
        end
        vim.bo[buf].modified = false
        vim.api.nvim_win_close(win, true)
        post_review()
      end,
    })
  end)
end

function M.setup()
  vim.api.nvim_create_user_command('PrNote', M.add_note, { range = true, desc = 'Add/edit a review note on the current line/selection' })
  vim.api.nvim_create_user_command('PrNoteDelete', M.delete_note, { desc = 'Delete the review note under the cursor' })
  vim.api.nvim_create_user_command('PrReviewSubmit', M.submit, { desc = 'Submit the pending review (approve / request changes / comment)' })
  vim.api.nvim_create_user_command('PrReviewDiscard', M.discard, { desc = 'Discard the pending review notes' })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufReadPost' }, {
    pattern = 'diffview://*',
    callback = function(a)
      if vim.api.nvim_buf_get_name(a.buf):find '%.git/' then
        vim.schedule(function()
          M.decorate(a.buf)
        end)
      end
    end,
  })
end
```

Note: the `REQUEST_CHANGES` guard simplifies to: if verdict is REQUEST_CHANGES and both summary and notes are empty, refuse. Keep just that condition.

- [ ] **Step 2: wire pr_review.attach**

In `lua/pr_review.lua` `M.open`, in the `if pr then` block after `require('pr_companion').offer(pr)`:
```lua
    require('pr_review_notes').attach(pr)
```

- [ ] **Step 3: wire the spec**

In `lua/plugins/diffview.lua`:
- add to `cmd`: `'PrNote', 'PrNoteDelete', 'PrReviewSubmit', 'PrReviewDiscard'`
- add to `keys`:
```lua
      { '<leader>gn', ':PrNote<cr>', mode = { 'n', 'x' }, desc = '[G]it PR: add/edit [N]ote' },
      { '<leader>gN', '<cmd>PrNoteDelete<cr>', desc = '[G]it PR: delete [N]ote' },
      { '<leader>gs', '<cmd>PrReviewSubmit<cr>', desc = '[G]it PR: [S]ubmit review' },
```
- in `config`, after `require('pr_companion').setup()`: `require('pr_review_notes').setup()`

- [ ] **Step 4: Live test — submit a real COMMENT review on #463, then clean up**

```bash
cd ~/projects/dexpace/morphic && nvim --headless -c 'PrReview' -c 'lua vim.defer_fn(function()
  local N = require("pr_review_notes")
  N.attach({ url = "https://github.com/dexpace/morphic/pull/463", number = 463, baseRefName = "main" })
  local head = vim.trim(vim.system({"git","rev-parse","HEAD"},{text=true}):wait().stdout)
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local rev = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w)):match("/%.git/([^/]+)/")
    if rev and vim.startswith(head, rev) then vim.api.nvim_set_current_win(w) break end
  end
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  vim.ui.input = function(o, cb) cb("automated test note — please ignore") end
  N.add_note()
  vim.defer_fn(function()
    vim.ui.select = function(items, o, cb) cb("Comment") end
    N.submit()
    vim.defer_fn(function()
      -- write the summary buffer to trigger submit
      vim.api.nvim_buf_set_lines(0, 0, 0, false, { "automated test review — ignore" })
      vim.cmd("write")
      vim.defer_fn(function() vim.cmd("qa!") end, 4000)
    end, 500)
  end, 800)
end, 5000)' 2>&1 | grep -v "deprecated\|image.nvim"
# verify + delete the test review
id=$(gh api repos/dexpace/morphic/pulls/463/reviews -q '.[-1].id')
gh api repos/dexpace/morphic/pulls/463/reviews/$id -q '.state + " / " + .body'
gh api repos/dexpace/morphic/pulls/463/reviews -q '.[-1].id' | xargs -I{} gh api --method DELETE repos/dexpace/morphic/pulls/463/reviews/{} 2>/dev/null || echo "manual cleanup: dismiss review $id on GitHub"
rm -f ~/.local/share/nvim/pr_review/dexpace_morphic_463.review.json
```
Expected: the notify shows "review submitted (COMMENT)"; the last review's state/body match; cleanup deletes it (COMMENT reviews are deletable; a submitted APPROVE/REQUEST_CHANGES would need `dismiss`).

- [ ] **Step 5: Docs**

In `lua/plugins/CLAUDE.md` diffview section add a `#### Review notes` block: `<leader>gn` add/edit note (line or visual range, either pane), `<leader>gN` delete, `<leader>gs` submit (Comment/Approve/Request changes, summary editor), `:PrReviewDiscard`; pending review persisted to `<key>.review.json`; existing threads rendered inline read-only. In root `CLAUDE.md` Shared Utilities add `lua/pr_review_notes.lua`.

- [ ] **Step 6: Format + commit**

```bash
cd /home/fuad/.config/nvim
stylua --check . || stylua .
git add lua/pr_review_notes.lua lua/pr_review.lua lua/plugins/diffview.lua lua/plugins/CLAUDE.md CLAUDE.md
git commit -m "feat: submit GitHub reviews from diffview + wire notes commands"
```

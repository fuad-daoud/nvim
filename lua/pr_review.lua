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

local function mark_row(buf, row)
  vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { virt_text = { { '✓', 'DiffviewFilePanelInsertions' } }, virt_text_pos = 'overlay' })
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_col = #line, hl_group = 'Comment', priority = 200 })
end

-- Paint ✓ + dimmed rows for viewed files (and collapsed directories whose files are all viewed), plus a counter on the
-- "Changes" title. Runs after every panel redraw.
function M.decorate(panel)
  local buf = panel.bufid
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  if not state.pr_id or not panel.components then
    return
  end
  local total, done, dirs = 0, 0, {}
  panel.components.comp:deep_some(function(comp)
    if comp.name == 'directory' and comp.context.collapsed then
      table.insert(dirs, comp) -- like diffview's folder status letter, only shown while collapsed
    elseif comp.name == 'file' then
      total = total + 1
      if state.viewed[comp.context.path] then
        done = done + 1
        mark_row(buf, comp.lstart)
      end
    end
    return false
  end)
  for _, dir in ipairs(dirs) do
    local prefix, n, all = dir.context.path .. '/', 0, true
    panel.components.comp:deep_some(function(comp)
      if comp.name == 'file' and vim.startswith(comp.context.path, prefix) then
        n = n + 1
        all = all and state.viewed[comp.context.path] ~= nil
      end
      return not all
    end)
    if n > 0 and all then
      mark_row(buf, dir.components[1].lstart)
    end
  end
  local title = panel.components.working.title.comp
  if title and title.lstart then
    local counter = { { ' ✓ ' .. done .. '/' .. total, 'DiffviewFilePanelCounter' } }
    vim.api.nvim_buf_set_extmark(buf, ns, title.lstart, 0, { virt_text = counter, virt_text_pos = 'eol' })
  end
  -- PR number on the panel's path line, read from the view that owns this panel (per-tab).
  local pr
  for _, view in ipairs(require('diffview.lib').views) do
    if view.panel == panel then
      pr = view.pr
      break
    end
  end
  local path = panel.components.path and panel.components.path.comp
  if pr and path and path.lstart then
    vim.api.nvim_buf_set_extmark(buf, ns, path.lstart, 0, { virt_text = { { '  PR #' .. pr.number, 'DiffviewFilePanelCounter' } }, virt_text_pos = 'eol' })
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

-- GitHub rejects a request with too many aliased mutations ("Resource limits for this query exceeded"; measured
-- limit is somewhere in 50-59), so directory toggles are sent in batches of this size.
local BATCH = 25

-- Flip `paths` to `viewed` on GitHub, one aliased mutation per batch; optimistic, each failed batch is reverted.
local function set_viewed(panel, paths, viewed)
  local pr_id = state.pr_id
  for _, p in ipairs(paths) do
    state.viewed[p] = viewed or nil
  end
  panel:redraw()
  local mutation = viewed and 'markFileAsViewed' or 'unmarkFileAsViewed'
  for i = 1, #paths, BATCH do
    local batch = vim.list_slice(paths, i, i + BATCH - 1)
    local fields = {}
    for j, p in ipairs(batch) do
      fields[j] = ('f%d: %s(input:{pullRequestId:$id,path:%s}){ clientMutationId }'):format(j, mutation, vim.json.encode(p))
    end
    graphql('mutation($id:ID!){ ' .. table.concat(fields, ' ') .. ' }', { id = pr_id }, function(data, err)
      if state.pr_id ~= pr_id then
        return
      end
      if not data or data.errors then
        for _, p in ipairs(batch) do
          state.viewed[p] = (not viewed) or nil
        end
        redraw_panel()
        local reason = err ~= '' and err or (data.errors[1] and data.errors[1].message) or vim.inspect(data.errors)
        vim.notify(('pr_review: %s failed for %d file(s)\n%s'):format(mutation, #batch, reason), vim.log.levels.ERROR)
      end
    end)
  end
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

-- `:PrReview [number] [--commits]`: checkout, detect base, fetch, then open diffview against the base.
-- Default view is the whole PR with viewed marks; `--commits` opens the commit-by-commit history instead.
function M.open(args)
  local number, commits
  for _, a in ipairs(vim.split(args or '', '%s+', { trimempty = true })) do
    if a == '--commits' then
      commits = true
    else
      number = a
    end
  end
  if number then
    local res = gh({ 'pr', 'checkout', number }):wait()
    if res.code ~= 0 then
      vim.notify('gh pr checkout ' .. number .. ' failed:\n' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
  end
  M.reset()
  local base, pr = 'master', nil
  local res = gh({ 'pr', 'view', '--json', 'id,baseRefName,number,title,body,url' }):wait()
  if res.code == 0 then
    local ok, decoded = pcall(vim.json.decode, res.stdout)
    if ok and decoded.id then
      pr = decoded
      state.pr_id = pr.id
      base = pr.baseRefName
    end
  end
  vim.system({ 'git', 'fetch', 'origin', base }, { text = true }):wait()
  if commits then
    vim.cmd('DiffviewFileHistory --range=origin/' .. base .. '...HEAD --reverse')
    return
  end
  vim.cmd('DiffviewOpen origin/' .. base .. '...HEAD')
  if pr then
    local view = require('diffview.lib').get_current_view()
    if view then
      view.pr = { number = pr.number, url = pr.url, title = pr.title } -- per-view so each tab shows its own PR
    end
    M.load_viewed()
    require('pr_companion').offer(pr)
    require('pr_review_notes').attach(pr)
  end
end

-- The PR shown in the current diffview tab (per-view), or nil. Used by :PrUrl and the panel header.
function M.current()
  local view = require('diffview.lib').get_current_view()
  return view and view.pr or nil
end

-- Summarise statusCheckRollup as { ok = n, failed = n, pending = n, names = { failed/pending check names } }.
local function summarise_checks(rollup)
  local c = { ok = 0, failed = 0, pending = 0, names = {} }
  for _, check in ipairs(rollup or {}) do
    local state = check.conclusion or check.state or check.status or ''
    if state == 'SUCCESS' or state == 'NEUTRAL' or state == 'SKIPPED' then
      c.ok = c.ok + 1
    elseif state == 'FAILURE' or state == 'ERROR' or state == 'CANCELLED' or state == 'TIMED_OUT' or state == 'ACTION_REQUIRED' then
      c.failed = c.failed + 1
      table.insert(c.names, (check.name or check.context or '?') .. ' ✗')
    else
      c.pending = c.pending + 1
      table.insert(c.names, (check.name or check.context or '?') .. ' …')
    end
  end
  return c
end

-- Run the merge with the edited message; closes diffview on success. `auto` queues it (--auto) instead.
local function run_merge(pr, subject, body, auto)
  local args = { 'pr', 'merge', tostring(pr.number), '--squash', '--delete-branch', '--subject', subject, '--body', body }
  if auto then
    table.insert(args, '--auto')
  end
  vim.notify(('pr_review: %s PR #%d…'):format(auto and 'queueing' or 'merging', pr.number), vim.log.levels.INFO)
  gh(args, nil, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        return vim.notify('pr_review: merge failed\n' .. (out.stderr ~= '' and out.stderr or out.stdout), vim.log.levels.ERROR)
      end
      vim.notify(
        ('pr_review: PR #%d %s\n%s'):format(pr.number, auto and 'auto-merge enabled' or 'merged', vim.trim(out.stdout .. out.stderr)),
        vim.log.levels.INFO
      )
      if not auto then
        pcall(vim.cmd, 'DiffviewClose')
      end
    end)
  end)
end

-- Floating gitcommit buffer prefilled with the squash message. `:w` merges, `q` aborts.
local function edit_merge_message(pr, auto)
  local lines = { ('%s (#%d)'):format(pr.title, pr.number), '' }
  vim.list_extend(lines, vim.split(pr.body ~= vim.NIL and pr.body or '', '\n'))
  vim.list_extend(lines, {
    '',
    ('# Squash-merging PR #%d into %s (%s).'):format(pr.number, pr.baseRefName, auto and 'auto-merge when checks pass' or 'now'),
    '# First line is the commit subject, the rest is the body. Lines starting with # are ignored.',
    '# :w merges with this message · q aborts.',
    '#',
    '# Commits being squashed:',
  })
  for _, c in ipairs(pr.commits or {}) do
    table.insert(lines, ('#   %s %s'):format(c.oid:sub(1, 7), c.messageHeadline))
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, 'pr-merge://' .. pr.number)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'gitcommit'
  local width, height = math.min(100, vim.o.columns - 4), math.min(#lines + 2, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = 'minimal',
    border = 'rounded',
    title = (' Squash merge #%d '):format(pr.number),
  })
  vim.wo[win].wrap = true
  vim.keymap.set('n', 'q', function()
    vim.api.nvim_win_close(win, true)
    vim.notify('pr_review: merge aborted', vim.log.levels.INFO)
  end, { buffer = buf, desc = 'Abort merge' })
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      local msg = vim.tbl_filter(function(l)
        return not l:match '^#'
      end, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      local subject = vim.trim(msg[1] or '')
      if subject == '' then
        return vim.notify('pr_review: empty commit subject', vim.log.levels.ERROR)
      end
      local body = vim.trim(table.concat(vim.list_slice(msg, 2), '\n'))
      vim.bo[buf].modified = false
      vim.api.nvim_win_close(win, true)
      run_merge(pr, subject, body, auto)
    end,
  })
end

-- `:PrMerge`: readiness summary → confirm → edit squash message → `gh pr merge --squash --delete-branch`.
function M.merge()
  local fields = 'number,title,body,url,baseRefName,headRefName,mergeable,reviewDecision,isDraft,state,statusCheckRollup,commits'
  local res = gh({ 'pr', 'view', '--json', fields }):wait()
  if res.code ~= 0 then
    return vim.notify('pr_review: not on a PR branch\n' .. (res.stderr or ''), vim.log.levels.ERROR)
  end
  local pr = vim.json.decode(res.stdout)
  if pr.state ~= 'OPEN' then
    return vim.notify(('pr_review: PR #%d is %s'):format(pr.number, pr.state), vim.log.levels.WARN)
  end
  if pr.isDraft then
    return vim.notify(('pr_review: PR #%d is a draft'):format(pr.number), vim.log.levels.WARN)
  end
  if pr.mergeable == 'CONFLICTING' then
    return vim.notify(('pr_review: PR #%d has merge conflicts'):format(pr.number), vim.log.levels.ERROR)
  end
  local checks = summarise_checks(pr.statusCheckRollup)
  local summary = ('#%d %s\n%s → %s · review: %s · checks: %d ok, %d failed, %d pending'):format(
    pr.number,
    pr.title,
    pr.headRefName,
    pr.baseRefName,
    pr.reviewDecision ~= vim.NIL and pr.reviewDecision or 'none',
    checks.ok,
    checks.failed,
    checks.pending
  )
  if #checks.names > 0 then
    summary = summary .. '\n' .. table.concat(checks.names, ', ')
  end
  vim.notify(summary, vim.log.levels.INFO)
  local choices = { 'Squash merge + delete branch', 'Cancel' }
  if checks.pending > 0 then
    table.insert(choices, 1, 'Enable auto-merge (squash + delete branch when checks pass)')
  end
  vim.ui.select(choices, { prompt = ('Merge PR #%d into %s?'):format(pr.number, pr.baseRefName) }, function(choice)
    if not choice or choice == 'Cancel' then
      return
    end
    edit_merge_message(pr, choice:find '^Enable auto' ~= nil)
  end)
end

-- Debug: print viewed state + extmarks for the entry under the cursor (and every file under it, for a directory).
function M.inspect()
  local panel = current_panel()
  local item = panel and panel:get_item_at_cursor()
  if not item then
    return print 'pr_review: nothing under cursor'
  end
  local prefix = item.basename and item.path or item.path .. '/'
  print(('pr_id=%s cwd=%s item=%s'):format(tostring(state.pr_id), vim.fn.getcwd(), item.path))
  panel.components.comp:deep_some(function(comp)
    if comp.name == 'file' and vim.startswith(comp.context.path, prefix) then
      local marks = vim.api.nvim_buf_get_extmarks(panel.bufid, ns, { comp.lstart, 0 }, { comp.lstart, -1 }, {})
      print(('  %-60s viewed=%-5s lstart=%d extmarks=%d'):format(comp.context.path, tostring(state.viewed[comp.context.path] ~= nil), comp.lstart, #marks))
    end
    return false
  end)
end

function M.setup()
  local FilePanel = require('diffview.scene.views.diff.file_panel').FilePanel
  local redraw = FilePanel.redraw
  FilePanel.redraw = function(self, ...)
    redraw(self, ...)
    M.decorate(self)
  end
  vim.api.nvim_create_user_command('PrMerge', M.merge, { desc = 'Squash-merge the current PR (gh pr merge --squash --delete-branch)' })
  vim.api.nvim_create_user_command('PrUrl', function()
    local pr = M.current()
    if not pr then
      return vim.notify('pr_review: no PR in the current view', vim.log.levels.INFO)
    end
    vim.fn.setreg('+', pr.url)
    vim.notify('pr_review: copied ' .. pr.url, vim.log.levels.INFO)
  end, { desc = 'Copy the current PR URL to the system clipboard' })
  vim.api.nvim_create_user_command('PrReview', function(opts)
    M.open(opts.args)
  end, {
    nargs = '*',
    complete = function()
      return { '--commits' }
    end,
    desc = 'Checkout PR [number] and open diffview against its base (--commits: one commit at a time)',
  })
end

return M

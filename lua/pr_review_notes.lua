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
  local mt = {}
  function mt:__index(key)
    if key == 'current' then
      return current
    elseif key == 'review' then
      return review
    elseif key == 'threads' then
      return threads
    end
  end
  function mt:__newindex(key, value)
    if key == 'current' then
      current = value
    elseif key == 'review' then
      review = value
    elseif key == 'threads' then
      threads = value
    end
  end

  return setmetatable({}, mt)
end

-- diffview buffer name -> (path, side). RIGHT when the rev prefixes HEAD, else LEFT. nil for non-diff buffers.
function M._parse_diff_name(name, head)
  local rev, path = name:match '^diffview://.-/%.git/([^/]+)/(.*)$'
  if not rev then
    return nil
  end
  return path, (head and vim.startswith(head, rev)) and 'RIGHT' or 'LEFT'
end

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

-- Location from the current diff buffer + command range. Returns {path, side, line, start_line?} or nil.
local function note_loc(opts)
  local buf = vim.api.nvim_get_current_buf()
  local path, side = M._parse_diff_name(vim.api.nvim_buf_get_name(buf), head_rev())
  if not path then
    vim.notify('pr_review_notes: not in a diff buffer', vim.log.levels.INFO)
    return
  end
  local a, b
  if opts and opts.range and opts.range > 0 then
    a, b = opts.line1, opts.line2
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

function M.add_note(opts)
  if not current then
    return vim.notify('pr_review_notes: open a PR with :PrReview first', vim.log.levels.INFO)
  end
  local loc = note_loc(opts)
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
    return vim.notify('pr_review_notes: open a PR with :PrReview first', vim.log.levels.INFO)
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
    if vim.api.nvim_buf_get_name(b):find '^diffview://' and vim.api.nvim_buf_get_name(b):find '%.git/' then
      M.decorate(b)
    end
  end
end

function M.discard()
  if not current then
    return
  end
  review = { verdict = 'COMMENT', summary = '', notes = {} }
  os.remove(review_file())
  M.redraw_all()
end

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
  vim.ui.select(
    { 'Comment', 'Approve', 'Request changes' },
    { prompt = ('Submit review on PR #%d (%d notes)'):format(current.number, #review.notes) },
    function(choice)
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
          if review.verdict == 'REQUEST_CHANGES' and #review.notes == 0 and review.summary == '' then
            vim.bo[buf].modified = false
            return vim.notify('pr_review_notes: request-changes needs a summary or notes', vim.log.levels.ERROR)
          end
          vim.bo[buf].modified = false
          vim.api.nvim_win_close(win, true)
          post_review()
        end,
      })
    end
  )
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

return M

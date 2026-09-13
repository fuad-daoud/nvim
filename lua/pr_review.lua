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
    local counter = { { ' ✓ ' .. done .. '/' .. total, 'DiffviewFilePanelCounter' } }
    vim.api.nvim_buf_set_extmark(buf, ns, title.lstart, 0, { virt_text = counter, virt_text_pos = 'eol' })
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

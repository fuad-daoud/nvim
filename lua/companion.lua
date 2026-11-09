-- Shared engine for the AI companions (pr_companion, solve_companion): one headless agent session per target,
-- streamed into a persistent markdown pane. `new(spec)` returns an instance; the domain layer supplies the target
-- (`set_current`), prompts and user commands.
--
-- Two backends, picked per instance with `set_backend` and persisted in stdpath('data')/<spec.name>/backend.json:
--  claude  `claude -p` (default: opus, high effort)
--  agy     Antigravity CLI (headless when the prompt comes on stdin; `--model <base id> --effort <level>`)
-- A session belongs to the backend that created it (sessions[key].backend); the two cannot resume each other's, so
-- `request` refuses to resume across backends and the domain layer offers a reset instead.
--
-- Sessions live in stdpath('data')/<spec.name>/sessions.json keyed by current.key; each pane is mirrored to <key>.md
-- next to it. The companion is strictly read-only:
--  claude  `--restricted` ignores settings files (the user's global `defaultMode = auto` would otherwise auto-approve
--          everything) and drops every tool not named in `--tools`; in print mode anything outside `spec.allowed` is
--          denied rather than prompted, and `spec.denied` wins over `spec.allowed`.
--  agy     headless mode auto-denies every permission it cannot prompt for (commands, writes); file reads in the
--          workspace are free. `spec.agy_allow` adds prefix rules such as `command(python3 lc.py test)` (each token
--          matched whole; `a && b` does not match `a`); writes, URL fetches and MCP are denied outright. NB: a denied
--          action ends agy's turn with an empty response, so prompts should steer it to its file tools.
local M = {}

local TIMEOUT_MS = 10 * 60 * 1000

M.EFFORTS = { 'low', 'medium', 'high', 'xhigh', 'max' }
M.CLAUDE_MODELS = { 'opus', 'sonnet', 'haiku' }
local DEFAULT_BACKEND = { name = 'claude', model = 'opus', effort = 'high' }
local AGY_DENY = { 'write_file(*)', 'execute_url(*)', 'mcp(*)' }

-- RFC 4122 v4 from OS randomness (math.random is unseeded in a fresh Neovim and would repeat).
function M.uuid()
  local b = { vim.uv.random(16):byte(1, 16) }
  b[7] = bit.bor(bit.band(b[7], 0x0f), 0x40)
  b[9] = bit.bor(bit.band(b[9], 0x3f), 0x80)
  return ('%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x'):format(unpack(b))
end

-- One-line description of a tool call for the activity log.
local function describe(name, what)
  return ('· %s %s'):format(name, (tostring(what or ''):gsub('\n.*', '')):sub(1, 70))
end

local function read_json(path)
  local f = io.open(path)
  local ok, decoded = pcall(vim.json.decode, f and f:read '*a' or '')
  if f then
    f:close()
  end
  return ok and type(decoded) == 'table' and decoded or nil
end

local function write_json(path, tbl)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local f = assert(io.open(path, 'w'))
  f:write(vim.json.encode(tbl))
  f:close()
end

-- `agy models` → { { id = 'gemini-4-argon', label = 'Gemini 4 Argon', efforts = { 'medium', 'high', 'low' } }, … }.
-- Its ids carry the effort (gemini-4-argon-high) but agy wants the base id plus `--effort`. Cached per Neovim session.
local agy_models
function M.agy_models(cb)
  if agy_models then
    return cb(agy_models)
  end
  if vim.fn.executable 'agy' ~= 1 then
    return cb(nil, 'agy CLI not found on PATH')
  end
  vim.system({ 'agy', 'models' }, { text = true, timeout = 30000 }, function(res)
    vim.schedule(function()
      local list, by_id = {}, {}
      for line in (res.stdout or ''):gmatch '[^\n]+' do
        local id, label = line:match '^(%S+)\t(.+)$'
        if id then
          local base, effort = id:match '^(.-)%-(%a+)$'
          if not (base and vim.tbl_contains(M.EFFORTS, effort)) then
            base, effort = id, nil
          end
          local m = by_id[base]
          if not m then
            m = { id = base, label = (label:gsub('%s*%(%a+%)$', '')), efforts = {} }
            by_id[base] = m
            table.insert(list, m)
          end
          if effort then
            table.insert(m.efforts, effort)
          end
        end
      end
      if #list == 0 then
        return cb(nil, 'agy models listed nothing: ' .. vim.trim(res.stderr or ''))
      end
      for _, m in ipairs(list) do
        table.sort(m.efforts, function(x, y)
          return vim.fn.index(M.EFFORTS, x) < vim.fn.index(M.EFFORTS, y)
        end)
      end
      agy_models = list
      cb(list)
    end)
  end)
end

-- Model choices for backend `name`, in the shape of M.agy_models.
function M.models(name, cb)
  if name == 'agy' then
    return M.agy_models(cb)
  end
  cb(vim.tbl_map(function(id)
    return { id = id, label = id, efforts = M.EFFORTS }
  end, M.CLAUDE_MODELS))
end

--- spec = { name, label, scheme, tools, allowed, denied, agy_allow?, pane_width?, not_ready }
---  name       data dir under stdpath('data')
---  label      prefix of every notification: '<label>: …'
---  scheme     pane buffer name is `<scheme>://<key>`
---  tools      claude `--tools` value, e.g. 'Read,Grep,Glob,Bash'
---  allowed    claude `--allowedTools` entries; denied  `--disallowedTools` entries (either may be empty)
---  agy_allow  agy `permissions.allow` rules, e.g. { 'command(python3 lc.py test)' } (default: none)
---  pane_width vsplit width (default 60)
---  not_ready  message when a command runs with no current target
function M.new(spec)
  local c = {}
  local pane_width = spec.pane_width or 60
  local data_dir = vim.fs.joinpath(vim.fn.stdpath 'data', spec.name)
  local sessions_file = vim.fs.joinpath(data_dir, 'sessions.json')
  local backend_file = vim.fs.joinpath(data_dir, 'backend.json')

  local current -- { key, title, root }
  local busy = false
  local sessions
  local backend

  c.uuid = M.uuid

  local function notify(msg, level)
    vim.notify(spec.label .. ': ' .. msg, level or vim.log.levels.INFO)
  end

  ---------------------------------------------------------------------------
  -- Backend: { name = 'claude'|'agy', model, effort? }
  ---------------------------------------------------------------------------

  function c.backend()
    if not backend then
      local b = read_json(backend_file)
      backend = b and (b.name == 'claude' or b.name == 'agy') and type(b.model) == 'string' and b or vim.deepcopy(DEFAULT_BACKEND)
    end
    return backend
  end

  function c.set_backend(b)
    backend = { name = b.name, model = b.model, effort = b.effort }
    write_json(backend_file, backend)
  end

  -- 'agy · gemini-4-argon · high'
  function c.tag()
    local b = c.backend()
    return table.concat({ b.name, b.model, b.effort }, ' · ')
  end

  ---------------------------------------------------------------------------
  -- Current target + sessions
  ---------------------------------------------------------------------------

  function c.set_current(cur)
    current = cur
  end

  function c.current()
    return current
  end

  function c.busy()
    return busy
  end

  local function load_sessions()
    if not sessions then
      sessions = read_json(sessions_file) or {}
    end
    return sessions
  end

  local function save_sessions()
    write_json(sessions_file, sessions)
  end

  function c.session()
    return current and load_sessions()[current.key] or nil
  end

  -- Backend the current session was created with (sessions from before backends existed are claude's), or nil.
  function c.session_backend()
    local s = c.session()
    return s and s.session_id and (s.backend or 'claude') or nil
  end

  -- Shallow-merge `tbl` into the current session and persist.
  function c.save_session(tbl)
    local all = load_sessions()
    all[current.key] = vim.tbl_extend('force', all[current.key] or {}, tbl)
    save_sessions()
  end

  function c.clear_session()
    load_sessions()[current.key] = nil
    save_sessions()
  end

  ---------------------------------------------------------------------------
  -- Headless runners. An adapter turns the backend + session into argv (`args`), folds one stream-json event into
  -- `live` = { activity = {…}, text = '' } and its private state `st` (`handle`), and reads the outcome (`finish` →
  -- text | nil, err). st.sid is the session id: claude takes the one we mint, agy reports its conversation id.
  ---------------------------------------------------------------------------

  local adapters = {}

  adapters.claude = {
    args = function(b, sess)
      local args = { 'claude', '-p', '--model', b.model, '--effort', b.effort or 'high', '--restricted', '--tools', spec.tools }
      vim.list_extend(args, { '--output-format', 'stream-json', '--verbose', '--include-partial-messages' })
      if #spec.allowed > 0 then
        table.insert(args, '--allowedTools')
        vim.list_extend(args, spec.allowed)
      end
      if #spec.denied > 0 then
        table.insert(args, '--disallowedTools')
        vim.list_extend(args, spec.denied)
      end
      return vim.list_extend(args, sess.resume and { '--resume', sess.resume } or { '--session-id', sess.new })
    end,
    handle = function(ev, live, st)
      if ev.type == 'assistant' then
        for _, block in ipairs(ev.message and ev.message.content or {}) do
          if block.type == 'tool_use' then
            local input = block.input or {}
            table.insert(live.activity, describe(block.name, input.command or input.file_path or input.pattern or input.path))
          end
        end
      elseif ev.type == 'stream_event' and ev.event then
        local e = ev.event
        if e.type == 'message_start' then
          live.text = ''
        elseif e.type == 'content_block_start' and e.content_block and e.content_block.type == 'thinking' then
          table.insert(live.activity, '· 💭 thinking')
        elseif e.type == 'content_block_delta' and e.delta and e.delta.type == 'text_delta' then
          live.text = live.text .. e.delta.text
        end
      elseif ev.type == 'result' then
        st.result = ev
      end
    end,
    finish = function(st, live)
      local r = st.result
      if not r then
        return nil
      end
      if r.is_error then
        return nil, tostring(r.result)
      end
      return r.result or live.text
    end,
    chat = function(_, id)
      return 'claude --resume ' .. id
    end,
  }

  adapters.agy = {
    args = function(b, sess)
      local perms = { deny = AGY_DENY }
      if spec.agy_allow and #spec.agy_allow > 0 then
        perms.allow = spec.agy_allow
      end
      local args = { 'agy', '--model', b.model }
      if b.effort then
        vim.list_extend(args, { '--effort', b.effort })
      end
      vim.list_extend(args, { '--output-format', 'stream-json', '--settings', vim.json.encode { permissions = perms } })
      if sess.resume then
        vim.list_extend(args, { '--conversation', sess.resume })
      end
      return args
    end,
    handle = function(ev, live, st)
      if ev.event == 'init' then
        st.sid = ev.conversation_id or st.sid
      elseif ev.event == 'step_update' and ev.step_update then
        local u = ev.step_update
        if u.step_type == 'agent_response' and u.text_delta then
          if st.step ~= u.step_index then
            st.step = u.step_index
            live.text = ''
          end
          live.text = live.text .. u.text_delta
        elseif u.step_type == 'tool' and u.step_index and not st.seen[u.step_index] then
          st.seen[u.step_index] = true
          local p = u.tool_info and u.tool_info.parameters or {}
          table.insert(live.activity, describe(u.tool_name, p.CommandLine or p.Path or p.AbsolutePath or p.SearchPath or p.DirectoryPath or p.Query))
        end
      elseif ev.event == 'result' then
        st.result = ev.result
      end
    end,
    finish = function(st, live)
      local r = st.result
      if not r then
        return nil
      end
      if r.conversation_id and r.conversation_id ~= '' then
        st.sid = r.conversation_id
      end
      if r.status ~= 'SUCCESS' then
        return nil, tostring(r.error or r.status)
      end
      local text = r.response and r.response ~= '' and r.response or live.text
      if vim.trim(text) ~= '' then
        return text
      end
      local denied = vim.tbl_map(function(d)
        return d.display_name or d.action
      end, r.denied_actions or {})
      if #denied > 0 then
        return nil, ('agy stopped: headless mode denied %s (outside the read-only allowlist) — ask again'):format(table.concat(denied, ', '))
      end
      return nil, 'agy returned an empty response'
    end,
    chat = function(b, id)
      local cmd = 'agy --conversation ' .. id
      if b.name == 'agy' then
        cmd = cmd .. ' --model ' .. vim.fn.shellescape(b.model) .. (b.effort and ' --effort ' .. b.effort or '')
      end
      return cmd
    end,
  }

  -- Run the current backend headless with `prompt` on stdin, streaming events. sess = { resume = id } or {} for a new
  -- session. `on_event(live)` is called (on the main loop) whenever the live state changes. cb(text|nil, err, sid).
  local function run(sess, prompt, on_event, cb)
    local b = c.backend()
    local a = adapters[b.name]
    if vim.fn.executable(b.name) ~= 1 then
      return cb(nil, b.name .. ' CLI not found on PATH')
    end
    if not sess.resume and b.name == 'claude' then
      sess.new = M.uuid()
    end
    busy = true
    local live, pending, st = { activity = {}, text = '' }, '', { seen = {}, sid = sess.resume or sess.new }
    local function on_stdout(_, data)
      if not data then
        return
      end
      pending = pending .. data
      local lines = vim.split(pending, '\n', { plain = true })
      pending = table.remove(lines)
      vim.schedule(function()
        for _, line in ipairs(lines) do
          local ok, ev = pcall(vim.json.decode, line)
          if ok and type(ev) == 'table' then
            a.handle(ev, live, st)
          end
        end
        on_event(live)
      end)
    end
    vim.system(a.args(b, sess), { text = true, stdin = prompt, cwd = current.root, timeout = TIMEOUT_MS, stdout = on_stdout }, function(res)
      vim.schedule(function()
        busy = false
        if res.signal ~= 0 and res.code ~= 0 then
          return cb(nil, ('%s gave up after %d minutes (killed)'):format(b.name, TIMEOUT_MS / 60000))
        end
        local text, err = a.finish(st, live)
        if text then
          return cb(text, nil, st.sid)
        end
        cb(nil, err or (res.code ~= 0 and (res.stderr ~= '' and res.stderr or 'exit ' .. res.code) or b.name .. ' ended without a result'))
      end)
    end)
  end

  ---------------------------------------------------------------------------
  -- Pane
  ---------------------------------------------------------------------------

  local function pane_file()
    return vim.fs.joinpath(data_dir, current.key .. '.md')
  end

  local function buf_name()
    return spec.scheme .. '://' .. current.key
  end

  -- Exact-name lookup: bufnr() takes a pattern, so bufnr('pr-companion://11') would happily return PR 112's pane.
  function c.find_pane_buf()
    local name = buf_name()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(buf) == name then
        return buf
      end
    end
  end

  -- Programmatic edits to a buffer shown in another window fire no TextChanged, and render-markdown only re-renders on
  -- events it listens to — streamed answers would stay raw markdown until the cursor entered the pane. Fire it by hand.
  local function touched(buf)
    vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf, modeline = false })
  end

  function c.pane_buf()
    local buf = c.find_pane_buf()
    if buf and vim.api.nvim_buf_is_loaded(buf) then
      return buf
    end
    if buf then
      -- :bdelete (e.g. <leader>hb's %bdelete) unloads the pane: still findable by name but empty, with no filetype or
      -- highlighter. Wipe it and rebuild from the mirror file — every write persists, so in-flight regions keep their rows.
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, buf_name())
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'hide'
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = 'markdown'
    local f = io.open(pane_file())
    if f then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(f:read '*a', '\n'))
      f:close()
    else
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# ' .. current.title, '' })
    end
    vim.keymap.set('n', 'q', c.toggle, { buffer = buf, desc = 'Close companion pane' })
    return buf
  end

  function c.pane_win()
    local buf = c.find_pane_buf()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        return win
      end
    end
  end

  function c.open_pane()
    local buf = c.pane_buf()
    local win = c.pane_win()
    if not win then
      local prev = vim.api.nvim_get_current_win()
      vim.cmd('botright ' .. pane_width .. 'vsplit')
      win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, buf)
      vim.wo[win].wrap = true
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = 'no'
      vim.api.nvim_set_current_win(prev)
    end
    return buf, win
  end

  local function persist(buf)
    vim.fn.mkdir(data_dir, 'p')
    local f = assert(io.open(pane_file(), 'w'))
    f:write(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    f:close()
  end

  -- Scroll the pane to `line` only if it is currently visible — writing must never force a hidden pane back open.
  local function scroll_if_visible(line)
    local win = c.pane_win()
    if win then
      vim.api.nvim_win_set_cursor(win, { line, 0 })
    end
  end

  -- Append lines to the pane buffer (creating it if needed) and scroll to the bottom if visible. Returns the first row.
  -- Deliberately does NOT open the window: a closed pane keeps receiving stream updates in the background.
  function c.append(lines)
    local buf = c.pane_buf()
    local row = vim.api.nvim_buf_line_count(buf)
    vim.api.nvim_buf_set_lines(buf, row, row, false, lines)
    touched(buf)
    scroll_if_visible(vim.api.nvim_buf_line_count(buf))
    persist(buf)
    return row
  end

  -- Replace pane rows [from, to) with `lines` and persist. Used to drop a failed entry.
  function c.set_lines(from, to, lines)
    local buf = c.pane_buf()
    vim.api.nvim_buf_set_lines(buf, from, to, false, lines)
    touched(buf)
    persist(buf)
  end

  -- A region of the pane owned by one in-flight request: `render(lines)` replaces it in place. Buffer-only, never opens.
  function c.region(row, len)
    local r = { row = row, len = len }
    function r.render(lines)
      local buf = c.pane_buf()
      vim.api.nvim_buf_set_lines(buf, r.row, r.row + r.len, false, lines)
      r.len = #lines
      touched(buf)
      scroll_if_visible(math.min(r.row + r.len, vim.api.nvim_buf_line_count(buf)))
      persist(buf)
    end
    return r
  end

  -- Runs a request into `r`: status line with elapsed time + recent activity + streamed text while working;
  -- the final answer (or an error line) when done. Re-renders on events and every 2 s for the clock.
  local function stream_into(r, label, sess, prompt, on_done)
    local started, timer, live = vim.uv.now(), vim.uv.new_timer(), { activity = {}, text = '' }
    local function draw()
      local secs = math.floor((vim.uv.now() - started) / 1000)
      local lines = { ('_%s (%dm%02ds)_'):format(label, secs / 60, secs % 60) }
      local n = #live.activity
      for i = math.max(1, n - 5), n do
        table.insert(lines, live.activity[i])
      end
      if live.text ~= '' then
        table.insert(lines, '')
        vim.list_extend(lines, vim.split(live.text, '\n'))
      end
      r.render(lines)
    end
    timer:start(2000, 2000, vim.schedule_wrap(draw))
    run(sess, prompt, function(l)
      live = l
      draw()
    end, function(result, err, sid)
      timer:stop()
      timer:close()
      on_done(result, err, sid)
    end)
  end

  function c.toggle()
    if not current then
      return notify(spec.not_ready)
    end
    local win = c.pane_win()
    if win then
      vim.api.nvim_win_close(win, true)
    else
      c.open_pane()
    end
  end

  ---------------------------------------------------------------------------
  -- Requests
  ---------------------------------------------------------------------------

  -- o = { entry, label, resume?, prompt, on_done? }: opens the pane, appends `entry` (its first line gets the backend
  -- tag, its LAST line is the placeholder), streams into a region over that line, then calls
  -- on_done(result, err, region, entry_row, session_id). `resume` is a session id; without it a new session starts.
  -- Without on_done the answer (or `**error:** …`) is rendered in place. Refuses while another request is running, and
  -- refuses to resume a session made by the other backend.
  function c.request(o)
    if busy then
      return notify('busy with the previous request', vim.log.levels.WARN)
    end
    local b = c.backend()
    if o.resume and c.session_backend() and c.session_backend() ~= b.name then
      return notify(('this session was made with %s but the engine is %s; switch back or reset'):format(c.session_backend(), b.name), vim.log.levels.WARN)
    end
    local entry = vim.deepcopy(o.entry)
    entry[1] = entry[1] .. '  · _' .. c.tag() .. '_'
    c.open_pane() -- surface the pane when a request starts; closing it afterwards keeps streaming in the background
    local row = c.append(entry)
    local r = c.region(row + #entry - 1, 1)
    stream_into(r, o.label, { resume = o.resume }, o.prompt, function(result, err, sid)
      if o.on_done then
        return o.on_done(result, err, r, row, sid)
      end
      if not result then
        return r.render { '**error:** ' .. err, '' }
      end
      r.render(vim.list_extend(vim.split(result, '\n'), { '' }))
    end)
  end

  function c.chat()
    local s = c.session()
    if not s or not s.session_id then
      return notify 'no session; bootstrap first'
    end
    local cmd = adapters[s.backend or 'claude'].chat(c.backend(), s.session_id)
    require('toggleterm.terminal').Terminal:new({ cmd = cmd, dir = current.root, direction = 'float', close_on_exit = true }):toggle()
  end

  function c.reset()
    if not current then
      return
    end
    c.clear_session()
    os.remove(pane_file())
    local buf = c.find_pane_buf()
    if buf then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    notify 'session cleared'
  end

  return c
end

return M

-- Shared engine for the AI companions (pr_companion, solve_companion): one headless Claude Code session per target,
-- streamed into a persistent markdown pane. `new(spec)` returns an instance; the domain layer supplies the target
-- (`set_current`), prompts and user commands.
--
-- Sessions live in stdpath('data')/<spec.name>/sessions.json keyed by current.key; each pane is mirrored to <key>.md
-- next to it. The companion is strictly read-only. `--restricted` ignores settings files (the user's global
-- `defaultMode = auto` would otherwise auto-approve everything) and drops every tool not named in `--tools`; in print
-- mode anything outside `spec.allowed` is denied rather than prompted, and `spec.denied` wins over `spec.allowed`.
local M = {}

local TIMEOUT_MS = 10 * 60 * 1000

-- RFC 4122 v4 from OS randomness (math.random is unseeded in a fresh Neovim and would repeat).
function M.uuid()
  local b = { vim.uv.random(16):byte(1, 16) }
  b[7] = bit.bor(bit.band(b[7], 0x0f), 0x40)
  b[9] = bit.bor(bit.band(b[9], 0x3f), 0x80)
  return ('%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x'):format(unpack(b))
end

-- One-line description of a tool call for the activity log.
local function describe_tool(block)
  local input = block.input or {}
  local what = input.command or input.file_path or input.pattern or input.path or ''
  what = tostring(what):gsub('\n.*', ''):sub(1, 70)
  return ('· %s %s'):format(block.name, what)
end

--- spec = { name, label, scheme, tools, allowed, denied, pane_width?, not_ready }
---  name       data dir under stdpath('data')
---  label      prefix of every notification: '<label>: …'
---  scheme     pane buffer name is `<scheme>://<key>`
---  tools      `--tools` value, e.g. 'Read,Grep,Glob,Bash'
---  allowed    `--allowedTools` entries; denied  `--disallowedTools` entries (either may be empty)
---  pane_width vsplit width (default 60)
---  not_ready  message when a command runs with no current target
function M.new(spec)
  local c = {}
  local pane_width = spec.pane_width or 60
  local data_dir = vim.fs.joinpath(vim.fn.stdpath 'data', spec.name)
  local sessions_file = vim.fs.joinpath(data_dir, 'sessions.json')

  local current -- { key, title, root }
  local busy = false
  local sessions

  c.uuid = M.uuid

  local function notify(msg, level)
    vim.notify(spec.label .. ': ' .. msg, level or vim.log.levels.INFO)
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
      local f = io.open(sessions_file)
      local ok, decoded = pcall(vim.json.decode, f and f:read '*a' or '')
      if f then
        f:close()
      end
      sessions = ok and type(decoded) == 'table' and decoded or {}
    end
    return sessions
  end

  local function save_sessions()
    vim.fn.mkdir(data_dir, 'p')
    local f = assert(io.open(sessions_file, 'w'))
    f:write(vim.json.encode(sessions))
    f:close()
  end

  function c.session()
    return current and load_sessions()[current.key] or nil
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
  -- Headless claude
  ---------------------------------------------------------------------------

  local function claude_args(extra)
    local args = { 'claude', '-p', '--model', 'opus', '--effort', 'high', '--restricted', '--tools', spec.tools }
    vim.list_extend(args, { '--output-format', 'stream-json', '--verbose', '--include-partial-messages' })
    if #spec.allowed > 0 then
      table.insert(args, '--allowedTools')
      vim.list_extend(args, spec.allowed)
    end
    if #spec.denied > 0 then
      table.insert(args, '--disallowedTools')
      vim.list_extend(args, spec.denied)
    end
    return vim.list_extend(args, extra)
  end

  -- Run claude headless with `prompt` on stdin, streaming events. `on_event(live)` is called (on the main loop)
  -- whenever the live state changes: live = { activity = {…}, text = '' }. cb(result_text|nil, err) at the end.
  local function claude(extra, prompt, on_event, cb)
    if vim.fn.executable 'claude' ~= 1 then
      return cb(nil, 'claude CLI not found on PATH')
    end
    busy = true
    local live, pending, result = { activity = {}, text = '' }, '', nil
    local function handle(ev)
      if ev.type == 'assistant' then
        for _, block in ipairs(ev.message and ev.message.content or {}) do
          if block.type == 'tool_use' then
            table.insert(live.activity, describe_tool(block))
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
        result = ev
      end
    end
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
            handle(ev)
          end
        end
        on_event(live)
      end)
    end
    vim.system(claude_args(extra), { text = true, stdin = prompt, cwd = current.root, timeout = TIMEOUT_MS, stdout = on_stdout }, function(res)
      vim.schedule(function()
        busy = false
        if res.signal ~= 0 and res.code ~= 0 then
          return cb(nil, ('claude gave up after %d minutes (killed)'):format(TIMEOUT_MS / 60000))
        end
        if not result then
          return cb(nil, res.code ~= 0 and (res.stderr ~= '' and res.stderr or 'exit ' .. res.code) or 'claude ended without a result')
        end
        if result.is_error then
          return cb(nil, tostring(result.result))
        end
        cb(result.result or live.text)
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
  local function stream_into(r, label, extra, prompt, on_done)
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
    claude(extra, prompt, function(l)
      live = l
      draw()
    end, function(result, err)
      timer:stop()
      timer:close()
      on_done(result, err)
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

  -- o = { entry, label, extra, prompt, on_done? }: opens the pane, appends `entry` (its LAST line is the placeholder),
  -- streams into a region over that line, then calls on_done(result, err, region, entry_row). Without on_done the
  -- answer (or `**error:** …`) is rendered in place. Refuses while another request is running.
  function c.request(o)
    if busy then
      return notify('busy with the previous request', vim.log.levels.WARN)
    end
    c.open_pane() -- surface the pane when a request starts; closing it afterwards keeps streaming in the background
    local row = c.append(o.entry)
    local r = c.region(row + #o.entry - 1, 1)
    stream_into(r, o.label, o.extra, o.prompt, function(result, err)
      if o.on_done then
        return o.on_done(result, err, r, row)
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
    require('toggleterm.terminal').Terminal
      :new({ cmd = 'claude --resume ' .. s.session_id, dir = current.root, direction = 'float', close_on_exit = true })
      :toggle()
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

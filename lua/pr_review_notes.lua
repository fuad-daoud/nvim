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

return M

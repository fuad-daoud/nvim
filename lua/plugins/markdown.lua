---@param buf integer
---@return { code: string, row: integer }[]
local function find_mermaid_blocks(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  if not ok or not parser then
    return {}
  end
  local trees = parser:parse()
  if not trees or not trees[1] then
    return {}
  end

  local blocks = {}

  local function visit(node)
    if node:type() == 'fenced_code_block' then
      local info_text = ''
      local code = ''
      local code_row = nil
      for child in node:iter_children() do
        local t = child:type()
        if t == 'info_string' then
          info_text = vim.treesitter.get_node_text(child, buf) or ''
        elseif t == 'code_fence_content' then
          code = vim.treesitter.get_node_text(child, buf) or ''
          code_row = child:start()
        end
      end
      if info_text:lower():find '^mermaid' and code ~= '' and code_row then
        blocks[#blocks + 1] = { code = code, row = code_row }
      end
      return
    end
    for child in node:iter_children() do
      visit(child)
    end
  end

  visit(trees[1]:root())
  return blocks
end

---@type table<integer, table<integer, table>>
local mermaid_images = {}

---@param buf integer
local function clear_mermaid(buf)
  local imgs = mermaid_images[buf]
  if not imgs then
    return
  end
  for _, img in pairs(imgs) do
    pcall(function()
      img:clear()
    end)
  end
  mermaid_images[buf] = nil
end

---@param buf integer
local function render_mermaid(buf)
  if vim.fn.executable 'mmdc' == 0 then
    return
  end
  local ok, image_api = pcall(require, 'image')
  if not ok then
    return
  end

  clear_mermaid(buf)
  mermaid_images[buf] = {}

  local blocks = find_mermaid_blocks(buf)
  if #blocks == 0 then
    return
  end

  local tmpdir = vim.fn.stdpath 'cache' .. '/mermaid'
  vim.fn.mkdir(tmpdir, 'p')

  for _, block in ipairs(blocks) do
    local key = buf .. '_' .. block.row
    local input = tmpdir .. '/' .. key .. '.mmd'
    local output = tmpdir .. '/' .. key .. '.png'
    local row = block.row

    vim.fn.writefile(vim.split(block.code, '\n'), input)

    vim.system({ 'mmdc', '-i', input, '-o', output, '-b', 'transparent' }, {}, function(res)
      if res.code ~= 0 then
        return
      end
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        local win = vim.fn.bufwinid(buf)
        if win == -1 then
          return
        end
        local img = image_api.from_file(output, {
          buffer = buf,
          window = win,
          row = row,
          col = 0,
          with_virtual_padding = true,
        })
        if img then
          img:render()
          if mermaid_images[buf] then
            mermaid_images[buf][row] = img
          end
        end
      end)
    end)
  end
end

return {
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown' },
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    opts = {},
  },
  {
    '3rd/image.nvim',
    ft = { 'markdown' },
    opts = {
      backend = 'kitty',
      integrations = {
        markdown = { enabled = false },
        neorg = { enabled = false },
      },
      max_width_window_percentage = 80,
    },
    config = function(_, opts)
      require('image').setup(opts)
      local group = vim.api.nvim_create_augroup('mermaid-render', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost' }, {
        group = group,
        pattern = '*.md',
        callback = function(ev)
          render_mermaid(ev.buf)
        end,
      })
      vim.api.nvim_create_autocmd('BufWipeout', {
        group = group,
        pattern = '*.md',
        callback = function(ev)
          clear_mermaid(ev.buf)
        end,
      })
      -- image.nvim is lazy-loaded on ft=markdown, so BufReadPost has already fired
      -- for the buffer that triggered the load — render it now
      vim.schedule(function()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'markdown' then
            render_mermaid(buf)
          end
        end
      end)
    end,
  },
}

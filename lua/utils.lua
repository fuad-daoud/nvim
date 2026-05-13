local M = {}

M.emit_osc7 = function(cwd)
  cwd = cwd or vim.fn.getcwd()
  io.write(string.format('\027]7;file://%s%s\027\\', vim.fn.hostname(), cwd))
end

return M

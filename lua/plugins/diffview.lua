-- Side-by-side diff review of a PR. Workflow: `:PrReview 464` → <Tab>/<S-Tab> files, ]c/[c hunks, `-` toggle viewed.

-- Base branch of the PR on the current branch (`origin/<base>`), or `origin/master` if gh can't tell.
local function pr_base()
  local res = vim.system({ 'gh', 'pr', 'view', '--json', 'baseRefName', '-q', '.baseRefName' }, { text = true }):wait()
  local base = res.code == 0 and vim.trim(res.stdout or '') or ''
  if base == '' then
    base = 'master'
  end
  return 'origin/' .. base
end

local function pr_review(opts)
  local number = opts.args
  if number ~= '' then
    local res = vim.system({ 'gh', 'pr', 'checkout', number }, { text = true }):wait()
    if res.code ~= 0 then
      vim.notify('gh pr checkout ' .. number .. ' failed:\n' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
  end
  local base = pr_base()
  vim.system({ 'git', 'fetch', 'origin', (base:gsub('^origin/', '')) }, { text = true }):wait()
  vim.cmd('DiffviewOpen ' .. base .. '...HEAD')
end

return {
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory', 'PrReview' },
    keys = {
      { '<leader>gv', '<cmd>PrReview<cr>', desc = '[G]it re[V]iew PR (diffview)' },
      { '<leader>gV', '<cmd>DiffviewClose<cr>', desc = '[G]it close re[V]iew' },
    },
    opts = {
      enhanced_diff_hl = true,
      view = { merge_tool = { layout = 'diff3_mixed' } },
    },
    config = function(_, opts)
      require('diffview').setup(opts)
      vim.api.nvim_create_user_command('PrReview', pr_review, { nargs = '?', desc = 'Checkout PR [number] and open diffview against its base' })
    end,
  },
}

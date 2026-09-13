-- Side-by-side PR review. `:PrReview 464` → <Tab>/<S-Tab> files, ]c/[c hunks, `-` toggles GitHub "viewed"; `--commits` for one commit at a time. Logic lives in lua/pr_review.lua.
return {
  {
    'sindrets/diffview.nvim',
    cmd = { 'DiffviewOpen', 'DiffviewClose', 'DiffviewFileHistory', 'PrReview' },
    keys = {
      { '<leader>gv', '<cmd>PrReview<cr>', desc = '[G]it re[V]iew PR (diffview)' },
      { '<leader>gc', '<cmd>PrReview --commits<cr>', desc = '[G]it review PR by [C]ommit' },
      { '<leader>gV', '<cmd>DiffviewClose<cr>', desc = '[G]it close re[V]iew' },
    },
    opts = {
      enhanced_diff_hl = true,
      view = { merge_tool = { layout = 'diff3_mixed' } },
      file_panel = { win_config = { width = 45 } },
      keymaps = {
        file_panel = {
          {
            'n',
            '-',
            function()
              require('pr_review').toggle_viewed()
            end,
            { desc = 'Toggle viewed on GitHub' },
          },
        },
      },
      hooks = {
        view_closed = function()
          require('pr_review').reset()
        end,
      },
    },
    config = function(_, opts)
      require('diffview').setup(opts)
      require('pr_review').setup()
    end,
  },
}

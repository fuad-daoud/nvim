-- Side-by-side PR review. `:PrReview 464` → <Tab>/<S-Tab> files, ]c/[c hunks, `-` toggles GitHub "viewed"; `--commits` for one commit at a time. Logic lives in lua/pr_review.lua.
return {
  {
    'sindrets/diffview.nvim',
    cmd = {
      'DiffviewOpen',
      'DiffviewClose',
      'DiffviewFileHistory',
      'PrReview',
      'PrMerge',
      'PrCompanion',
      'PrAsk',
      'PrChat',
      'PrNote',
      'PrNoteDelete',
      'PrReviewSubmit',
      'PrReviewDiscard',
    },
    keys = {
      { '<leader>gv', '<cmd>PrReview<cr>', desc = '[G]it re[V]iew PR (diffview)' },
      { '<leader>gc', '<cmd>PrReview --commits<cr>', desc = '[G]it review PR by [C]ommit' },
      { '<leader>gV', '<cmd>DiffviewClose<cr>', desc = '[G]it close re[V]iew' },
      { '<leader>gm', '<cmd>PrMerge<cr>', desc = '[G]it PR: squash [M]erge' },
      { '<leader>gu', '<cmd>PrUrl<cr>', desc = '[G]it PR: copy [U]RL' },
      { '<leader>ga', ':PrAsk<cr>', mode = { 'n', 'x' }, desc = '[G]it PR: [A]sk companion (about selection)' },
      { '<leader>gA', '<cmd>PrCompanion toggle<cr>', desc = '[G]it PR: toggle companion p[A]ne' },
      { '<leader>gn', ':PrNote<cr>', mode = { 'n', 'x' }, desc = '[G]it PR: add/edit [N]ote' },
      { '<leader>gN', '<cmd>PrNoteDelete<cr>', desc = '[G]it PR: delete [N]ote' },
      { '<leader>gs', '<cmd>PrReviewSubmit<cr>', desc = '[G]it PR: [S]ubmit review' },
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
      require('pr_companion').setup()
      require('pr_review_notes').setup()
    end,
  },
}

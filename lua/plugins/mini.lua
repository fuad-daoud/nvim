return {
  { 'echasnovski/mini.pairs', version = '*', opts = {} },
  { 'echasnovski/mini.surround', version = '*', opts = {} },
  {
    'echasnovski/mini.animate',
    version = '*',
    opts = function()
      local animate = require 'mini.animate'
      local fast = animate.gen_timing.linear { duration = 60, unit = 'total' }
      return {
        scroll = { enable = false }, -- snacks.scroll owns this
        cursor = { timing = animate.gen_timing.linear { duration = 100, unit = 'total' } },
        resize = { timing = fast },
        open = { timing = fast },
        close = { timing = fast },
      }
    end,
  },
}

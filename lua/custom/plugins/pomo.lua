return {
  'epwalsh/pomo.nvim',
  version = '*', -- Recommended, use latest release instead of latest commit
  lazy = true,
  cmd = { 'TimerStart', 'TimerRepeat', 'TimerSession' },
  dependencies = {
    -- Optional, but highly:TimerStart 10s recommended if you want to use the "Default" timer
    'rcarriga/nvim-notify',
  },
  opts = {
    -- How often the notifiers are updated.
    update_interval = 1000,

    -- Configure the default notifiers to use for each timer.
    -- You can also configure different notifiers for timers given specific names, see
    -- the 'timers' field below.
    notifiers = {
      -- The "Default" notifier uses 'vim.notify' and works best when you have 'nvim-notify' installed.
      {
        name = 'Default',
        opts = {
          sticky = true,
          title_icon = '󱎫',
          text_icon = '󰄉',
          -- Replace the above with these if you don't have a patched font:
          -- title_icon = "⏳",
          -- text_icon = "⏱️",
        },
      },

      -- The "System" notifier sends a system notification when the timer is finished.
      -- Available on MacOS and Windows natively and on Linux via the `libnotify-bin` package.
      { name = 'System' },

      -- You can also define custom notifiers by providing an "init" function instead of a name.
      -- See "Defining custom notifiers" below for an example 👇
      -- { init = function(timer) ... end }
    },

    timers = {
      -- For example, use only the "System" notifier when you create a timer called "Break",
      -- e.g. ':TimerStart 2m Break'.
      Break = {
        { name = 'System' },
      },
    },
    sessions = {
      pomodoro = {
        { name = 'Work', duration = '25m' },
        { name = 'Short Break', duration = '5m' },
        { name = 'Work', duration = '25m' },
        { name = 'Short Break', duration = '5m' },
        { name = 'Work', duration = '25m' },
        { name = 'Long Break', duration = '15m' },
      },
    },
  },
}

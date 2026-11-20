-- Sessions per directory and git branch, with folke/persistence.nvim
-- (https://github.com/folke/persistence.nvim). A session is saved when
-- Neovim exits, if a file was open; nothing is restored automatically.
return {
  {
    "folke/persistence.nvim",
    version = "^3",
    -- Loaded when the first file is read, so it saves sessions that opened a
    -- file but doesn't slow down startup.
    event = "BufReadPre",
    init = function()
      -- Neovim's default also has terminal, which would bring the Claude
      -- Code terminal back as a new shell, and blank, which saves windows
      -- without a file. Leaving blank out keeps nvim-tree and trouble
      -- windows out of sessions too, since their buffers have no file.
      -- skiprtp keeps the session from overriding lazy.nvim's runtimepath.
      vim.opt.sessionoptions = { "buffers", "curdir", "folds", "help", "tabpages", "winsize", "skiprtp" }
    end,
    opts = {},
    config = function(_, opts)
      local persistence = require("persistence")
      persistence.setup(opts)
      -- Headless nvims (tests, bootstrap.sh, scripts) don't save sessions,
      -- or every run would leave one in the state dir.
      if #vim.api.nvim_list_uis() == 0 then
        persistence.stop()
      end
    end,
    -- <leader>w (workspace) rather than LazyVim's <leader>q: the buffers
    -- picker has a buffer-local <leader>q to delete a buffer, which would
    -- otherwise wait for timeoutlen in case <leader>qs followed.
    keys = {
      {
        "<leader>ws",
        function()
          require("persistence").load()
        end,
        desc = "Restore session for this directory",
      },
      {
        "<leader>wl",
        function()
          require("persistence").load({ last = true })
        end,
        desc = "Restore last session",
      },
      {
        "<leader>wS",
        function()
          require("persistence").select()
        end,
        desc = "Select a session",
      },
      {
        "<leader>wd",
        function()
          require("persistence").stop()
        end,
        desc = "Don't save this session on exit",
      },
    },
  },
}

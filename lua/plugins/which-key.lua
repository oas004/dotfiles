-- https://github.com/folke/which-key.nvim
-- Shows a popup with the available keys after a prefix such as <leader>.
-- Only group names are registered here; the maps themselves (and their
-- desc) live where they are defined.
--
-- Leader layout (see the README's Keybindings section). Register a group
-- here when its first map lands:
--   a  ai (Claude)        c  code: actions, format, rename
--   f  find (pickers)     g  git tools: diff views, Git UI, git pickers
--   h  git hunks          n  new
--   y  yank               d  debug
--   t  test               u  toggles (inlay hints, blame, ...)
--   x  lists (diagnostics, quickfix)
-- The single-letter maps from before the f group (p, o, r, s, S) are
-- aliases of the <leader>f maps. e/E (diagnostics) and l/L (nvim-tree)
-- stay single letters.
return {
  {
    "folke/which-key.nvim",
    version = "^3", -- the spec format below is the v3 one
    event = "VeryLazy",
    opts = {
      spec = {
        { "<leader>a", group = "ai (Claude)", mode = { "n", "v" } },
        { "<leader>c", group = "code" },
        { "<leader>f", group = "find", mode = { "n", "x" } },
        { "<leader>g", group = "git" },
        { "<leader>h", group = "git hunks", mode = { "n", "x" } },
        { "<leader>n", group = "new" },
        { "<leader>u", group = "toggles" },
        { "<leader>x", group = "lists" },
        { "<leader>y", group = "yank", mode = { "n", "x" } },
      },
    },
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer-local keymaps (which-key)",
      },
    },
  },
}

-- https://github.com/smart-splits-nvim/smart-splits.nvim
-- <C-h/j/k/l> move between Neovim windows, and past the last window into the
-- neighbouring tmux pane; <A-h/j/k/l> resize the same way. The tmux half
-- (key bindings in tmux.conf that pass the keys on to Neovim) is in the
-- README under "Window navigation and tmux".

-- Normal mode only. In terminal mode (the Claude Code terminal) the keys
-- belong to the program running there, and insert-mode <C-k> is LSP
-- signature help (plugins/language-server.lua).
local function map(lhs, fn, desc)
  return {
    lhs,
    function()
      require("smart-splits")[fn]()
    end,
    mode = "n",
    desc = desc,
  }
end

return {
  {
    "smart-splits-nvim/smart-splits.nvim",
    version = "^3",
    -- Not lazy-loaded: the tmux backend marks the pane as running Neovim
    -- (@pane-is-vim) when the plugin loads, and until then tmux keeps
    -- <C-h/j/k/l> for itself.
    lazy = false,
    dependencies = {
      -- v3 has no multiplexer support of its own. No release tags, so it
      -- follows master at the commit in lazy-lock.json.
      { "smart-splits-nvim/backend-tmux" },
    },
    opts = {
      mux = {
        -- Headless nvims (tests, bootstrap.sh, scripts) skip tmux, so they
        -- never set or clear @pane-is-vim on the pane they were started from.
        backend = function()
          return #vim.api.nvim_list_uis() > 0 and "smart-splits-backend-tmux" or {}
        end,
        -- Outside tmux this falls back to plain window movement, which is fine
        warn_if_unusable = false,
      },
    },
    keys = {
      map("<C-h>", "move_cursor_left", "Window: Move left (or tmux pane)"),
      map("<C-j>", "move_cursor_down", "Window: Move down (or tmux pane)"),
      map("<C-k>", "move_cursor_up", "Window: Move up (or tmux pane)"),
      map("<C-l>", "move_cursor_right", "Window: Move right (or tmux pane)"),
      map("<A-h>", "resize_left", "Window: Resize left"),
      map("<A-j>", "resize_down", "Window: Resize down"),
      map("<A-k>", "resize_up", "Window: Resize up"),
      map("<A-l>", "resize_right", "Window: Resize right"),
    },
  },
}

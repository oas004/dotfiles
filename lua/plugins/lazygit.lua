-- lazygit in a floating terminal, through snacks.nvim's lazygit module.
-- https://github.com/folke/snacks.nvim/blob/main/docs/lazygit.md
--
-- snacks writes a lazygit theme from the current colorscheme and sets
-- lazygit's editPreset to nvim-remote. lazygit runs in a Neovim terminal,
-- where $NVIM is set, so editing a file from lazygit (e) opens it in this
-- Neovim instead of a nested one.
--
-- This is a fragment of the snacks.nvim spec; lazy.nvim merges it with the
-- other specs that list snacks (e.g. claudecode.nvim's dependency).
-- bootstrap.sh installs the lazygit binary.

--- Run a snacks.lazygit function, or say how to install lazygit if it is missing.
--- Without the check snacks reports "Failed to get lazygit config directory"
--- and opens a terminal that exits at once.
---@param fn "open"|"log_file"
local function lazygit(fn)
  return function()
    if vim.fn.executable("lazygit") == 0 then
      vim.notify(
        "lazygit is not installed. Run bootstrap.sh, or install it from https://github.com/jesseduffield/lazygit#installation",
        vim.log.levels.ERROR
      )
      return
    end
    if fn == "log_file" and vim.api.nvim_buf_get_name(0) == "" then
      vim.notify("The buffer has no file, so there is no file history to show", vim.log.levels.WARN)
      return
    end
    require("snacks").lazygit[fn]()
  end
end

return {
  {
    "folke/snacks.nvim",
    opts = {
      lazygit = {},
    },
    keys = {
      { "<leader>gg", lazygit("open"), desc = "Git: lazygit" },
      { "<leader>gf", lazygit("log_file"), desc = "Git: lazygit history of the current file" },
    },
  },
}

-- Git signs in the sign column and hunk actions via gitsigns.nvim.
-- Keymaps are buffer-local and only set in buffers gitsigns attaches to.

--- Run a gitsigns toggle, which returns the new state, and report it.
---@param label string
---@param fn fun(value?: boolean): boolean
local function toggle(label, fn)
  vim.notify(label .. (fn() and " on" or " off"), vim.log.levels.INFO)
end

local function on_attach(bufnr)
  local gitsigns = require("gitsigns")

  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
  end

  -- In diff mode ]c and [c keep their built-in meaning (next/prev change).
  map("n", "]c", function()
    if vim.wo.diff then
      vim.cmd.normal({ "]c", bang = true })
    else
      gitsigns.nav_hunk("next")
    end
  end, "Git: Next hunk")

  map("n", "[c", function()
    if vim.wo.diff then
      vim.cmd.normal({ "[c", bang = true })
    else
      gitsigns.nav_hunk("prev")
    end
  end, "Git: Previous hunk")

  -- On a hunk that is already staged, stage_hunk unstages it (gitsigns
  -- deprecated undo_stage_hunk for this), so there is no separate unstage map.
  map("n", "<leader>hs", gitsigns.stage_hunk, "Git: Stage/unstage hunk")
  map("n", "<leader>hr", gitsigns.reset_hunk, "Git: Reset hunk")
  map("x", "<leader>hs", function()
    gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
  end, "Git: Stage selected lines")
  map("x", "<leader>hr", function()
    gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
  end, "Git: Reset selected lines")
  map("n", "<leader>hS", gitsigns.stage_buffer, "Git: Stage buffer")
  map("n", "<leader>hR", gitsigns.reset_buffer, "Git: Reset buffer")
  map("n", "<leader>hp", gitsigns.preview_hunk, "Git: Preview hunk")
  -- Shows the hunk's deleted lines inline (replaces gitsigns' deprecated
  -- toggle_deleted)
  map("n", "<leader>hi", gitsigns.preview_hunk_inline, "Git: Preview hunk inline")
  map("n", "<leader>hb", function()
    gitsigns.blame_line({ full = true })
  end, "Git: Blame line")
  map("n", "<leader>hd", function()
    gitsigns.diffthis()
  end, "Git: Diff against the index")
  map("n", "<leader>hD", function()
    gitsigns.diffthis("@")
  end, "Git: Diff against the last commit")
  map("n", "<leader>hq", function()
    gitsigns.setqflist("all")
  end, "Git: All hunks in the repo to quickfix")

  map("n", "<leader>ub", function()
    toggle("Blame on the current line", gitsigns.toggle_current_line_blame)
  end, "Toggle git blame on the current line")
  map("n", "<leader>uw", function()
    toggle("Git word diff", gitsigns.toggle_word_diff)
  end, "Toggle git word diff")

  map({ "o", "x" }, "ih", gitsigns.select_hunk, "Git: Select hunk")
end

return {
  -- https://github.com/lewis6991/gitsigns.nvim
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      on_attach = on_attach,
    },
  },
}

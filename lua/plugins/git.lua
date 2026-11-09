-- Git signs in the sign column and hunk actions via gitsigns.nvim.
-- Keymaps are buffer-local and only set in buffers gitsigns attaches to.

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

  map("n", "<leader>hs", gitsigns.stage_hunk, "Git: Stage hunk")
  map("n", "<leader>hr", gitsigns.reset_hunk, "Git: Reset hunk")
  map("x", "<leader>hs", function()
    gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
  end, "Git: Stage selected lines")
  map("x", "<leader>hr", function()
    gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
  end, "Git: Reset selected lines")
  map("n", "<leader>hp", gitsigns.preview_hunk, "Git: Preview hunk")
  map("n", "<leader>hb", function()
    gitsigns.blame_line({ full = true })
  end, "Git: Blame line")

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

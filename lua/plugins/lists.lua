-- https://github.com/folke/trouble.nvim
-- Lists under <leader>x: diagnostics, symbols, LSP locations, quickfix and
-- location list, each in a split window that follows the current buffer.

local function toggle(mode, opts)
  return function()
    require("trouble").toggle(vim.tbl_extend("force", { mode = mode }, opts or {}))
  end
end

-- ]q/[q step through the items of an open trouble window (jumping to each),
-- and are Neovim's built-in :cnext/:cprevious otherwise. trouble can only be
-- open once it is loaded, so the check doesn't load it.
local function quickfix_nav(lhs, direction)
  local builtin = vim.fn.maparg(lhs, "n", false, true)
  vim.keymap.set("n", lhs, function()
    if package.loaded["trouble"] and require("trouble").is_open() then
      require("trouble")[direction]({ skip_groups = true, jump = true })
    elseif builtin.callback then
      builtin.callback()
    end
  end, { desc = (direction == "next" and "Next" or "Previous") .. " trouble item, or " .. (builtin.desc or lhs) })
end

return {
  {
    "folke/trouble.nvim",
    version = "^3",
    cmd = "Trouble",
    keys = {
      { "<leader>xx", toggle("diagnostics"), desc = "Diagnostics (workspace)" },
      { "<leader>xX", toggle("diagnostics", { filter = { buf = 0 } }), desc = "Diagnostics (buffer)" },
      { "<leader>xs", toggle("symbols", { focus = false }), desc = "Symbols (buffer)" },
      {
        "<leader>xr",
        toggle("lsp", { focus = false, win = { position = "right" } }),
        desc = "LSP definitions, references, implementations",
      },
      { "<leader>xq", toggle("qflist"), desc = "Quickfix list" },
      { "<leader>xl", toggle("loclist"), desc = "Location list" },
    },
    opts = {},
    init = function()
      quickfix_nav("]q", "next")
      quickfix_nav("[q", "prev")
    end,
  },
}

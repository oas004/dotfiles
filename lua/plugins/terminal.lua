-- A shell in a bottom split, toggled with <C-/>, through snacks.nvim's
-- terminal module (https://github.com/folke/snacks.nvim/blob/main/docs/terminal.md).
-- lazy.nvim merges this fragment with the other snacks.nvim specs.
--
-- Terminals send Ctrl+/ as <C-_> unless they support the kitty keyboard
-- protocol, so both keys are mapped. A count picks the terminal: 2<C-/>
-- toggles a second one.
--
-- Only normal mode is mapped globally. In terminal mode the toggle key is
-- buffer-local to this shell terminal, so in the Claude Code terminal (also
-- a snacks terminal) Ctrl+/ still reaches Claude. Double <Esc> leaves
-- terminal mode in both, from snacks' default terminal style; a single <Esc>
-- goes to the program. snacks' global terminal options are left alone for
-- the same reason: claudecode.nvim's terminal uses them too.

local toggle_keys = { "<C-/>", "<C-_>" }

local function toggle()
  local hide = {}
  for i, lhs in ipairs(toggle_keys) do
    hide["hide_" .. i] = { lhs, "hide", mode = "t", desc = "Hide terminal" }
  end
  require("snacks").terminal.toggle(nil, { win = { keys = hide } })
end

local keys = {}
for _, lhs in ipairs(toggle_keys) do
  table.insert(keys, { lhs, toggle, mode = "n", desc = "Toggle terminal" })
end

return {
  {
    "folke/snacks.nvim",
    keys = keys,
  },
}

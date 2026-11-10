-- https://github.com/coder/claudecode.nvim
-- Claude Code IDE integration: shares the current selection and diagnostics
-- with Claude Code and shows its proposed edits as diffs in Neovim.
-- Requires the `claude` CLI on PATH.
return {
  {
    "coder/claudecode.nvim",
    dependencies = { "folke/snacks.nvim" },
    config = true,
    -- Load right after startup (not on first use) so the IDE server is
    -- already running when `/ide` is run from a separate Claude session
    event = "VeryLazy",
    keys = {
      { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Claude: Toggle terminal" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude: Focus terminal" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Claude: Resume session" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Claude: Continue last session" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Claude: Select model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude: Add current buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude: Send selection" },
      { "<leader>as", "<cmd>ClaudeCodeTreeAdd<cr>", desc = "Claude: Add file from tree", ft = { "NvimTree" } },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Claude: Accept diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Claude: Deny diff" },
    },
  },
}

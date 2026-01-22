-- Kotlin formatting plugin with ktfmt and ktlint support
-- Provides format-on-save and manual formatting for Kotlin files
return {
  {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local conform = require("conform")

      conform.setup({
        formatters_by_ft = {
          -- Try ktlint first (respects project configs), then ktfmt as fallback
          kotlin = { "ktlint", "ktfmt" },
        },
        formatters = {
          ktfmt = {
            command = "ktfmt",
            stdin = true,
          },
          ktlint = {
            command = "ktlint",
            args = { "-F", "--stdin" },
            stdin = true,
          },
        },
        format_on_save = {
          timeout_ms = 2000,
          lsp_fallback = false, -- Never use LSP as fallback - it can corrupt the file
        },
      })

      -- Manual formatting command with error handling
      vim.api.nvim_create_user_command("KotlinFormat", function()
        local result = conform.format({ async = false, lsp_fallback = false, timeout_ms = 5000 })
        if result then
          vim.notify("Formatted Kotlin file", vim.log.levels.INFO)
        else
          vim.notify("Failed to format Kotlin file - check ktlint/ktfmt is installed and file is valid", vim.log.levels.ERROR)
        end
      end, {})

      -- Keybinding for manual format (optional)
      -- vim.keymap.set('n', '<leader>gf', function()
      --   conform.format({ async = false, lsp_fallback = true })
      -- end, { noremap = true, silent = true, desc = 'Format file' })
    end,
  },
}

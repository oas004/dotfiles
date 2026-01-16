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
          kotlin = { "ktfmt" },
          -- You can add alternative formatters here
          -- kotlin = { "ktlint" },
        },
        formatters = {
          ktfmt = {
            command = "ktfmt",
            args = { "--" },
            stdin = true,
          },
          ktlint = {
            command = "ktlint",
            args = { "-F", "--stdin" },
            stdin = true,
          },
        },
        format_on_save = {
          timeout_ms = 500,
          lsp_fallback = true,
        },
      })

      -- Manual formatting command
      vim.api.nvim_create_user_command("KotlinFormat", function()
        conform.format({ async = false, lsp_fallback = true })
        vim.notify("Formatted Kotlin file", vim.log.levels.INFO)
      end, {})

      -- Keybinding for manual format (optional)
      -- vim.keymap.set('n', '<leader>gf', function()
      --   conform.format({ async = false, lsp_fallback = true })
      -- end, { noremap = true, silent = true, desc = 'Format file' })
    end,
  },
}

-- Kotlin formatting plugin with ktfmt support
return {
  {
    "stevearc/conform.nvim",
    lazy = false,  -- Load immediately to avoid race conditions
    priority = 40, -- Load after LSP
    config = function()
      local conform = require("conform")

      conform.setup({
        formatters_by_ft = {
          kotlin = { "ktfmt" },
          json = { "jq", "prettierd", "prettier", stop_after_first = true },
        },
        formatters = {
          ktfmt = {
            command = "ktfmt",
            args = { "--kotlinlang-style", "-" },
            stdin = true,
          },
        },
        format_on_save = nil,
      })

      -- Manual formatting command with error handling and validation
      vim.api.nvim_create_user_command("KotlinFormat", function()
        -- Store current content before formatting
        local original_content = vim.fn.getline(1, "$")

        local result = conform.format({ async = false, lsp_fallback = false, timeout_ms = 5000 })

        if result then
          vim.notify("Formatted Kotlin file", vim.log.levels.INFO)
        else
          -- Restore original content if format failed
          vim.cmd("%d")
          vim.fn.append(0, original_content)
          vim.notify("Failed to format Kotlin file - restored original content. Check that your Kotlin syntax is valid.", vim.log.levels.ERROR)
        end
      end, {})

      -- Keybinding for manual format (uncomment to enable)
      -- vim.keymap.set('n', '<leader>gf', function()
      --   conform.format({ async = false, lsp_fallback = false })
      -- end, { noremap = true, silent = true, desc = 'Format Kotlin file' })
    end,
  },
}

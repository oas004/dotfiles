-- Kotlin formatting plugin with ktfmt support
-- Format on save only if syntactically correct, with helpful error messages
return {
  {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local conform = require("conform")

      conform.setup({
        formatters_by_ft = {
          kotlin = { "ktfmt" },
        },
        formatters = {
          ktfmt = {
            command = "ktfmt",
            stdin = true,
          },
        },
        format_on_save = {
          timeout_ms = 5000,
          lsp_fallback = false,
        },
      })

      -- Override format_on_save with custom logic that checks syntax first
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.kt",
        callback = function(event)
          local bufnr = event.buf
          local original_content = vim.fn.getline(1, "$")

          -- Try to format
          local result = conform.format({ async = false, lsp_fallback = false, timeout_ms = 5000, bufnr = bufnr })

          if result == false then
            -- Format failed - check if it's a syntax error and provide helpful message
            local current_content = vim.fn.getline(1, "$")

            -- If content changed (corrupted), restore it
            if vim.fn.json_encode(current_content) ~= vim.fn.json_encode(original_content) then
              vim.cmd("%d")
              vim.fn.append(0, original_content)
            end

            -- Show error message without disrupting save
            vim.defer_fn(function()
              vim.notify("Kotlin syntax error detected - file not formatted. Fix syntax errors and try again.", vim.log.levels.WARN)
            end, 10)
          end
        end,
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

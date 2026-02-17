--- Java formatter plugin for Google Java Format
--- Integrates Google Java Format with nvim-none-ls for formatting

return {
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local utils = require('core.utils')

      local none_ls = utils.safe_require("none-ls", "none-ls failed to load")
      if not none_ls then return end

      local java_config = utils.safe_require("core.java-config", "Failed to load java-config")
      if not java_config then return end

      local sources = {}

      -- Google Java Format
      -- Respects project-level .google-java-format.xml or falls back to default
      table.insert(sources, none_ls.builtins.formatting.google_java_format.with({
        filetypes = { "java" },
      }))

      none_ls.setup({
        sources = sources,
      })

      -- Format on save for Java
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.java",
        callback = function()
          if none_ls.is_registered("google_java_format") then
            vim.lsp.buf.format({ async = false, timeout_ms = 5000 })
          end
        end,
      })
    end,
  },
}

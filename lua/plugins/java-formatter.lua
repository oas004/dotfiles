--- Java formatter plugin for Google Java Format
--- Integrates Google Java Format with nvim-none-ls for formatting

return {
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local ok_none_ls, none_ls = pcall(require, "none-ls")
      if not ok_none_ls then
        vim.notify("none-ls failed to load", vim.log.levels.WARN)
        return
      end

      local ok_java_config, java_config = pcall(require, "config.java-config")
      if not ok_java_config then
        vim.notify("Failed to load java-config", vim.log.levels.WARN)
        return
      end

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

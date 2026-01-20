--- Java formatter plugin for Google Java Format
--- Integrates Google Java Format with nvim-nonels for formatting

return {
  {
    "nvimtools/none-ls.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local ok_null_ls, null_ls = pcall(require, "null_ls")
      if not ok_null_ls then
        vim.notify("null_ls failed to load", vim.log.levels.WARN)
        return
      end

      local ok_java_config, java_config = pcall(require, "config.java-config")
      if not ok_java_config then
        vim.notify("Failed to load java-config", vim.log.levels.WARN)
        return
      end

      local sources = {}

      -- Google Java Format
      table.insert(sources, null_ls.builtins.formatting.google_java_format.with({
        filetypes = { "java" },
        extra_args = { "--aosp" }, -- Use Android Open Source Project formatting
      }))

      null_ls.setup({
        sources = sources,
      })

      -- Format on save for Java
      vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.java",
        callback = function()
          if null_ls.is_registered("google_java_format") then
            vim.lsp.buf.format({ async = false, timeout_ms = 5000 })
          end
        end,
      })
    end,
  },
}

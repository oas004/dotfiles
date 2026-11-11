-- User commands for LSP maintenance and inspection

-- LSP cache cleanup command
vim.api.nvim_create_user_command("CleanupLSPCache", function()
  local paths = require("core.paths")
  local cache_dirs = {
    paths.lsp_cache.kotlin_lsp,
    paths.lsp_cache.jdtls,
  }
  local failed = false
  for _, dir in ipairs(cache_dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      if vim.fn.delete(dir, "rf") == 0 then
        vim.notify("Cleaned: " .. dir, vim.log.levels.INFO)
      else
        failed = true
        vim.notify("Failed to clean: " .. dir, vim.log.levels.ERROR)
      end
    end
  end
  if failed then
    vim.notify("LSP cache cleanup finished with errors", vim.log.levels.WARN)
  else
    vim.notify("LSP cache cleanup complete. Restart Neovim.", vim.log.levels.INFO)
  end
end, { desc = "Clean LSP caches (Kotlin & Java)" })

-- Manual log cleanup command
vim.api.nvim_create_user_command("CleanupLSPLogs", function()
  local paths = require("core.paths")
  local log_files = {
    paths.logs.lsp,
    paths.logs.mason,
    paths.logs.conform,
  }
  local total_freed = 0
  for _, log_file in ipairs(log_files) do
    local stat = vim.uv.fs_stat(log_file)
    if stat then
      total_freed = total_freed + stat.size
      vim.fn.delete(log_file)
    end
  end
  if total_freed > 0 then
    vim.notify(string.format("Cleaned %.1fMB of logs", total_freed / 1024 / 1024), vim.log.levels.INFO)
  else
    vim.notify("No log files to clean", vim.log.levels.INFO)
  end
end, { desc = "Clean all LSP and plugin logs" })

-- Show active LSP clients command
vim.api.nvim_create_user_command("LspClients", function()
  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    vim.notify("No active LSP clients", vim.log.levels.INFO)
    return
  end

  local lines = { "Active LSP Clients:", "" }
  for _, client in ipairs(clients) do
    table.insert(
      lines,
      string.format("• %s (id: %d, root: %s)", client.name, client.id, client.config.root_dir or "N/A")
    )
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Show active LSP clients" })

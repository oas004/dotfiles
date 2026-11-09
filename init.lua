require("core.options")
require("core.package-manager")
require("core.keymaps")

-- LSP log management: reduce log level and auto-cleanup
vim.lsp.log.set_level("WARN") -- Only log warnings and errors (default is INFO)

-- Delete the LSP log on startup if it exceeds 50MB
do
  local paths = require('core.paths')
  local max_size = 50 * 1024 * 1024 -- 50MB in bytes

  local stat = vim.uv.fs_stat(paths.logs.lsp)
  if stat and stat.size > max_size then
    vim.fn.delete(paths.logs.lsp)
    vim.notify("LSP log was too large (" .. math.floor(stat.size / 1024 / 1024) .. "MB), deleted", vim.log.levels.INFO)
  end
end

-- LSP cache cleanup command
vim.api.nvim_create_user_command('CleanupLSPCache', function()
  local paths = require('core.paths')
  local cache_dirs = {
    paths.lsp_cache.kotlin_lsp,
    paths.lsp_cache.jdtls,
  }
  for _, dir in ipairs(cache_dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      if vim.fn.delete(dir, "rf") == 0 then
        vim.notify("Cleaned: " .. dir, vim.log.levels.INFO)
      else
        vim.notify("Failed to clean: " .. dir, vim.log.levels.ERROR)
      end
    end
  end
  vim.notify("LSP cache cleanup complete. Restart Neovim.", vim.log.levels.INFO)
end, { desc = "Clean LSP caches (Kotlin & Java)" })

-- Manual log cleanup command
vim.api.nvim_create_user_command('CleanupLSPLogs', function()
  local paths = require('core.paths')
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
vim.api.nvim_create_user_command('LspClients', function()
  local clients = vim.lsp.get_clients()
  if #clients == 0 then
    vim.notify("No active LSP clients", vim.log.levels.INFO)
    return
  end

  local lines = {"Active LSP Clients:", ""}
  for _, client in ipairs(clients) do
    table.insert(lines, string.format("• %s (id: %d, root: %s)",
      client.name,
      client.id,
      client.config.root_dir or "N/A"))
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Show active LSP clients" })

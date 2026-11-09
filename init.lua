require("core.options")
require("core.package-manager")
require("core.keymaps")
require("core.commands")

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

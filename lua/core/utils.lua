local M = {}

--- Safely require a module with error handling
--- @param module string The module name to require
--- @param error_msg string|nil Optional custom error message
--- @return table|nil The required module or nil if failed
function M.safe_require(module, error_msg)
  local ok, result = pcall(require, module)
  if not ok then
    local msg = error_msg or ("Failed to load " .. module)
    vim.notify(msg, vim.log.levels.ERROR)
    return nil
  end
  return result
end

return M

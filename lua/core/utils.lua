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

--- Execute a function safely with error handling
--- @param fn function The function to execute
--- @param error_msg string|nil Optional custom error message
--- @return boolean success Whether the function executed successfully
--- @return any result The return value of the function or error message
function M.safe_call(fn, error_msg)
  local ok, result = pcall(fn)
  if not ok then
    local msg = error_msg or "Function execution failed"
    vim.notify(msg .. ": " .. tostring(result), vim.log.levels.ERROR)
    return false, result
  end
  return true, result
end

return M

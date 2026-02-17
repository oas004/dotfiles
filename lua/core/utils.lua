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

--- Check if a file exists
--- @param path string The file path to check
--- @return boolean exists Whether the file exists
function M.file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

--- Check if a directory exists
--- @param path string The directory path to check
--- @return boolean exists Whether the directory exists
function M.dir_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

--- Get platform information
--- @return table platform Table with 'is_mac', 'is_linux', 'is_windows' fields
function M.get_platform()
  return {
    is_mac = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1,
    is_linux = vim.fn.has("unix") == 1 and vim.fn.has("mac") == 0,
    is_windows = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1,
  }
end

return M

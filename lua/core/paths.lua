--- Centralized path management for the Neovim configuration
local M = {}

local home = os.getenv("HOME") or "~"

-- Standard Neovim directories
M.config = vim.fn.stdpath("config")
M.data = vim.fn.stdpath("data")
M.cache = vim.fn.stdpath("cache")
M.state = vim.fn.stdpath("state")

-- External LSP tools (installed outside Mason)
M.external = {
  kotlin_lsp = home .. "/.local/opt/kotlin-lsp/kotlin-lsp.sh",
}

-- LSP cache directories (per-project workspaces)
M.lsp_cache = {
  kotlin_lsp = M.cache .. "/kotlin-lsp",
  jdtls = M.data .. "/jdtls",
}

-- LSP log files
M.logs = {
  lsp = M.state .. "/lsp.log",
  mason = M.state .. "/mason.log",
  conform = M.state .. "/conform.log",
}

-- Configuration preference files
M.prefs = {
  kotlin = M.config .. "/kotlin-prefs.json",
  java = M.config .. "/java-prefs.json",
}

--- Check if a file exists at the given path
--- @param path string The file path to check
--- @return boolean exists Whether the file exists
function M.file_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

--- Check if a directory exists at the given path
--- @param path string The directory path to check
--- @return boolean exists Whether the directory exists
function M.dir_exists(path)
  local stat = vim.loop.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

--- Validate that external tools exist and notify if missing
--- @return table missing List of missing tools with their paths
function M.validate_external_tools()
  local missing = {}

  for name, path in pairs(M.external) do
    if not M.file_exists(path) then
      table.insert(missing, { name = name, path = path })
    end
  end

  return missing
end

return M

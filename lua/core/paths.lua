--- Centralized path management for the Neovim configuration
local M = {}

-- Standard Neovim directories
M.config = vim.fn.stdpath("config")
M.data = vim.fn.stdpath("data")
M.cache = vim.fn.stdpath("cache")
M.state = vim.fn.stdpath("state")

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

return M

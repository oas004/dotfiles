--- Kotlin LSP and Formatter Configuration Switcher
--- Provides easy switching between different Kotlin LSP implementations and formatters
---
--- Usage:
---   :KotlinLspSwitch kotlin-lsp          -- Switch to official Kotlin LSP
---   :KotlinLspSwitch kotlin_language_server -- Switch to kotlin_language_server
---   :KotlinFormatterSwitch ktfmt         -- Switch to ktfmt formatter
---   :KotlinFormatterSwitch ktlint        -- Switch to ktlint fixer
---   :KotlinLspList                       -- Show available LSP servers
---   :KotlinFormatterList                 -- Show available formatters

local KotlinConfig = {}

--- Available Kotlin LSP servers
KotlinConfig.lsp_servers = {
  kotlin_language_server = {
    name = "kotlin_language_server",
    description = "Community Kotlin Language Server (fwcd/kotlin-language-server)",
    mason_name = "kotlin_language_server",
  },
  ["kotlin-lsp"] = {
    name = "kotlin-lsp",
    description = "Official JetBrains Kotlin LSP (pre-alpha)",
    mason_name = nil, -- Must be installed manually from releases
  },
}

--- Available Kotlin formatters
KotlinConfig.formatters = {
  ktfmt = {
    name = "ktfmt",
    description = "Google's Kotlin formatter (recommended)",
    mason_name = "ktfmt",
    command = "ktfmt",
    organize_imports = true, -- Removes unused imports
  },
  ktlint = {
    name = "ktlint",
    description = "Kotlin linter with auto-fixer",
    mason_name = "ktlint",
    command = "ktlint",
    organize_imports = false, -- ktlint doesn't remove unused imports by default
  },
}

--- Get currently active LSP server (default: kotlin_language_server)
function KotlinConfig.get_lsp_server()
  return vim.g.kotlin_lsp or "kotlin_language_server"
end

--- Get currently active formatter (default: ktfmt)
function KotlinConfig.get_formatter()
  return vim.g.kotlin_formatter or "ktfmt"
end

--- Check if a formatter removes unused imports
function KotlinConfig.formatter_removes_imports()
  local formatter = KotlinConfig.get_formatter()
  local config = KotlinConfig.formatters[formatter]
  return config and config.organize_imports or false
end

--- Get formatter command for use in nvim-nonels or other tools
function KotlinConfig.get_formatter_cmd()
  local formatter = KotlinConfig.get_formatter()
  local config = KotlinConfig.formatters[formatter]
  if not config then
    return nil
  end

  if formatter == "ktfmt" then
    return { config.command }
  elseif formatter == "ktlint" then
    return { config.command, "-F", "--stdin" } -- -F for fix mode
  end

  return nil
end

--- Get LSP server configuration
function KotlinConfig.get_lsp_config()
  local server = KotlinConfig.get_lsp_server()
  return KotlinConfig.lsp_servers[server]
end

--- Setup Kotlin commands in init.lua
function KotlinConfig.setup_commands()
  vim.api.nvim_create_user_command("KotlinLspList", function()
    local lines = { "Available Kotlin LSP servers:" }
    for name, config in pairs(KotlinConfig.lsp_servers) do
      local current = name == KotlinConfig.get_lsp_server() and " (active)" or ""
      table.insert(lines, string.format("  • %s: %s%s", name, config.description, current))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Kotlin LSP" })
  end, {})

  vim.api.nvim_create_user_command("KotlinLspSwitch", function(args)
    local server = args.args:match("%S+")
    if not server or server == "" then
      vim.notify("Usage: :KotlinLspSwitch <server>", vim.log.levels.ERROR)
      return
    end
    if not KotlinConfig.lsp_servers[server] then
      vim.notify(string.format("Unknown Kotlin LSP server: %s", server), vim.log.levels.ERROR)
      return
    end
    vim.g.kotlin_lsp = server
    vim.notify(string.format("Kotlin LSP switched to: %s\n(Restart neovim to apply changes)", server),
               vim.log.levels.INFO, { title = "Kotlin LSP" })
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("KotlinFormatterList", function()
    local lines = { "Available Kotlin formatters:" }
    for name, config in pairs(KotlinConfig.formatters) do
      local current = name == KotlinConfig.get_formatter() and " (active)" or ""
      local imports = config.organize_imports and " [removes imports]" or ""
      table.insert(lines, string.format("  • %s: %s%s%s", name, config.description, imports, current))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Kotlin Formatter" })
  end, {})

  vim.api.nvim_create_user_command("KotlinFormatterSwitch", function(args)
    local formatter = args.args:match("%S+")
    if not formatter or formatter == "" then
      vim.notify("Usage: :KotlinFormatterSwitch <formatter>", vim.log.levels.ERROR)
      return
    end
    if not KotlinConfig.formatters[formatter] then
      vim.notify(string.format("Unknown Kotlin formatter: %s", formatter), vim.log.levels.ERROR)
      return
    end
    vim.g.kotlin_formatter = formatter
    vim.notify(string.format("Kotlin formatter switched to: %s", formatter),
               vim.log.levels.INFO, { title = "Kotlin Formatter" })
  end, { nargs = 1 })
end

return KotlinConfig

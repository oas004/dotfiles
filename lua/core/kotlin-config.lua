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
  ["kotlin-lsp"] = {
    name = "kotlin-lsp",
    description = "Official JetBrains Kotlin LSP",
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

--- Get persistent storage path for Kotlin preferences
local function get_config_file()
  return vim.fn.stdpath("config") .. "/kotlin-prefs.json"
end

--- Load preferences from disk
local function load_prefs()
  local file = get_config_file()
  local f = io.open(file, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local ok, prefs = pcall(vim.json.decode, content)
    if ok then
      return prefs
    end
  end
  return {}
end

--- Save preferences to disk
local function save_prefs(prefs)
  local file = get_config_file()
  local f = io.open(file, "w")
  if f then
    f:write(vim.json.encode(prefs))
    f:close()
  end
end

--- Get currently active LSP server (default: kotlin-lsp)
function KotlinConfig.get_lsp_server()
  return "kotlin-lsp"
end

--- Get currently active formatter (default: ktfmt)
function KotlinConfig.get_formatter()
  if vim.g.kotlin_formatter then
    return vim.g.kotlin_formatter
  end
  local prefs = load_prefs()
  return prefs.formatter or "ktfmt"
end

--- Set LSP server (no-op, always kotlin-lsp)
function KotlinConfig.set_lsp_server(server)
  -- No-op: only kotlin-lsp is supported
end

--- Set formatter and persist
function KotlinConfig.set_formatter(formatter)
  vim.g.kotlin_formatter = formatter
  local prefs = load_prefs()
  prefs.formatter = formatter
  save_prefs(prefs)
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
  vim.api.nvim_create_user_command("KotlinLspDiagnostics", function()
    local clients = vim.lsp.get_active_clients({ name = "kotlin_lsp" })

    if #clients == 0 then
      vim.notify("kotlin-lsp not attached to this buffer\nCheck :LspInfo and :LspLog for details", vim.log.levels.WARN, { title = "Kotlin LSP" })
      return
    end

    local client = clients[1]
    local root_dir = client.config.root_dir
    local gradle_cmd = root_dir and string.format("cd %s && ./gradlew dependencies", root_dir) or "unknown"

    vim.notify(string.format(
      "Kotlin LSP Status:\n" ..
      "Server: kotlin-lsp (JetBrains)\n" ..
      "Root: %s\n" ..
      "\nTo sync dependencies, run:\n%s",
      root_dir or "unknown",
      gradle_cmd
    ), vim.log.levels.INFO, { title = "Kotlin LSP Diagnostics" })
  end, {})

  vim.api.nvim_create_user_command("KotlinLspKill", function()
    vim.fn.system("pkill -9 -f kotlin-lsp")
    vim.notify("Killed all kotlin-lsp processes. Restart Neovim to start fresh.", vim.log.levels.INFO, { title = "Kotlin LSP" })
  end, {})

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
    KotlinConfig.set_formatter(formatter)
    vim.notify(string.format("Kotlin formatter switched to: %s", formatter),
               vim.log.levels.INFO, { title = "Kotlin Formatter" })
  end, {
    nargs = 1,
    complete = function(ArgLead, CmdLine, CursorPos)
      local choices = {}
      for name in pairs(KotlinConfig.formatters) do
        table.insert(choices, name)
      end
      return choices
    end
  })
end

return KotlinConfig

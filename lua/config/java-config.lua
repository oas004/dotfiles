--- Java LSP and Formatter Configuration Switcher
--- Provides easy switching between different Java LSP implementations and formatters
---
--- Usage:
---   :JavaLspList                       -- Show available LSP servers
---   :JavaFormatterList                 -- Show available formatters
---   :JavaFormatterSwitch google_format -- Switch to Google Java Format

local JavaConfig = {}

--- Available Java LSP servers
JavaConfig.lsp_servers = {
  jdtls = {
    name = "jdtls",
    description = "Eclipse JDT Language Server (recommended)",
    mason_name = "jdtls",
  },
}

--- Available Java formatters
JavaConfig.formatters = {
  google_format = {
    name = "google_format",
    description = "Google Java Format",
    mason_name = "google-java-format",
    command = "google-java-format",
  },
}

--- Get persistent storage path for Java preferences
local function get_config_file()
  return vim.fn.stdpath("config") .. "/java-prefs.json"
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

--- Get currently active LSP server (default: jdtls)
function JavaConfig.get_lsp_server()
  if vim.g.java_lsp then
    return vim.g.java_lsp
  end
  local prefs = load_prefs()
  return prefs.lsp_server or "jdtls"
end

--- Get currently active formatter (default: google_format)
function JavaConfig.get_formatter()
  if vim.g.java_formatter then
    return vim.g.java_formatter
  end
  local prefs = load_prefs()
  return prefs.formatter or "google_format"
end

--- Set LSP server and persist
function JavaConfig.set_lsp_server(server)
  vim.g.java_lsp = server
  local prefs = load_prefs()
  prefs.lsp_server = server
  save_prefs(prefs)
end

--- Set formatter and persist
function JavaConfig.set_formatter(formatter)
  vim.g.java_formatter = formatter
  local prefs = load_prefs()
  prefs.formatter = formatter
  save_prefs(prefs)
end

--- Get formatter command for use in nvim-nonels or other tools
function JavaConfig.get_formatter_cmd()
  local formatter = JavaConfig.get_formatter()
  local config = JavaConfig.formatters[formatter]
  if not config then
    return nil
  end

  if formatter == "google_format" then
    return { config.command, "-" } -- Read from stdin
  end

  return nil
end

--- Get LSP server configuration
function JavaConfig.get_lsp_config()
  local server = JavaConfig.get_lsp_server()
  return JavaConfig.lsp_servers[server]
end

--- Setup Java commands in init.lua
function JavaConfig.setup_commands()
  vim.api.nvim_create_user_command("JavaLspList", function()
    local lines = { "Available Java LSP servers:" }
    for name, config in pairs(JavaConfig.lsp_servers) do
      local current = name == JavaConfig.get_lsp_server() and " (active)" or ""
      table.insert(lines, string.format("  • %s: %s%s", name, config.description, current))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Java LSP" })
  end, {})

  vim.api.nvim_create_user_command("JavaFormatterList", function()
    local lines = { "Available Java formatters:" }
    for name, config in pairs(JavaConfig.formatters) do
      local current = name == JavaConfig.get_formatter() and " (active)" or ""
      table.insert(lines, string.format("  • %s: %s%s", name, config.description, current))
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Java Formatter" })
  end, {})

  vim.api.nvim_create_user_command("JavaFormatterSwitch", function(args)
    local formatter = args.args:match("%S+")
    if not formatter or formatter == "" then
      vim.notify("Usage: :JavaFormatterSwitch <formatter>", vim.log.levels.ERROR)
      return
    end
    if not JavaConfig.formatters[formatter] then
      vim.notify(string.format("Unknown Java formatter: %s", formatter), vim.log.levels.ERROR)
      return
    end
    JavaConfig.set_formatter(formatter)
    vim.notify(string.format("Java formatter switched to: %s", formatter),
               vim.log.levels.INFO, { title = "Java Formatter" })
  end, {
    nargs = 1,
    complete = function(ArgLead, CmdLine, CursorPos)
      local choices = {}
      for name in pairs(JavaConfig.formatters) do
        table.insert(choices, name)
      end
      return choices
    end
  })

  vim.api.nvim_create_user_command("JavaFormat", function()
    local bufnr = vim.api.nvim_get_current_buf()
    local filetype = vim.bo[bufnr].filetype

    if filetype ~= "java" then
      vim.notify("JavaFormat can only be used on Java files", vim.log.levels.ERROR)
      return
    end

    vim.lsp.buf.format({ async = false, timeout_ms = 5000 })
  end, {})
end

return JavaConfig

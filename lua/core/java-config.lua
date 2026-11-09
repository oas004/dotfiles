--- Java helpers
---
--- Java formatting (google-java-format via conform.nvim, including :JavaFormat)
--- lives in lua/plugins/formatting.lua, and jdtls is configured in
--- lua/plugins/language-server.lua. The old LSP/formatter switcher commands
--- (:JavaLspList, :JavaFormatterList, :JavaFormatterSwitch) and the
--- java-prefs.json file they wrote were removed because there was only one
--- option for each.

local JavaConfig = {}

--- Kept so language-server.lua can keep calling it. There are currently no
--- Java-specific commands to register here.
function JavaConfig.setup_commands() end

return JavaConfig

-- Core config tests: user commands, core modules, deprecated API usage
-- Run with: nvim --headless -c "luafile tests/core_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local out, test, assert_true = h.out, h.test, h.assert_true

local config_dir = vim.fn.resolve(vim.fn.stdpath("config"))
local test_file = config_dir .. "/init.lua"

local function command_exists(name)
  return vim.api.nvim_get_commands({ builtin = false })[name] ~= nil
end

local function main()
  h.wait_for_lazy()

  out("\n=== Core Tests ===\n")

  -- User commands. On Neovim 0.12+ nvim-lspconfig no longer defines
  -- :LspRestart and :LspInfo; the builtin :lsp command (:lsp restart) and
  -- :checkhealth vim.lsp replace them.
  local builtin_lsp = vim.fn.exists(":lsp") == 2
  local restart_cmd = builtin_lsp and "lsp restart" or "LspRestart"
  local commands = { "LspClients", "CleanupLSPCache", "CleanupLSPLogs" }
  if not builtin_lsp then
    vim.list_extend(commands, { "LspRestart", "LspInfo" })
  end
  for _, name in ipairs(commands) do
    test(":" .. name .. " command exists", function()
      assert_true(command_exists(name), ":" .. name .. " is not defined")
    end)
  end

  -- Core modules
  test("core.utils exposes safe_require", function()
    local utils = require("core.utils")
    assert_true(type(utils.safe_require) == "function", "safe_require missing")
  end)

  -- Open a file and give LSP a chance to attach, then exercise commands
  -- that call LSP APIs so any deprecated calls get recorded.
  vim.cmd("edit " .. vim.fn.fnameescape(test_file))
  local buf = vim.api.nvim_get_current_buf()
  vim.wait(10000, function()
    return #vim.lsp.get_clients({ bufnr = buf }) > 0
  end)

  test(":LspClients runs without error", function()
    vim.cmd("LspClients")
  end)

  local clients = vim.lsp.get_clients({ bufnr = buf })
  if #clients == 0 then
    h.skip(":" .. restart_cmd .. " works on a modified buffer", "no LSP client attached to init.lua")
  else
    test(":" .. restart_cmd .. " works on a modified buffer", function()
      local old_ids = {}
      for _, c in ipairs(clients) do old_ids[c.id] = true end

      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "-- modified by core_test" })
      assert_true(vim.bo[buf].modified, "buffer should be modified")

      local start = vim.uv.now()
      vim.cmd(restart_cmd)

      -- Generous, but a restart only takes this long if the old server
      -- hangs on exit; see exit_timeout for lua_ls in language-server.lua.
      local restarted = vim.wait(30000, function()
        for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
          if not old_ids[c.id] then return true end
        end
        return false
      end, 100)
      local exited = #vim.tbl_filter(function(c) return vim.lsp.get_client_by_id(c.id) == nil end, clients)
      assert_true(restarted, string.format("no new LSP client attached %d ms after :%s (%d of %d old clients exited)",
        vim.uv.now() - start, restart_cmd, exited, #clients))
      assert_true(vim.bo[buf].modified, "buffer modifications were lost")
    end)
  end

  -- Deprecated API usage from any source: this config or a plugin. Each
  -- deprecated function is reported as a WARNING followed by its tracebacks.
  -- tests/run.sh also fails any test whose nvim shows a deprecation warning.
  test("checkhealth vim.deprecated reports nothing", function()
    vim.cmd("checkhealth vim.deprecated")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local offending = {}
    local in_warning = false
    for _, line in ipairs(lines) do
      if line:find("WARNING", 1, true) then
        in_warning = true
      elseif line:match("^%s*$") or line:match("^=+$") then
        in_warning = false
      end
      if in_warning then
        table.insert(offending, vim.trim(line))
      end
    end
    assert_true(#offending == 0, "deprecated calls:\n" .. table.concat(offending, "\n"))
  end)

  h.finish()
end

-- vim.lsp.enable only re-attaches existing buffers after VimEnter, and
-- `-c` commands run before it, so defer the tests until startup is done.
-- nested = true lets :edit fire FileType so LSP clients can attach.
local function run()
  h.run(main)
end

if vim.v.vim_did_enter == 1 then
  run()
else
  vim.api.nvim_create_autocmd("VimEnter", { once = true, nested = true, callback = run })
end

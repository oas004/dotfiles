-- Core config tests: user commands, core modules, deprecated API usage
-- Run with: nvim --headless -c "luafile tests/core_test.lua"

local failed = 0
local passed = 0

-- print() output is not newline-terminated in headless mode once startup
-- has finished, so write lines to stdout directly.
local function out(msg)
  io.stdout:write(msg .. "\n")
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    out("✓ " .. name)
    passed = passed + 1
  else
    out("✗ " .. name .. ": " .. tostring(err))
    failed = failed + 1
  end
end

local function assert_true(val, msg)
  if not val then error(msg or "expected true") end
end

local config_dir = vim.fn.resolve(vim.fn.stdpath("config"))
local test_file = config_dir .. "/init.lua"

local function command_exists(name)
  return vim.api.nvim_get_commands({ builtin = false })[name] ~= nil
end

local function main()
  -- Wait for lazy to finish loading
  vim.wait(3000, function()
    return require("lazy").stats().loaded > 0
  end)

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

  test("core.paths file_exists and dir_exists work", function()
    local paths = require("core.paths")
    assert_true(paths.file_exists(test_file), "file_exists(init.lua) returned false")
    assert_true(not paths.file_exists(config_dir), "file_exists(dir) returned true")
    assert_true(paths.dir_exists(config_dir), "dir_exists(config dir) returned false")
    assert_true(not paths.dir_exists(test_file), "dir_exists(file) returned true")
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
    out("- skipped :" .. restart_cmd .. " test (no LSP client attached to init.lua)")
  else
    test(":" .. restart_cmd .. " works on a modified buffer", function()
      local old_ids = {}
      for _, c in ipairs(clients) do old_ids[c.id] = true end

      vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "-- modified by core_test" })
      assert_true(vim.bo[buf].modified, "buffer should be modified")

      vim.cmd(restart_cmd)

      local restarted = vim.wait(15000, function()
        for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
          if not old_ids[c.id] then return true end
        end
        return false
      end, 100)
      assert_true(restarted, "no new LSP client attached after :" .. restart_cmd)
      assert_true(vim.bo[buf].modified, "buffer modifications were lost")
    end)
  end

  -- Deprecated API usage from this repo's files
  test("checkhealth vim.deprecated reports nothing from this config", function()
    vim.cmd("checkhealth vim.deprecated")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local offending = {}
    for i, line in ipairs(lines) do
      if line:find(config_dir, 1, true) then
        table.insert(offending, vim.trim(line))
        -- Include the warning that owns this traceback for context
        for j = i, 1, -1 do
          if lines[j]:find("WARNING", 1, true) then
            table.insert(offending, "  " .. vim.trim(lines[j]))
            break
          end
        end
      end
    end
    assert_true(#offending == 0, "deprecated calls from config:\n" .. table.concat(offending, "\n"))
  end)

  -- Summary
  out("\n=== Results ===")
  out(string.format("Passed: %d, Failed: %d", passed, failed))

  if failed > 0 then
    vim.cmd("cq 1") -- Exit with error code
  else
    vim.cmd("qa!")
  end
end

-- vim.lsp.enable only re-attaches existing buffers after VimEnter, and
-- `-c` commands run before it, so defer the tests until startup is done.
-- nested = true lets :edit fire FileType so LSP clients can attach.
local function run()
  local ok, err = pcall(main)
  if not ok then
    out("✗ test run aborted: " .. tostring(err))
    vim.cmd("cq 1")
  end
end

if vim.v.vim_did_enter == 1 then
  run()
else
  vim.api.nvim_create_autocmd("VimEnter", { once = true, nested = true, callback = run })
end

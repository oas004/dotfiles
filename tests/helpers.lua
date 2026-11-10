-- Shared helpers for tests/*_test.lua and tests/startup_smoke.lua.
--
-- Load it relative to the test file, so it works with
-- `nvim --headless -c "luafile tests/<file>"` from the repo root and from
-- tests/run.sh:
--
--   ---@module "tests.helpers"
--   local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
--
-- Each test file runs in its own nvim, so the pass/fail counters below are
-- per file. Output goes to stdout one line at a time ("✓ name", "✗ name: err",
-- "- name (skipped: reason)"), and finish() prints "Passed: X, Failed: Y"
-- (plus ", Skipped: Z" if anything was skipped) and exits with cq 1 or qa!.

local M = {}

local passed, failed, skipped = 0, 0, 0

--- Write a line to stdout. print() output gets joined onto one line after
--- startup or when keys are fed in headless mode, so don't use print().
---@param line string
function M.out(line)
  io.stdout:write(line .. "\n")
  io.stdout:flush()
end

--- Record a passing check.
---@param name string
function M.pass(name)
  M.out("✓ " .. name)
  passed = passed + 1
end

--- Record a failing check.
---@param name string
---@param err any
function M.fail(name, err)
  M.out("✗ " .. name .. ": " .. tostring(err))
  failed = failed + 1
end

--- Run fn as a test. It fails if fn raises an error.
---@param name string
---@param fn fun()
function M.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.pass(name)
  else
    M.fail(name, err)
  end
end

--- Record a test that was not run.
---@param name string
---@param reason string
function M.skip(name, reason)
  M.out("- " .. name .. " (skipped: " .. reason .. ")")
  skipped = skipped + 1
end

---@return integer passed, integer failed, integer skipped
function M.counts()
  return passed, failed, skipped
end

function M.assert_true(val, msg)
  if not val then
    error(msg or "expected true", 2)
  end
end

function M.assert_not_nil(val, msg)
  if val == nil then
    error(msg or "expected non-nil", 2)
  end
end

--- Tables are compared by value (vim.deep_equal), everything else with ==.
---@param actual any
---@param expected any
---@param msg? string
function M.assert_eq(actual, expected, msg)
  if not vim.deep_equal(actual, expected) then
    error(string.format("%s: expected %s, got %s", msg or "mismatch", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

--- Wait for lazy.nvim to finish loading the startup plugins.
function M.wait_for_lazy()
  vim.wait(3000, function()
    return require("lazy").stats().loaded > 0
  end)
end

--- Whether lazy.nvim has loaded the plugin.
---@param name string
---@return boolean
function M.plugin_loaded(name)
  local plugin = require("lazy.core.config").plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end

--- The mapping for lhs in mode: global, or buffer-local in buf if buf is
--- given. Keys are compared after replacing termcodes, so "<C-k>" finds the
--- "<C-K>" map.
---@param mode string
---@param lhs string
---@param buf? integer
---@return table?
function M.find_keymap(mode, lhs, buf)
  local want = vim.keycode(lhs)
  local maps = buf and vim.api.nvim_buf_get_keymap(buf, mode) or vim.api.nvim_get_keymap(mode)
  for _, m in ipairs(maps) do
    if vim.keycode(m.lhs) == want then
      return m
    end
  end
  return nil
end

--- Fail if any normal mode <leader> map is a strict prefix of another one.
--- Such a pair makes the shorter map wait for timeoutlen before it fires.
--- Covers global maps (including lazy's key handler stubs for plugins that
--- are not loaded yet) and the buffer-local maps of buf.
---@param buf integer
function M.assert_no_leader_prefix_collisions(buf)
  local leader = vim.keycode(vim.g.mapleader or "\\")
  local lhss = {}
  local maps = vim.list_extend(vim.api.nvim_get_keymap("n"), vim.api.nvim_buf_get_keymap(buf, "n"))
  for _, m in ipairs(maps) do
    local raw = vim.keycode(m.lhs)
    if raw ~= leader and raw:sub(1, #leader) == leader then
      lhss[raw] = true
    end
  end
  local collisions = {}
  for a in pairs(lhss) do
    for b in pairs(lhss) do
      if a ~= b and b:sub(1, #a) == a then
        table.insert(collisions, vim.fn.keytrans(a) .. " is a prefix of " .. vim.fn.keytrans(b))
      end
    end
  end
  table.sort(collisions)
  if #collisions > 0 then
    error(table.concat(collisions, ", "), 2)
  end
end

-- Lowercased :messages lines containing any of these count as errors, as do
-- lines with a Vim error code such as "E5108:".
M.message_patterns = {
  "error", -- E5108: Error executing lua ..., Check log for errors, ...
  "quit with exit code", -- Client rust_analyzer quit with exit code 1 and signal 0
  "exited with code", -- LSP[name]: ... exited with code
  "deprecated", -- vim.deprecate() and plugin deprecation notices
}

--- The lines of messages (default: the current :messages) that report an
--- error, an LSP client exit or a deprecation.
---@param messages? string
---@return string[]
function M.message_errors(messages)
  messages = messages or vim.fn.execute("messages")
  local found = {}
  for line in messages:gmatch("[^\n]+") do
    local lower = line:lower()
    local bad = line:find("%f[%w]E%d+:") ~= nil
    for _, pat in ipairs(M.message_patterns) do
      bad = bad or lower:find(pat, 1, true) ~= nil
    end
    if bad then
      table.insert(found, line)
    end
  end
  return found
end

--- Fail if :messages has a line that message_errors() reports.
---@param context? string added to the error, e.g. "after lua_ls stopped"
function M.assert_no_message_errors(context)
  local found = M.message_errors()
  if #found > 0 then
    error(":messages has errors" .. (context and " " .. context or "") .. ":\n  " .. table.concat(found, "\n  "), 2)
  end
end

--- Stop LSP clients the way :lsp stop does (shutdown, then exit) and wait
--- until they are gone. A forced stop sends SIGTERM, after which servers
--- exit non-zero and Neovim logs "Client <name> quit with exit code ..."
--- (clangd exits with 1, the JVM behind kotlin_lsp with 143). Neovim 0.11
--- also force-stops a client that hasn't finished initializing, so this
--- first waits up to timeout ms for that. Clients still running timeout ms
--- after the stop are terminated with rpc.terminate(), since on 0.11
--- client:stop(true) does nothing once a stop is already in progress.
--- Returns a description of each client that was not stopped gracefully.
---@param clients? vim.lsp.Client[] default: all clients, initialized or not
---@param timeout? integer default: 10000 on CI, 5000 otherwise
---@return string[]
function M.stop_clients(clients, timeout)
  -- get_clients() leaves out clients that are still initializing (kotlin_lsp
  -- takes seconds), which are the ones that get force-stopped. There is no
  -- public way to list them; the private _uninitialized filter exists on
  -- 0.11 and 0.12.
  ---@diagnostic disable-next-line: invisible
  clients = clients or vim.lsp.get_clients({ _uninitialized = true })
  timeout = timeout or (vim.env.CI and 10000 or 5000)
  local forced = {}
  local function running()
    return vim.tbl_filter(function(c)
      return vim.lsp.get_client_by_id(c.id) ~= nil
    end, clients)
  end
  vim.wait(timeout, function()
    for _, c in ipairs(running()) do
      if not c.initialized then
        return false
      end
    end
    return true
  end, 50)
  for _, c in ipairs(running()) do
    if not c.initialized then
      table.insert(forced, string.format("%s (not initialized after %d ms)", c.name, timeout))
    end
    c:stop()
  end
  if not vim.wait(timeout, function()
    return #running() == 0
  end, 50) then
    for _, c in ipairs(running()) do
      table.insert(forced, string.format("%s (still running %d ms after stop)", c.name, timeout))
      c.rpc.terminate()
    end
    vim.wait(2000, function()
      return #running() == 0
    end, 50)
  end
  return forced
end

--- stop_clients() for one client.
---@param client vim.lsp.Client
---@param timeout? integer
---@return string[]
function M.stop_client(client, timeout)
  return M.stop_clients({ client }, timeout)
end

---@class tests.FakeServerOpts
---@field capabilities? table server capabilities returned from initialize
---@field results? table<string, any> request method -> result (default vim.NIL)
---@field log? string[] every request method is appended here
---@field name? string prefix for log entries ("<name>:<method>")

--- An in-process language server for vim.lsp.start({ cmd = ... }). It answers
--- initialize with opts.capabilities and other requests from opts.results,
--- and exits cleanly on "exit" (code 0) or terminate (signal 15).
---@param opts? tests.FakeServerOpts
---@return fun(dispatchers: vim.lsp.rpc.Dispatchers): vim.lsp.rpc.PublicClient
function M.fake_lsp_server(opts)
  opts = opts or {}
  local results = opts.results or {}
  return function(dispatchers)
    local closing = false
    local id = 0
    local function exit(signal)
      if not closing then
        closing = true
        vim.schedule(function()
          dispatchers.on_exit(0, signal)
        end)
      end
    end
    return {
      request = function(method, _, callback)
        id = id + 1
        if opts.log then
          table.insert(opts.log, (opts.name and opts.name .. ":" or "") .. method)
        end
        local result = vim.NIL
        if method == "initialize" then
          result = { capabilities = opts.capabilities or {} }
        elseif results[method] ~= nil then
          result = results[method]
        end
        vim.schedule(function()
          callback(nil, result)
        end)
        return true, id
      end,
      notify = function(method)
        if method == "exit" then
          exit(0)
        end
        return true
      end,
      is_closing = function()
        return closing
      end,
      terminate = function()
        exit(15)
      end,
    }
  end
end

--- Run main, and if it raises an error, report it and exit with cq 1.
---@param main fun()
function M.run(main)
  local ok, err = pcall(main)
  if not ok then
    M.out("✗ test run aborted: " .. tostring(err))
    vim.cmd("cq 1")
  end
end

--- Print the results, stop any LSP clients gracefully (see stop_clients) and
--- exit: cq 1 if a test failed, qa! otherwise.
function M.finish()
  M.out("\n=== Results ===")
  local summary = string.format("Passed: %d, Failed: %d", passed, failed)
  if skipped > 0 then
    summary = summary .. string.format(", Skipped: %d", skipped)
  end
  M.out(summary)
  M.stop_clients()
  if failed > 0 then
    vim.cmd("cq 1")
  else
    vim.cmd("qa!")
  end
end

return M

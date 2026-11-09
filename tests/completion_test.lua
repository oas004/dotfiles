-- Completion tests: nvim-cmp with Neovim's built-in vim.snippet
-- Run with: nvim --headless -c "luafile tests/completion_test.lua"
--
-- The keypress tests run asynchronously. Keys are fed into the typeahead and
-- each check is queued behind them as a <Plug> map, so it runs only after those
-- keys (and the ones vim.snippet and cmp feed while handling them) have been
-- processed.

local failed = 0
local passed = 0

-- print() from the async steps below runs inside mappings, where headless
-- nvim drops the newline, so write to stdout directly
local function log(msg)
  io.stdout:write(msg .. "\n")
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    log("✓ " .. name)
    passed = passed + 1
  else
    log("✗ " .. name .. ": " .. tostring(err))
    failed = failed + 1
  end
end

local function assert_true(val, msg)
  if not val then error(msg or "expected true", 2) end
end

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "values differ") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b), 2) end
end

local function t(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

local function finish()
  log("\n=== Results ===")
  log(string.format("Passed: %d, Failed: %d", passed, failed))
  if failed > 0 then
    vim.cmd("cq 1")
  else
    vim.cmd("qa!")
  end
end

-- Wait for lazy to finish loading
vim.wait(3000, function()
  return require("lazy").stats().loaded > 0
end)

local cmp = require("cmp")

log("\n=== Completion Config Tests ===\n")

test("LuaSnip and cmp_luasnip are not in the plugin list", function()
  local names = vim.tbl_map(function(p) return p.name end, require("lazy").plugins())
  for _, name in ipairs({ "LuaSnip", "cmp_luasnip" }) do
    assert_true(not vim.tbl_contains(names, name), name .. " is still a plugin")
  end
end)

test("cmp sources are nvim_lsp and buffer, without luasnip", function()
  local names = vim.tbl_map(function(s) return s.name end, cmp.get_config().sources)
  assert_true(vim.tbl_contains(names, "nvim_lsp"), "nvim_lsp not in " .. vim.inspect(names))
  assert_true(vim.tbl_contains(names, "buffer"), "buffer not in " .. vim.inspect(names))
  assert_true(not vim.tbl_contains(names, "luasnip"), "luasnip still in " .. vim.inspect(names))
end)

test("cmp expands snippets with vim.snippet", function()
  local got
  local orig = vim.snippet.expand
  vim.snippet.expand = function(body) got = body end
  local ok, err = pcall(cmp.get_config().snippet.expand, { body = "x$0" })
  vim.snippet.expand = orig
  assert_true(ok, tostring(err))
  assert_eq(got, "x$0", "vim.snippet.expand body")
end)

test("<Tab> and <S-Tab> are mapped in insert and select mode", function()
  local mapping = cmp.get_config().mapping
  for _, key in ipairs({ "<Tab>", "<S-Tab>" }) do
    assert_true(mapping[key] and mapping[key].i ~= nil, key .. " not mapped in insert mode")
    assert_true(mapping[key] and mapping[key].s ~= nil, key .. " not mapped in select mode")
  end
end)

test("other cmp mappings are kept", function()
  local mapping = cmp.get_config().mapping
  for _, key in ipairs({ "<C-Space>", "<CR>", "<C-Y>", "<C-E>", "<C-U>", "<C-D>", "<Up>", "<Down>", "<C-N>", "<C-P>" }) do
    assert_true(mapping[key] ~= nil, key .. " not mapped")
  end
end)

log("\n=== Snippet Keypress Tests ===\n")

local function line()
  return vim.api.nvim_get_current_line()
end

local function mode()
  return vim.api.nvim_get_mode().mode
end

-- cmp replaces the map it finds (buffer-local or global, here Neovim's own
-- <Tab>/<S-Tab> snippet maps) and calls it as the fallback
local function has_cmp_map(m, lhs)
  local map = vim.fn.maparg(lhs, m, false, true)
  return map.desc == "cmp.utils.keymap.set_map"
end

local function expand(body)
  cmp.get_config().snippet.expand({ body = body })
end

-- Each step does something (fn, which may run actions and returns keys to
-- feed), then once those keys and anything they queued have been processed,
-- runs check. A check that returns false is retried, which is used to wait
-- for cmp's InsertEnter setup and its async menu.
local steps = {}
local function step(name, fn, check)
  table.insert(steps, { name = name, fn = fn, check = check })
end

step("cmp maps <Tab>/<S-Tab> in insert and select mode", function()
  return ""
end, function()
  if not has_cmp_map("s", "<Tab>") then return false end
  for _, m in ipairs({ "i", "s" }) do
    for _, lhs in ipairs({ "<Tab>", "<S-Tab>" }) do
      assert_true(has_cmp_map(m, lhs), m .. " " .. lhs .. " not mapped by cmp")
    end
  end
end)

step("expanding a snippet selects the first placeholder", function()
  expand("foo(${1:aaa}, ${2:bbb})")
  return ""
end, function()
  assert_true(vim.snippet.active(), "snippet not active")
  assert_eq(mode(), "s", "mode")
end)

step("typing replaces the first placeholder", function()
  return "X"
end, function()
  assert_eq(line(), "foo(X, bbb)", "line")
end)

step("<Tab> in insert mode jumps to the second placeholder", function()
  return "<Tab>"
end, function()
  assert_eq(mode(), "s", "mode")
end)

step("typing replaces the second placeholder, giving foo(X, Y)", function()
  return "Y"
end, function()
  assert_eq(line(), "foo(X, Y)", "line")
end)

step("<S-Tab> jumps back to the first placeholder", function()
  return "<S-Tab>"
end, function()
  assert_eq(mode(), "s", "mode")
  assert_eq(vim.api.nvim_win_get_cursor(0)[2], #"foo(", "cursor")
end)

step("<Tab> in select mode jumps to the second placeholder", function()
  return "<Tab>"
end, function()
  assert_eq(mode(), "s", "mode")
  assert_eq(vim.api.nvim_win_get_cursor(0)[2], #"foo(X, ", "cursor")
end)

step("typing in select mode replaces the second placeholder", function()
  return "W"
end, function()
  assert_eq(line(), "foo(X, W)", "line")
end)

step("<Tab> on the last placeholder moves to the final tabstop", function()
  return "<Tab>"
end, function()
  assert_eq(mode(), "i", "mode")
  assert_eq(vim.api.nvim_win_get_cursor(0)[2], #"foo(X, W)", "cursor")
end)

step("<Tab> with no menu and no snippet falls back to inserting indent", function()
  vim.snippet.stop()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  return "<Tab>"
end, function()
  assert_true(line():match("^%s+$") ~= nil, "line is " .. vim.inspect(line()))
end)

step("cmp menu opens on buffer words inside a snippet", function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha_one alpha_two", "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  expand("$1 end$2")
  return "alp"
end, function()
  if not cmp.visible() then
    cmp.complete()
    return false
  end
  assert_true(vim.snippet.active({ direction = 1 }), "snippet not active")
end)

step("<Tab> with the menu visible selects an item instead of jumping", function()
  return "<Tab>"
end, function()
  assert_true(cmp.visible(), "menu closed")
  assert_true(cmp.get_selected_entry() ~= nil, "no entry selected")
  assert_eq(mode(), "i", "mode")
  assert_eq(vim.api.nvim_win_get_cursor(0)[2], #"alp", "cursor")
end)

step("<C-e> closes the menu", function()
  return "<C-e>"
end, function()
  if cmp.visible() then return false end
  assert_eq(line(), "alp end", "line")
end)

step("<Tab> after closing the menu jumps", function()
  return "<Tab>"
end, function()
  assert_true(not cmp.visible(), "menu reopened")
  assert_eq(vim.api.nvim_win_get_cursor(0)[2], #"alp end", "cursor")
end)

local i = 0
local retries = 0
local SYNC = "<Plug>(completion-test-sync)"
local CHECK = "<Plug>(completion-test-check)"

-- Fed with remapping, so the <Plug> maps below fire
local function feed(keys)
  vim.api.nvim_feedkeys(t(keys), "t", false)
end

local function fail(name, err)
  log("✗ " .. name .. ": " .. tostring(err))
  failed = failed + 1
  -- Later steps depend on this one
  feed("<Esc>")
  vim.schedule(finish)
end

local function next_step()
  i = i + 1
  local s = steps[i]
  if not s then
    feed("<Esc>")
    vim.schedule(finish)
    return
  end
  local ok, keys = pcall(s.fn)
  if not ok then return fail(s.name, keys) end
  -- The sync hop queues the check behind keys that vim.snippet and cmp feed
  -- while processing these keys
  feed(keys .. SYNC)
end

local function check()
  local s = steps[i]
  local ok, res = pcall(s.check)
  if ok and res == false then
    retries = retries + 1
    if retries > 100 then return fail(s.name, "timed out waiting") end
    vim.defer_fn(function() feed(CHECK) end, 20)
    return
  end
  retries = 0
  if not ok then return fail(s.name, res) end
  log("✓ " .. s.name)
  passed = passed + 1
  next_step()
end

vim.keymap.set({ "i", "s" }, SYNC, function() feed(CHECK) end)
vim.keymap.set({ "i", "s" }, CHECK, check)

-- Safety net so a stuck key sequence fails instead of hanging
vim.defer_fn(function()
  log("✗ keypress tests timed out at step " .. i .. (steps[i] and (" (" .. steps[i].name .. ")") or ""))
  failed = failed + 1
  finish()
end, 20000)

vim.o.showmode = false
vim.cmd("enew")
vim.bo.buftype = "nofile"
feed("i")
next_step()

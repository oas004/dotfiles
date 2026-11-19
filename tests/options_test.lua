-- Editor option tests: lua/core/options.lua
-- Run with: nvim --headless -c "luafile tests/options_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

h.out("\n=== Option Tests ===\n")

-- Count matches of pattern in a scratch buffer holding lines
local function count_matches(lines, pattern)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.fn.setreg("/", pattern)
  local count = vim.fn.searchcount({ pattern = pattern, recompute = true, maxcount = 0 }).total
  vim.api.nvim_buf_delete(buf, { force = true })
  return count
end

test("lowercase search matches any case", function()
  assert_eq(count_matches({ "foo Foo FOO" }, "foo"), 3, "matches of foo")
end)

test("search with an uppercase letter is case-sensitive", function()
  assert_eq(count_matches({ "foo Foo FOO" }, "Foo"), 1, "matches of Foo")
end)

test("\\C forces a case-sensitive search", function()
  assert_eq(count_matches({ "foo Foo FOO" }, "\\Cfoo"), 1, "matches of \\Cfoo")
end)

test(":s previews off-screen matches in a split", function()
  assert_eq(vim.o.inccommand, "split", "inccommand")
end)

-- Run a split command and return the positions of the old and new window
local function split_positions(cmd)
  vim.cmd("enew")
  vim.cmd("only")
  local old = vim.api.nvim_get_current_win()
  vim.cmd(cmd)
  local new = vim.api.nvim_get_current_win()
  assert_true(new ~= old, cmd .. " did not create a window")
  local positions = { vim.api.nvim_win_get_position(old), vim.api.nvim_win_get_position(new) }
  vim.cmd("only")
  return positions[1], positions[2]
end

test(":vsplit opens to the right", function()
  local old, new = split_positions("vsplit")
  assert_true(new[2] > old[2], "new window column " .. new[2] .. " is not right of " .. old[2])
end)

test(":split opens below", function()
  local old, new = split_positions("split")
  assert_true(new[1] > old[1], "new window row " .. new[1] .. " is not below " .. old[1])
end)

test("confirm is on", function()
  assert_eq(vim.o.confirm, true, "confirm")
end)

test("tabs, trailing spaces and non-breaking spaces are shown", function()
  assert_eq(vim.o.list, true, "list")
  local listchars = vim.opt.listchars:get()
  for _, key in ipairs({ "tab", "trail", "nbsp" }) do
    assert_true(listchars[key] ~= nil and listchars[key] ~= "", "listchars has no " .. key)
  end
end)

test("breakindent is on", function()
  assert_eq(vim.o.breakindent, true, "breakindent")
end)

test("cursorline highlights only the line number", function()
  assert_eq(vim.o.cursorline, true, "cursorline")
  assert_eq(vim.o.cursorlineopt, "number", "cursorlineopt")
end)

test("lazyredraw is off", function()
  assert_eq(vim.o.lazyredraw, false, "lazyredraw")
end)

test("leader is space and localleader is backslash", function()
  assert_eq(vim.g.mapleader, " ", "mapleader")
  assert_eq(vim.g.maplocalleader, "\\", "maplocalleader")
end)

h.finish()

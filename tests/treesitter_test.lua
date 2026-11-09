-- Treesitter behaviour tests (highlighting, text objects, large-file guard)
-- Run with: nvim --headless -c "luafile tests/treesitter_test.lua"
-- Needs the lua and kotlin parsers installed (see lua/plugins/parser.lua).

local failed = 0
local passed = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("✓ " .. name)
    passed = passed + 1
  else
    print("✗ " .. name .. ": " .. tostring(err))
    failed = failed + 1
  end
end

local function assert_true(val, msg)
  if not val then error(msg or "expected true", 2) end
end

local function assert_eq(expected, actual, msg)
  if expected ~= actual then
    error(string.format("%s: expected %s, got %s", msg or "mismatch", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

-- Wait for lazy to finish loading
vim.wait(3000, function()
  return require("lazy").stats().loaded > 0
end)

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

local function write_file(name, lines)
  local path = tmpdir .. "/" .. name
  vim.fn.writefile(lines, path)
  return path
end

-- Open a file in a fresh buffer so FileType autocmds fire
local function open(path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

local function highlighting(buf)
  return vim.treesitter.highlighter.active[buf] ~= nil
end

-- Run keys with mappings applied, then return to normal mode
local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
end

-- Select with a visual-mode text object and return { start_line, end_line }
local function select_lines(textobject)
  feed("v" .. textobject .. "<Esc>")
  return { vim.fn.line("'<"), vim.fn.line("'>") }
end

local lua_src = {
  "local M = {}",               -- 1
  "",                           -- 2
  "local function add(a, b)",   -- 3
  "  local sum = a + b",        -- 4
  "  return sum",               -- 5
  "end",                        -- 6
  "",                           -- 7
  "function M.twice(x)",        -- 8
  "  return add(x, x)",         -- 9
  "end",                        -- 10
  "",                           -- 11
  "return M",                   -- 12
}

print("\n=== Treesitter Tests ===\n")

test("lua and kotlin parsers are installed", function()
  for _, lang in ipairs({ "lua", "kotlin" }) do
    assert_true(vim.treesitter.language.add(lang), lang .. " parser not available")
  end
end)

local lua_path = write_file("sample.lua", lua_src)
local kt_path = write_file("Sample.kt", {
  "class Sample {",
  "    fun greet(name: String): String {",
  "        return \"Hello, $name\"",
  "    }",
  "}",
})

test("highlighting active in lua buffer", function()
  local buf = open(lua_path)
  assert_eq("lua", vim.bo[buf].filetype, "filetype")
  assert_true(highlighting(buf), "treesitter highlighter not active for lua")
end)

test("highlighting active in kotlin buffer", function()
  local buf = open(kt_path)
  assert_eq("kotlin", vim.bo[buf].filetype, "filetype")
  assert_true(highlighting(buf), "treesitter highlighter not active for kotlin")
end)

test("af selects around function", function()
  open(lua_path)
  vim.api.nvim_win_set_cursor(0, { 4, 2 })
  local range = select_lines("af")
  assert_eq(3, range[1], "start line")
  assert_eq(6, range[2], "end line")
end)

test("if selects inside function", function()
  open(lua_path)
  vim.api.nvim_win_set_cursor(0, { 4, 2 })
  local range = select_lines("if")
  assert_eq(4, range[1], "start line")
  assert_eq(5, range[2], "end line")
end)

test("]m moves to next function start", function()
  open(lua_path)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed("]m")
  assert_eq(3, vim.fn.line("."), "first ]m")
  feed("]m")
  assert_eq(8, vim.fn.line("."), "second ]m")
end)

test("large-file guard skips highlighting over 100KB", function()
  -- Kotlin, because Neovim's own lua/help/query ftplugins start treesitter
  -- themselves, independent of this config.
  local lines = { "class Big {" }
  local line = "    val value = \"" .. string.rep("x", 80) .. "\""
  for _ = 1, 1500 do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = "}"
  local path = write_file("Big.kt", lines)
  assert_true(vim.fn.getfsize(path) > 100 * 1024, "fixture is not over 100KB")

  local buf = open(path)
  assert_eq("kotlin", vim.bo[buf].filetype, "filetype")
  assert_true(not highlighting(buf), "treesitter highlighter active for large file")
end)

vim.fn.delete(tmpdir, "rf")

-- Summary
print("\n=== Results ===")
print(string.format("Passed: %d, Failed: %d", passed, failed))

if failed > 0 then
  vim.cmd("cq 1")  -- Exit with error code
else
  vim.cmd("qa!")
end

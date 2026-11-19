-- Treesitter behaviour tests (highlighting, text objects, large-file guard)
-- Run with: nvim --headless -c "luafile tests/treesitter_test.lua"
-- Needs the parsers in lua/plugins/parser.lua installed (bootstrap.sh and
-- the CI warmup install them).

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

-- Only treesitter is under test here, so don't start language servers for
-- the files below. A kotlin_lsp started by the Kotlin buffers is still busy
-- (initializing, or indexing on a cold start on CI) when the test quits, so
-- it gets force-stopped and logs "Client kotlin_lsp quit with exit code 143",
-- and on CI it doesn't exit within 10 s of a graceful stop either.
-- gradle_ls would attach to the build.gradle files below the same way.
vim.lsp.enable({ "kotlin_lsp", "lua_ls", "gradle_ls" }, false)

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

local function write_file(name, lines)
  local path = tmpdir .. "/" .. name
  vim.fn.mkdir(vim.fs.dirname(path), "p")
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
  "local M = {}", -- 1
  "", -- 2
  "local function add(a, b)", -- 3
  "  local sum = a + b", -- 4
  "  return sum", -- 5
  "end", -- 6
  "", -- 7
  "function M.twice(x)", -- 8
  "  return add(x, x)", -- 9
  "end", -- 10
  "", -- 11
  "return M", -- 12
}

h.out("\n=== Treesitter Tests ===\n")

test("lua and kotlin parsers are installed", function()
  for _, lang in ipairs({ "lua", "kotlin" }) do
    assert_true(vim.treesitter.language.add(lang), lang .. " parser not available")
  end
end)

local lua_path = write_file("sample.lua", lua_src)
local kt_path = write_file("Sample.kt", {
  "class Sample {",
  "    fun greet(name: String): String {",
  '        return "Hello, $name"',
  "    }",
  "}",
})

test("highlighting active in lua buffer", function()
  local buf = open(lua_path)
  assert_eq(vim.bo[buf].filetype, "lua", "filetype")
  assert_true(highlighting(buf), "treesitter highlighter not active for lua")
end)

test("highlighting active in kotlin buffer", function()
  local buf = open(kt_path)
  assert_eq(vim.bo[buf].filetype, "kotlin", "filetype")
  assert_true(highlighting(buf), "treesitter highlighter not active for kotlin")
end)

test("every parser in vim.g.treesitter_parsers is installed", function()
  local missing = vim.tbl_filter(function(lang)
    return not vim.treesitter.language.add(lang)
  end, vim.g.treesitter_parsers)
  assert_eq(missing, {}, "parsers not available")
end)

-- Files this setup opens that have no parser without the Android, Gradle
-- and Git entries in lua/plugins/parser.lua: path, filetype, parser.
local file_parsers = {
  { "app/src/main/AndroidManifest.xml", { '<?xml version="1.0"?>', '<manifest package="a" />' }, "xml", "xml" },
  { "app/src/main/res/values/strings.xml", { '<resources><string name="a">A</string></resources>' }, "xml", "xml" },
  { "build.gradle", { "plugins {", "    id 'java'", "}" }, "groovy", "groovy" },
  { "settings.gradle", { "include ':app'" }, "groovy", "groovy" },
  { ".git/COMMIT_EDITMSG", { "Fix the thing", "", "# Please enter the commit message" }, "gitcommit", "gitcommit" },
  { ".git/rebase-merge/git-rebase-todo", { "pick abc1234 Fix the thing" }, "gitrebase", "git_rebase" },
  { "fix.diff", { "--- a/x", "+++ b/x", "@@ -1 +1 @@", "-a", "+b" }, "diff", "diff" },
  { "fix.patch", { "--- a/x", "+++ b/x", "@@ -1 +1 @@", "-a", "+b" }, "diff", "diff" },
}

for _, f in ipairs(file_parsers) do
  local name, lines, ft, lang = f[1], f[2], f[3], f[4]
  test(name .. " is highlighted with the " .. lang .. " parser", function()
    assert_true(vim.list_contains(vim.g.treesitter_parsers, lang), lang .. " is not in vim.g.treesitter_parsers")
    local buf = open(write_file(name, lines))
    assert_eq(vim.bo[buf].filetype, ft, "filetype")
    assert_true(highlighting(buf), "treesitter highlighter not active")
    assert_eq(assert(vim.treesitter.get_parser(buf)):lang(), lang, "parser")
  end)
end

-- Languages that are only used as injections into other languages
local injections = {
  { "regex", "pattern.js", { "const re = /a+b/;" } },
  { "html", "page.md", { "# Title", "", "<div>", "  <p>hi</p>", "</div>" } },
}

for _, inj in ipairs(injections) do
  local lang, name, lines = inj[1], inj[2], inj[3]
  test(lang .. " is injected into " .. name, function()
    assert_true(vim.list_contains(vim.g.treesitter_parsers, lang), lang .. " is not in vim.g.treesitter_parsers")
    local buf = open(write_file(name, lines))
    local parser = assert(vim.treesitter.get_parser(buf))
    parser:parse(true)
    assert_true(
      parser:children()[lang] ~= nil,
      "no " .. lang .. " injection, children: " .. vim.inspect(vim.tbl_keys(parser:children()))
    )
  end)
end

test("af selects around function", function()
  open(lua_path)
  vim.api.nvim_win_set_cursor(0, { 4, 2 })
  local range = select_lines("af")
  assert_eq(range[1], 3, "start line")
  assert_eq(range[2], 6, "end line")
end)

test("if selects inside function", function()
  open(lua_path)
  vim.api.nvim_win_set_cursor(0, { 4, 2 })
  local range = select_lines("if")
  assert_eq(range[1], 4, "start line")
  assert_eq(range[2], 5, "end line")
end)

test("]m moves to next function start", function()
  open(lua_path)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed("]m")
  assert_eq(vim.fn.line("."), 3, "first ]m")
  feed("]m")
  assert_eq(vim.fn.line("."), 8, "second ]m")
end)

test("large-file guard skips highlighting over 100KB", function()
  -- Kotlin, because Neovim's own lua/help/query ftplugins start treesitter
  -- themselves, independent of this config.
  local lines = { "class Big {" }
  local line = '    val value = "' .. string.rep("x", 80) .. '"'
  for _ = 1, 1500 do
    lines[#lines + 1] = line
  end
  lines[#lines + 1] = "}"
  local path = write_file("Big.kt", lines)
  assert_true(vim.fn.getfsize(path) > 100 * 1024, "fixture is not over 100KB")

  local buf = open(path)
  assert_eq(vim.bo[buf].filetype, "kotlin", "filetype")
  assert_true(not highlighting(buf), "treesitter highlighter active for large file")
end)

test("no LSP client started, no errors in :messages", function()
  ---@diagnostic disable-next-line: invisible
  local names = vim.tbl_map(function(c)
    return c.name
  end, vim.lsp.get_clients({ _uninitialized = true }))
  assert_eq(names, {}, "LSP clients")
  h.assert_no_message_errors()
end)

vim.fn.delete(tmpdir, "rf")

h.finish()

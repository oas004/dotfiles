-- Big file tests: snacks.bigfile (lua/plugins/parser.lua)
-- Run with: nvim --headless -c "luafile tests/bigfile_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.out("\n=== Big File Tests ===\n")

-- -c commands run before VimEnter. bigfile has to be set up by then, since
-- files given on the command line are read before VimEnter.
test("snacks.nvim is loaded at startup", function()
  assert_true(h.plugin_loaded("snacks.nvim"), "snacks.nvim not loaded before VimEnter")
end)

h.wait_for_lazy()

-- Resolved, because snacks.bigfile only checks a file when the path it is
-- given matches the buffer name, and on macOS the temp dir is under the
-- /var -> /private/var symlink, which buffer names resolve.
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")
tmpdir = assert(vim.uv.fs_realpath(tmpdir))

local kotlin_class = {
  "class Sample(val name: String) {",
  "    fun greet(other: String): String {",
  '        return "Hello, $other from $name"',
  "    }",
  "}",
  "",
}

-- A Kotlin file of at least kb kilobytes
local function write_kotlin(name, kb)
  local lines = {}
  local size = 0
  while size < kb * 1024 do
    for _, l in ipairs(kotlin_class) do
      lines[#lines + 1] = l
      size = size + #l + 1
    end
  end
  local path = tmpdir .. "/" .. name
  vim.fn.writefile(lines, path)
  return path
end

-- A fake Kotlin server, so the test can see whether one would attach
local log = {}
vim.lsp.config("bigfile_test_fake", {
  cmd = h.fake_lsp_server({ log = log }),
  filetypes = { "kotlin" },
  root_dir = function(_, on_dir)
    on_dir(tmpdir)
  end,
})
-- Only the fake server: the real kotlin_lsp would start on the small file
vim.lsp.enable({ "kotlin_lsp", "lua_ls" }, false)
vim.lsp.enable("bigfile_test_fake")

local messages = {}
local orig_notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg, level, opts)
  table.insert(messages, { msg = tostring(msg), level = level })
  return orig_notify(msg, level, opts)
end

local function open(path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

local function clients(buf)
  vim.wait(500)
  return #vim.lsp.get_clients({ bufnr = buf })
end

test("a small Kotlin file keeps its filetype, treesitter, folds and LSP", function()
  local buf = open(write_kotlin("Small.kt", 4))
  assert_eq(vim.bo[buf].filetype, "kotlin", "filetype")
  assert_true(vim.treesitter.highlighter.active[buf] ~= nil, "no treesitter highlighting")
  assert_eq(vim.wo.foldmethod, "expr", "foldmethod")
  vim.wait(2000, function()
    return clients(buf) > 0
  end)
  assert_eq(clients(buf), 1, "LSP clients")
end)

-- Larger than snacks' 1.5 MB default
local big_path = write_kotlin("Big.kt", 1600)

test("a file over 1.5 MB gets the bigfile filetype", function()
  messages = {}
  -- A global foldmethod would otherwise carry over into the big buffer
  vim.cmd("set foldmethod=indent")
  local buf = open(big_path)
  vim.cmd("setglobal foldmethod=manual")
  assert_eq(vim.bo[buf].filetype, "bigfile", "filetype")
end)

test("big file: no treesitter, syntax, folds or LSP", function()
  local buf = vim.api.nvim_get_current_buf()
  assert_true(vim.treesitter.highlighter.active[buf] == nil, "treesitter highlighting active")
  assert_eq(vim.bo[buf].syntax, "bigfile", "syntax")
  assert_eq(vim.fn.exists("b:current_syntax"), 0, "a syntax file was loaded")
  assert_eq(vim.wo.foldmethod, "manual", "foldmethod")
  assert_eq(clients(buf), 0, "LSP clients")
end)

test("big file: matchparen is cheap here and still on elsewhere", function()
  local buf = vim.api.nvim_get_current_buf()
  assert_eq(vim.b[buf].matchparen_timeout, 1, "b:matchparen_timeout")
  assert_eq(vim.b[buf].matchparen_insert_timeout, 1, "b:matchparen_insert_timeout")
  -- :NoMatchParen would have removed the autocmds for every buffer
  assert_eq(vim.fn.exists("#matchparen#CursorMoved"), 1, "matchparen CursorMoved autocmd")
end)

test("big file: a warning names the file and its real filetype", function()
  local warning
  for _, m in ipairs(messages) do
    if m.msg:find("Big file", 1, true) then
      warning = m
    end
  end
  assert_true(warning ~= nil, "no notification: " .. vim.inspect(messages))
  ---@cast warning -nil
  assert_eq(warning.level, vim.log.levels.WARN, "level")
  assert_true(warning.msg:find("Big.kt", 1, true) ~= nil, "file not named: " .. warning.msg)
  assert_true(warning.msg:find("kotlin", 1, true) ~= nil, "filetype not named: " .. warning.msg)
end)

test("a minified file with very long lines gets the bigfile filetype", function()
  local items = {}
  for i = 1, 2000 do
    items[i] = ('{"id":%d,"name":"item %d"}'):format(i, i)
  end
  local path = tmpdir .. "/bundle.min.json"
  vim.fn.writefile({ "[" .. table.concat(items, ",") .. "]" }, path)
  assert_true(vim.fn.getfsize(path) < 1.5 * 1024 * 1024, "fixture is not under 1.5 MB")
  local buf = open(path)
  assert_eq(vim.bo[buf].filetype, "bigfile", "filetype")
end)

test("a small file opened after a big one is set up normally", function()
  local buf = open(write_kotlin("After.kt", 4))
  assert_eq(vim.bo[buf].filetype, "kotlin", "filetype")
  assert_true(vim.treesitter.highlighter.active[buf] ~= nil, "no treesitter highlighting")
  assert_eq(vim.wo.foldmethod, "expr", "foldmethod")
end)

vim.notify = orig_notify
for _, c in ipairs(vim.lsp.get_clients({ name = "bigfile_test_fake" })) do
  h.stop_client(c)
end
vim.cmd("enew")
vim.fn.delete(tmpdir, "rf")

h.finish()

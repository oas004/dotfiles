-- Editor defaults: diagnostics, signcolumn, matchit/matchparen, and
-- opening a directory with nvim-tree.
-- Run with: nvim --headless -c "luafile tests/editor_test.lua"

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

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "mismatch") .. ": expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
  end
end

local function assert_true(val, msg)
  if not val then error(msg or "expected true") end
end

-- Script run inside a child nvim. It waits up to EDITOR_TEST_WAIT ms for an
-- nvim-tree window, then writes what it sees to EDITOR_TEST_OUT.
local child_script = [[
local wait_ms = tonumber(vim.env.EDITOR_TEST_WAIT)
vim.wait(wait_ms, function() return vim.bo.filetype == "NvimTree" end, 50)
local result = {
  filetype = vim.bo.filetype,
  nvim_tree_loaded = package.loaded["nvim-tree"] ~= nil,
}
local f = assert(io.open(vim.env.EDITOR_TEST_OUT, "w"))
f:write(vim.json.encode(result))
f:close()
vim.cmd("qa!")
]]

-- Starts a child nvim with the same config (NVIM_APPNAME is inherited) on
-- `path` and returns the decoded result of child_script.
local function open_in_child(path, wait_ms)
  local tmp = vim.fn.tempname()
  local script = tmp .. ".lua"
  local result_file = tmp .. ".json"
  vim.fn.writefile(vim.split(child_script, "\n"), script)
  local proc = vim.system(
    { vim.v.progpath, "--headless", path, "-c", "luafile " .. vim.fn.fnameescape(script) },
    ---@diagnostic disable-next-line: assign-type-mismatch
    { env = { EDITOR_TEST_OUT = result_file, EDITOR_TEST_WAIT = tostring(wait_ms) }, stdin = false }
  ):wait(60000)
  vim.fn.delete(script)
  if vim.fn.filereadable(result_file) == 0 then
    error("child nvim wrote no result (exit " .. tostring(proc.code) .. "): " .. (proc.stderr or ""))
  end
  local result = vim.json.decode(table.concat(vim.fn.readfile(result_file), "\n"))
  vim.fn.delete(result_file)
  return result
end

local function main()
  out("\n=== Editor Defaults Tests ===\n")

  local config = vim.diagnostic.config()
  ---@cast config -nil

  test("diagnostics: virtual_text has a prefix and spacing", function()
    assert_eq(type(config.virtual_text), "table", "virtual_text")
    assert_true(type(config.virtual_text.prefix) == "string" and config.virtual_text.prefix ~= "", "no prefix")
    assert_eq(config.virtual_text.spacing, 2, "virtual_text.spacing")
  end)

  test("diagnostics: severity_sort is on", function()
    assert_eq(config.severity_sort, true, "severity_sort")
  end)

  test("diagnostics: update_in_insert is off", function()
    assert_eq(config.update_in_insert, false, "update_in_insert")
  end)

  test("diagnostics: float has a rounded border and shows the source", function()
    assert_eq(type(config.float), "table", "float")
    assert_eq(config.float.border, "rounded", "float.border")
    assert_eq(config.float.source, true, "float.source")
  end)

  test("diagnostics: signs have text for every severity", function()
    assert_eq(type(config.signs), "table", "signs")
    local text = config.signs.text or {}
    for name, severity in pairs({ ERROR = 1, WARN = 2, INFO = 3, HINT = 4 }) do
      assert_true(type(text[severity]) == "string" and text[severity] ~= "", "no sign text for " .. name)
    end
  end)

  test("diagnostics: gl float uses the configured source", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = 1" })
    local ns = vim.api.nvim_create_namespace("editor_test")
    vim.diagnostic.set(ns, buf, {
      { lnum = 0, col = 0, message = "test error", severity = vim.diagnostic.severity.ERROR, source = "editor_test" },
    })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local keys = vim.api.nvim_replace_termcodes("gl", true, false, true)
    vim.api.nvim_feedkeys(keys, "x", false)
    local float_win
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= "" then
        float_win = win
      end
    end
    assert_true(float_win ~= nil, "gl opened no float")
    local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float_win), 0, -1, false), "\n")
    vim.api.nvim_win_close(float_win, true)
    vim.diagnostic.reset(ns, buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert_true(text:find("editor_test", 1, true) ~= nil, "float does not show the source: " .. text)
  end)

  test("signcolumn is always shown", function()
    assert_eq(vim.o.signcolumn, "yes", "signcolumn")
  end)

  test("matchparen is loaded", function()
    assert_eq(vim.g.loaded_matchparen, 1, "g:loaded_matchparen")
    assert_eq(vim.fn.exists(":DoMatchParen"), 2, ":DoMatchParen")
  end)

  test("matchit is loaded and maps %", function()
    assert_eq(vim.g.loaded_matchit, 1, "g:loaded_matchit")
    assert_true(vim.fn.maparg("%", "n"):find("Matchit", 1, true) ~= nil, "% is not mapped by matchit")
  end)

  test("nvim-tree is not loaded at startup", function()
    assert_true(package.loaded["nvim-tree"] == nil, "nvim-tree was loaded at startup")
  end)

  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/sample.txt"
  vim.fn.writefile({ "hello" }, file)

  test("nvim <dir> opens nvim-tree", function()
    local result = open_in_child(dir, 10000)
    assert_eq(result.filetype, "NvimTree", "filetype")
  end)

  test("nvim <file> does not load nvim-tree", function()
    local result = open_in_child(file, 1000)
    assert_eq(result.filetype, "text", "filetype")
    assert_eq(result.nvim_tree_loaded, false, "nvim-tree loaded")
  end)

  vim.fn.delete(dir, "rf")

  out(string.format("\nPassed: %d, Failed: %d", passed, failed))
  if failed > 0 then
    vim.cmd("cq")
  else
    vim.cmd("qa!")
  end
end

local ok, err = pcall(main)
if not ok then
  out("Test runner error: " .. tostring(err))
  vim.cmd("cq")
end

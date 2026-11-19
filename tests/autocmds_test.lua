-- Editing autocmd tests: lua/core/autocmds.lua
-- Run with: nvim --headless -c "luafile tests/autocmds_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

h.out("\n=== Autocmd Tests ===\n")

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

local function write_file(name, count)
  local lines = {}
  for i = 1, count do
    lines[i] = "line " .. i
  end
  local path = tmpdir .. "/" .. name
  vim.fn.writefile(lines, path)
  return path
end

local function open(path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

-- Leave the file at line, unload it, and open it again. :bdelete keeps the
-- '" mark (as the shada file does across sessions), but the buffer is read
-- again, so BufReadPost fires.
local function reopen_at(path, line)
  local buf = open(path)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.cmd("enew")
  vim.cmd("bdelete " .. buf)
  open(path)
  return vim.fn.line(".")
end

test("yanking highlights the yanked text", function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })
  vim.api.nvim_feedkeys("yj", "x", false)
  local ns = vim.api.nvim_get_namespaces()["nvim.hlyank"] or vim.api.nvim_get_namespaces()["hlyank"]
  assert_true(ns ~= nil, "no hlyank namespace")
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
  assert_true(#marks > 0, "no yank highlight extmark")
  vim.api.nvim_buf_delete(buf, { force = true })
end)

test("reopening a file restores the cursor line", function()
  assert_eq(reopen_at(write_file("restore.txt", 20), 15), 15, "cursor line")
end)

test("a mark past the end of the file is ignored", function()
  local path = write_file("shrunk.txt", 20)
  local buf = open(path)
  vim.api.nvim_win_set_cursor(0, { 18, 0 })
  vim.cmd("enew")
  vim.cmd("bdelete " .. buf)
  vim.fn.writefile({ "only line" }, path)
  open(path)
  assert_eq(vim.fn.line("."), 1, "cursor line")
end)

test("git commit messages start at the top", function()
  vim.fn.mkdir(tmpdir .. "/.git", "p")
  assert_eq(reopen_at(write_file(".git/COMMIT_EDITMSG", 20), 15), 1, "cursor line")
  assert_eq(vim.bo.filetype, "gitcommit", "filetype")
end)

test("loading a file in the background leaves the current window alone", function()
  -- LSP rename and references load files with bufload() without showing them
  local path = write_file("background.txt", 20)
  local buf = open(path)
  vim.api.nvim_win_set_cursor(0, { 15, 0 })
  vim.cmd("enew")
  vim.cmd("bdelete " .. buf)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b" })
  vim.fn.bufload(vim.fn.bufadd(path))
  assert_eq(vim.fn.line("."), 1, "cursor line in the current window")
  vim.cmd("bwipeout!")
end)

test("reloading a changed file does not move the cursor", function()
  local path = write_file("reload.txt", 20)
  reopen_at(path, 15)
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  vim.cmd("edit")
  assert_eq(vim.fn.line("."), 5, "cursor line after :edit")
  write_file("reload.txt", 21)
  -- Make sure the mtime differs, so :checktime sees the change
  vim.uv.fs_utime(path, os.time() + 5, os.time() + 5)
  vim.cmd("checktime")
  assert_eq(vim.api.nvim_buf_line_count(0), 21, "buffer was not reloaded")
  assert_eq(vim.fn.line("."), 5, "cursor line after :checktime")
end)

vim.cmd("enew")
vim.fn.delete(tmpdir, "rf")

h.finish()

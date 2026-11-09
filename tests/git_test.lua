-- Git integration tests (gitsigns.nvim): lazy-loading, hunk detection,
-- buffer-local keymaps and <leader> prefix collisions
-- Run with: NVIM_APPNAME=<appname> nvim --headless -c "luafile tests/git_test.lua"

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

local leader = vim.api.nvim_replace_termcodes(vim.g.mapleader or "\\", true, true, true)

local function find_buf_keymap(buf, mode, lhs)
  local want = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == want then
      return m
    end
  end
  return nil
end

--- Same check as in ui_test.lua: fail if any normal mode <leader> map
--- (global or buffer-local in buf) is a strict prefix of another one.
local function assert_no_leader_prefix_collisions(buf)
  local lhss = {}
  local maps = vim.list_extend(vim.api.nvim_get_keymap("n"), vim.api.nvim_buf_get_keymap(buf, "n"))
  for _, m in ipairs(maps) do
    local raw = vim.api.nvim_replace_termcodes(m.lhs, true, true, true)
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
  assert_true(#collisions == 0, table.concat(collisions, ", "))
end

local function plugin_loaded(name)
  local plugin = require("lazy.core.config").plugins[name]
  return plugin ~= nil and plugin._.loaded ~= nil
end

local function git(args, cwd)
  -- Ignore the user's global git config (signing, hooks, templates)
  local cmd = vim.list_extend({
    "git", "-c", "user.name=test", "-c", "user.email=test@example.com",
    "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main",
  }, args)
  local res = vim.system(cmd, { cwd = cwd, text = true, env = { GIT_CONFIG_GLOBAL = "/dev/null" } }):wait()
  assert_true(res.code == 0, table.concat(args, " ") .. " failed: " .. (res.stderr or ""))
end

-- Wait for lazy to finish loading
vim.wait(3000, function()
  return require("lazy").stats().loaded > 0
end)

print("\n=== Git Tests ===\n")

test("gitsigns is not loaded at startup without a file", function()
  assert_true(not plugin_loaded("gitsigns.nvim"), "gitsigns.nvim loaded at startup")
end)

-- Temp repo with a committed file, then edit the file on disk
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
local file = repo .. "/sample.txt"
local repo_ok = pcall(function()
  vim.fn.writefile({ "one", "two", "three", "four", "five", "six" }, file)
  git({ "init", "-q" }, repo)
  git({ "add", "sample.txt" }, repo)
  git({ "commit", "-q", "-m", "init" }, repo)
  vim.fn.writefile({ "one", "two", "three", "four", "FIVE", "six" }, file)
end)

test("temp git repo is created", function()
  assert_true(repo_ok, "could not set up the temp git repo")
end)

vim.cmd.edit(vim.fn.fnameescape(file))
local buf = vim.api.nvim_get_current_buf()

test("gitsigns loads on BufReadPre", function()
  assert_true(plugin_loaded("gitsigns.nvim"), "gitsigns.nvim not loaded after opening a file")
end)

local attached = vim.wait(10000, function()
  local hunks = package.loaded["gitsigns"] and require("gitsigns").get_hunks(buf)
  return hunks ~= nil and #hunks > 0
end, 50)

test("gitsigns attaches and detects the changed hunk", function()
  assert_true(vim.b[buf].gitsigns_status_dict ~= nil, "gitsigns did not attach")
  assert_true(attached, "no hunks detected")
  local hunks = require("gitsigns").get_hunks(buf)
  assert_true(#hunks == 1, "expected 1 hunk, got " .. #hunks)
  assert_true(hunks[1].type == "change", "expected a change hunk, got " .. tostring(hunks[1].type))
  assert_true(hunks[1].added.start == 5, "expected hunk at line 5, got " .. tostring(hunks[1].added.start))
end)

test("buffer-local git keymaps exist with descs", function()
  local expected = {
    { "n", "]c" }, { "n", "[c" },
    { "n", "<leader>hs" }, { "n", "<leader>hr" },
    { "x", "<leader>hs" }, { "x", "<leader>hr" },
    { "n", "<leader>hp" }, { "n", "<leader>hb" },
    { "o", "ih" }, { "x", "ih" },
  }
  local missing = {}
  for _, e in ipairs(expected) do
    local m = find_buf_keymap(buf, e[1], e[2])
    if not m then
      table.insert(missing, e[1] .. " " .. e[2] .. " (not mapped)")
    elseif not m.desc or m.desc == "" then
      table.insert(missing, e[1] .. " " .. e[2] .. " (no desc)")
    end
  end
  assert_true(#missing == 0, table.concat(missing, ", "))
end)

test("git keymaps are not set in buffers outside git", function()
  local scratch = vim.api.nvim_create_buf(false, true)
  assert_true(find_buf_keymap(scratch, "n", "]c") == nil, "]c mapped in a scratch buffer")
  assert_true(find_buf_keymap(scratch, "n", "<leader>hs") == nil, "<leader>hs mapped in a scratch buffer")
end)

test("]c jumps to the next hunk", function()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("]c", true, true, true), "x", false)
  local moved = vim.wait(3000, function()
    return vim.api.nvim_win_get_cursor(0)[1] == 5
  end, 20)
  assert_true(moved, "cursor on line " .. vim.api.nvim_win_get_cursor(0)[1] .. ", expected 5")
end)

test("]c and [c fall back to the built-in maps in diff mode", function()
  local gitsigns = require("gitsigns")
  local orig = gitsigns.nav_hunk
  local calls = 0
  gitsigns.nav_hunk = function() calls = calls + 1 end
  local win = vim.api.nvim_get_current_win()
  vim.cmd("vnew")
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four", "five", "six" })
  vim.cmd("diffthis")
  vim.api.nvim_set_current_win(win)
  vim.cmd("diffthis")
  local ok, err = pcall(function()
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    vim.api.nvim_feedkeys("]c", "x", false)
    assert_true(calls == 0, "gitsigns.nav_hunk called in diff mode")
    assert_true(vim.api.nvim_win_get_cursor(win)[1] == 5, "built-in ]c did not move to the diff change")
    vim.api.nvim_feedkeys("[c", "x", false)
    assert_true(calls == 0, "gitsigns.nav_hunk called in diff mode")
  end)
  gitsigns.nav_hunk = orig
  vim.cmd("diffoff!")
  vim.cmd("only")
  assert_true(ok, err)
end)

test("no <leader> map is a prefix of another (git buffer)", function()
  assert_no_leader_prefix_collisions(buf)
end)

vim.fn.delete(repo, "rf")

-- Summary
print("\n=== Results ===")
print(string.format("Passed: %d, Failed: %d", passed, failed))

if failed > 0 then
  vim.cmd("cq 1")  -- Exit with error code
else
  vim.cmd("qa!")
end

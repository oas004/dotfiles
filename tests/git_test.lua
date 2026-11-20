-- Git integration tests (gitsigns.nvim): lazy-loading, hunk detection,
-- buffer-local keymaps and <leader> prefix collisions
-- Run with: NVIM_APPNAME=<appname> nvim --headless -c "luafile tests/git_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq, plugin_loaded = h.test, h.assert_true, h.assert_eq, h.plugin_loaded

local function git(args, cwd)
  -- Ignore the user's global git config (signing, hooks, templates)
  local cmd = vim.list_extend({
    "git",
    "-c",
    "user.name=test",
    "-c",
    "user.email=test@example.com",
    "-c",
    "commit.gpgsign=false",
    "-c",
    "init.defaultBranch=main",
  }, args)
  local res = vim.system(cmd, { cwd = cwd, text = true, env = { GIT_CONFIG_GLOBAL = "/dev/null" } }):wait()
  assert_true(res.code == 0, table.concat(args, " ") .. " failed: " .. (res.stderr or ""))
end

h.wait_for_lazy()

h.out("\n=== Git Tests ===\n")

test("gitsigns is not loaded at startup without a file", function()
  assert_true(not plugin_loaded("gitsigns.nvim"), "gitsigns.nvim loaded at startup")
end)

-- Temp repo with a committed file, then edit the file on disk
local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
local file = repo .. "/sample.txt"
local repo_ok = pcall(function()
  vim.fn.writefile({ "one", "two", "three", "four", "five", "six" }, file)
  -- A second file, changed but never opened, for <leader>hq
  vim.fn.writefile({ "a", "b" }, repo .. "/other.txt")
  git({ "init", "-q" }, repo)
  git({ "add", "sample.txt", "other.txt" }, repo)
  git({ "commit", "-q", "-m", "init" }, repo)
  vim.fn.writefile({ "one", "two", "three", "four", "FIVE", "six" }, file)
  vim.fn.writefile({ "a", "B" }, repo .. "/other.txt")
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
    { "n", "]c" },
    { "n", "[c" },
    { "n", "<leader>hs" },
    { "n", "<leader>hr" },
    { "x", "<leader>hs" },
    { "x", "<leader>hr" },
    { "n", "<leader>hp" },
    { "n", "<leader>hb" },
    { "n", "<leader>hS" },
    { "n", "<leader>hR" },
    { "n", "<leader>hi" },
    { "n", "<leader>hd" },
    { "n", "<leader>hD" },
    { "n", "<leader>hq" },
    { "n", "<leader>ub" },
    { "n", "<leader>uw" },
    { "o", "ih" },
    { "x", "ih" },
  }
  local missing = {}
  for _, e in ipairs(expected) do
    local m = h.find_keymap(e[1], e[2], buf)
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
  assert_true(h.find_keymap("n", "]c", scratch) == nil, "]c mapped in a scratch buffer")
  assert_true(h.find_keymap("n", "<leader>hs", scratch) == nil, "<leader>hs mapped in a scratch buffer")
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
  gitsigns.nav_hunk = function()
    calls = calls + 1
  end
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
  h.assert_no_leader_prefix_collisions(buf)
end)

-- The tests below run the maps themselves, so they come after the ones that
-- need the unstaged hunk on line 5.

local function run_map(lhs)
  local m = h.find_keymap("n", lhs, buf)
  assert_true(m ~= nil and m.callback ~= nil, lhs .. " has no callback")
  ---@cast m -nil
  vim.api.nvim_set_current_buf(buf)
  m.callback()
end

-- Capture vim.notify messages while fn runs
local function notifications(fn)
  local msgs = {}
  local orig = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    table.insert(msgs, msg)
  end
  local ok, err = pcall(fn)
  vim.notify = orig
  assert_true(ok, err)
  return msgs
end

-- Diff window opened by diffthis, other than the file's own window
local function diff_buffer_name(lhs)
  local win = vim.api.nvim_get_current_win()
  run_map(lhs)
  local other
  vim.wait(5000, function()
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if w ~= win and vim.wo[w].diff then
        other = w
        return true
      end
    end
    return false
  end, 20)
  local name = other and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(other))
  vim.cmd("diffoff!")
  vim.api.nvim_set_current_win(win)
  vim.cmd("only")
  return name
end

test("<leader>hd diffs against the index and <leader>hD against the last commit", function()
  local index = diff_buffer_name("<leader>hd")
  assert_true(index ~= nil, "<leader>hd opened no diff window")
  local head = diff_buffer_name("<leader>hD")
  assert_true(head ~= nil, "<leader>hD opened no diff window")
  assert_true(index ~= head, "both diffs use the same base: " .. tostring(index))
  assert_true(head:find("@", 1, true) ~= nil, "<leader>hD base is not @: " .. head)
end)

test("<leader>hq lists the repo's hunks in the quickfix list", function()
  vim.fn.setqflist({}, "r")
  run_map("<leader>hq")
  -- Items for a file in the temp repo. "all" also lists the repo Neovim's
  -- cwd is in, so the other items are ignored.
  local function items(name)
    return vim.tbl_filter(function(i)
      return vim.fs.basename(vim.api.nvim_buf_get_name(i.bufnr)) == name
        and vim.fn.resolve(vim.fs.dirname(vim.api.nvim_buf_get_name(i.bufnr))) == vim.fn.resolve(repo)
    end, vim.fn.getqflist())
  end
  local found = vim.wait(5000, function()
    return #items("sample.txt") > 0 and #items("other.txt") > 0
  end, 20)
  vim.cmd("cclose")
  vim.api.nvim_set_current_buf(buf)
  assert_true(found, "quickfix list lacks sample.txt or other.txt: " .. vim.inspect(vim.fn.getqflist()))
  assert_eq(#items("sample.txt"), 1, "quickfix items for sample.txt")
  assert_eq(items("sample.txt")[1].lnum, 5, "sample.txt item line")
  assert_eq(items("other.txt")[1].lnum, 2, "other.txt item line")
end)

-- After the diff tests: gitsigns' diffthis asserts on a cache entry that
-- toggle_word_diff clears for a moment, so a diff right after the toggle fails.
test("<leader>ub and <leader>uw toggle blame and word diff and say so", function()
  local config = require("gitsigns.config").config
  for lhs, setting in pairs({ ["<leader>ub"] = "current_line_blame", ["<leader>uw"] = "word_diff" }) do
    local before = config[setting]
    local msgs = notifications(function()
      run_map(lhs)
    end)
    assert_true(config[setting] == not before, lhs .. " did not toggle " .. setting)
    assert_true(
      #msgs == 1 and msgs[1]:find(before and " off$" or " on$") ~= nil,
      lhs .. " notified " .. vim.inspect(msgs)
    )
    notifications(function()
      run_map(lhs)
    end)
    assert_true(config[setting] == before, lhs .. " did not toggle " .. setting .. " back")
  end
  -- The toggles make gitsigns recompute the hunks; wait for the hunk to be
  -- back before the tests below act on it.
  local settled = vim.wait(5000, function()
    return #(require("gitsigns").get_hunks(buf) or {}) == 1
  end, 20)
  assert_true(settled, "hunk not back after toggling")
end)

local function git_out(args)
  local res = vim.system(vim.list_extend({ "git" }, args), { cwd = repo, text = true }):wait()
  return vim.trim(res.stdout or "")
end

-- A second hunk on line 1, so the buffer maps can be told apart from the
-- hunk maps. The cursor stays on the line 5 hunk.
test("buffer has two hunks", function()
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "ONE" })
  vim.cmd("silent write")
  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  local two = vim.wait(5000, function()
    return #(require("gitsigns").get_hunks(buf) or {}) == 2
  end, 20)
  assert_true(two, "hunks: " .. vim.inspect(require("gitsigns").get_hunks(buf)))
end)

test("<leader>hS stages both hunks of the buffer", function()
  run_map("<leader>hS")
  local staged = vim.wait(5000, function()
    return git_out({ "diff", "--name-only", "--", "sample.txt" }) == ""
      and git_out({ "diff", "--cached", "--name-only" }) == "sample.txt"
  end, 50)
  assert_true(staged, "unstaged diff left: " .. git_out({ "diff", "--", "sample.txt" }))
  git({ "reset", "-q" }, repo)
end)

test("<leader>hR resets both hunks of the buffer", function()
  vim.wait(5000, function()
    return #(require("gitsigns").get_hunks(buf) or {}) == 2
  end, 20)
  run_map("<leader>hR")
  local reset = vim.wait(5000, function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return lines[1] == "one" and lines[5] == "five"
  end, 20)
  assert_true(reset, "lines: " .. vim.inspect(vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
end)

vim.fn.delete(repo, "rf")

h.finish()

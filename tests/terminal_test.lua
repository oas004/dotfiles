-- Terminal toggle tests: lua/plugins/terminal.lua
-- Run with: nvim --headless -c "luafile tests/terminal_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

h.out("\n=== Terminal Tests ===\n")

-- Run keys with mappings applied
local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
end

-- Windows showing a terminal buffer
local function terminal_wins()
  return vim.tbl_filter(function(win)
    return vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal"
  end, vim.api.nvim_list_wins())
end

local function wait_for(fn)
  vim.wait(3000, fn, 20)
  return fn()
end

vim.cmd("enew")
local editor_win = vim.api.nvim_get_current_win()

test("<C-/> and <C-_> toggle a terminal in normal mode only", function()
  for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
    local m = h.find_keymap("n", lhs)
    assert_true(m ~= nil, lhs .. " not mapped in normal mode")
    ---@cast m -nil
    assert_eq(m.desc, "Toggle terminal", lhs .. " desc")
    -- A global terminal-mode map would take Ctrl+/ from Claude Code
    assert_eq(h.find_keymap("t", lhs), nil, lhs .. " has a global terminal-mode map")
  end
end)

local term_buf

test("<C-/> opens a shell in a bottom split and focuses it", function()
  feed("<C-/>")
  assert_true(
    wait_for(function()
      return #terminal_wins() == 1
    end),
    "no terminal window"
  )
  local win = terminal_wins()[1]
  term_buf = vim.api.nvim_win_get_buf(win)
  assert_eq(vim.api.nvim_get_current_win(), win, "terminal window is not focused")
  assert_eq(vim.bo[term_buf].filetype, "snacks_terminal", "filetype")
  assert_eq(vim.api.nvim_win_get_config(win).relative, "", "terminal is a float, not a split")
  assert_true(
    vim.api.nvim_win_get_position(win)[1] > vim.api.nvim_win_get_position(editor_win)[1],
    "terminal split is not below the editor window"
  )
  assert_true(vim.fn.jobwait({ vim.bo[term_buf].channel }, 0)[1] == -1, "shell is not running")
end)

test("<C-/> in terminal mode hides the terminal and keeps the shell running", function()
  assert_true(term_buf ~= nil, "no terminal from the previous test")
  ---@cast term_buf -nil
  local m = h.find_keymap("t", "<C-/>", term_buf)
  assert_true(m ~= nil, "<C-/> has no terminal-mode map in the shell terminal")
  vim.cmd("startinsert")
  feed("<C-/>")
  assert_true(
    wait_for(function()
      return #terminal_wins() == 0
    end),
    "terminal still shown"
  )
  assert_true(vim.api.nvim_buf_is_valid(term_buf), "terminal buffer was deleted")
  assert_true(vim.fn.jobwait({ vim.bo[term_buf].channel }, 0)[1] == -1, "shell stopped when hidden")
end)

test("<C-/> again shows the same shell", function()
  vim.cmd("stopinsert")
  vim.api.nvim_set_current_win(editor_win)
  feed("<C-/>")
  assert_true(
    wait_for(function()
      return #terminal_wins() == 1
    end),
    "terminal not shown again"
  )
  assert_eq(vim.api.nvim_win_get_buf(terminal_wins()[1]), term_buf, "a new terminal was started")
  vim.api.nvim_set_current_win(editor_win)
  feed("<C-/>")
  assert_true(
    wait_for(function()
      return #terminal_wins() == 0
    end),
    "<C-/> in normal mode did not hide it"
  )
end)

test("a count opens a second shell", function()
  vim.api.nvim_set_current_win(editor_win)
  feed("2<C-/>")
  assert_true(
    wait_for(function()
      return #terminal_wins() == 1
    end),
    "no terminal for count 2"
  )
  local buf = vim.api.nvim_win_get_buf(terminal_wins()[1])
  assert_true(buf ~= term_buf, "count 2 reused the first terminal")
  vim.api.nvim_set_current_win(editor_win)
  feed("2<C-/>")
  assert_true(
    wait_for(function()
      return #terminal_wins() == 0
    end),
    "second terminal not hidden"
  )
end)

-- claudecode.nvim opens Claude through Snacks.terminal with its own cmd, the
-- way this does with cat. Ctrl+/ there must go to the program.
test("other snacks terminals keep Ctrl+/ for their program", function()
  vim.api.nvim_set_current_win(editor_win)
  local other = require("snacks").terminal.open({ "cat" })
  assert_true(
    wait_for(function()
      return vim.bo[other.buf].buftype == "terminal"
    end),
    "cat terminal did not start"
  )
  for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
    assert_eq(h.find_keymap("t", lhs, other.buf), nil, lhs .. " mapped in another snacks terminal")
  end
  -- End cat with Ctrl-D, so it exits cleanly (snacks reports a non-zero
  -- exit, which a kill would be, as an error)
  local job = vim.bo[other.buf].channel
  vim.fn.chansend(job, "\4")
  assert_eq(vim.fn.jobwait({ job }, 3000)[1], 0, "cat exit code")
end)

test("no <leader> map is a prefix of another, no errors in :messages", function()
  vim.api.nvim_set_current_win(editor_win)
  h.assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
  h.assert_no_message_errors()
end)

-- Stop the shells, so the test exits without waiting on them
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buf].buftype == "terminal" then
    pcall(vim.fn.jobstop, vim.bo[buf].channel)
  end
end

h.finish()

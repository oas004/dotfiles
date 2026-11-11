-- Tests for AI agent integration (auto-reload, code reference keymap, claudecode.nvim)
-- Run with: NVIM_APPNAME=<appname> nvim --headless -c "luafile tests/ai_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local out, test, assert_true, assert_eq = h.out, h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

out("\n=== AI Integration Tests ===\n")

-- Auto-reload ---------------------------------------------------------------

test("autoread is enabled", function()
  assert_true(vim.o.autoread, "autoread is off")
end)

test("checktime autocmds exist", function()
  for _, event in ipairs({ "FocusGained", "BufEnter", "CursorHold", "TermLeave", "TermClose" }) do
    local cmds = vim.api.nvim_get_autocmds({ group = "AutoReloadChangedFiles", event = event })
    assert_true(#cmds > 0, "no autocmd for " .. event)
  end
end)

test("FileChangedShellPost notification autocmd exists", function()
  local cmds = vim.api.nvim_get_autocmds({ group = "AutoReloadChangedFiles", event = "FileChangedShellPost" })
  assert_true(#cmds > 0, "no FileChangedShellPost autocmd")
end)

test("each reload event runs :checktime", function()
  -- Neovim postpones the actual reload of a :checktime triggered from an
  -- autocmd until it is idle waiting for input, which never happens inside
  -- this script, so spy on the command instead of waiting for the reload.
  local calls = 0
  rawset(vim.cmd, "checktime", function()
    calls = calls + 1
  end)
  local ok, err = pcall(function()
    for _, event in ipairs({ "FocusGained", "BufEnter", "CursorHold", "TermLeave", "TermClose" }) do
      local before = calls
      vim.api.nvim_exec_autocmds(event, { group = "AutoReloadChangedFiles" })
      assert_true(calls == before + 1, event .. " did not run :checktime")
    end
  end)
  rawset(vim.cmd, "checktime", nil)
  if not ok then
    error(err, 0)
  end
end)

-- Code reference keymap -----------------------------------------------------

-- Use an in-memory clipboard provider so the tests work headless (and on CI
-- without pbcopy/xclip) and never overwrite the real system clipboard.
local fake_clipboard = { ["+"] = { { "" }, "v" }, ["*"] = { { "" }, "v" } }
vim.g.clipboard = {
  name = "ai_test",
  copy = {
    ["+"] = function(l, t)
      fake_clipboard["+"] = { l, t }
    end,
    ["*"] = function(l, t)
      fake_clipboard["*"] = { l, t }
    end,
  },
  paste = {
    ["+"] = function()
      return fake_clipboard["+"]
    end,
    ["*"] = function()
      return fake_clipboard["*"]
    end,
  },
}
vim.g.loaded_clipboard_provider = nil
vim.cmd("runtime autoload/provider/clipboard.vim")

local ref_reg = "+"
local saved_cwd = vim.fn.getcwd()
local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir .. "/sub", "p")
local lines = {}
for i = 1, 10 do
  lines[i] = "line " .. i
end
vim.fn.writefile(lines, tmpdir .. "/sub/file.lua")
vim.cmd("cd " .. vim.fn.fnameescape(tmpdir))
vim.cmd("edit sub/file.lua")

-- Capture notifications instead of printing them
local notifications = {}
local real_notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg)
  table.insert(notifications, msg)
end

test("clipboard (+ register) is available", function()
  assert_true(vim.fn.has("clipboard") == 1, "no clipboard provider")
end)

test("<leader>yr is mapped in normal and visual mode", function()
  assert_true(vim.fn.maparg("<leader>yr", "n") ~= "", "normal mapping missing")
  assert_true(vim.fn.maparg("<leader>yr", "x") ~= "", "visual mapping missing")
end)

test("<leader>yr has no prefix conflict with other leader maps", function()
  local key = vim.fn.keytrans(vim.keycode("<leader>yr"))
  for _, m in ipairs(vim.fn.maplist()) do
    local relevant = m.mode == " " or m.mode:find("[nvx]")
    if relevant and m.buffer == 0 and m.lhs ~= key and (vim.startswith(key, m.lhs) or vim.startswith(m.lhs, key)) then
      error("prefix conflict: " .. m.lhs .. " in mode '" .. m.mode .. "'")
    end
  end
end)

test("normal mode copies path:LINE", function()
  vim.fn.setreg(ref_reg, "")
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  vim.fn.maparg("<leader>yr", "n", false, true).callback()
  assert_eq(vim.fn.getreg(ref_reg), "sub/file.lua:4")
  assert_eq(fake_clipboard["+"][1][1], "sub/file.lua:4", "not sent to clipboard provider")
  assert_eq(notifications[#notifications], "Copied sub/file.lua:4", "no notification")
end)

test("visual mode copies path:START-END", function()
  vim.fn.setreg(ref_reg, "")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.keycode("3GVjj<leader>yr"), "mx", false)
  assert_eq(vim.fn.getreg(ref_reg), "sub/file.lua:3-5")
  assert_eq(vim.fn.mode(), "n", "visual mode not exited")
end)

test("visual mode selected upwards copies ordered range", function()
  vim.fn.setreg(ref_reg, "")
  vim.api.nvim_feedkeys(vim.keycode("8Gvkk<leader>yr"), "mx", false)
  assert_eq(vim.fn.getreg(ref_reg), "sub/file.lua:6-8")
end)

test("falls back to git root when file is outside the cwd", function()
  vim.fn.mkdir(tmpdir .. "/.git", "p")
  local elsewhere = vim.fn.tempname()
  vim.fn.mkdir(elsewhere, "p")
  vim.cmd("cd " .. vim.fn.fnameescape(elsewhere))
  vim.fn.setreg(ref_reg, "")
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.fn.maparg("<leader>yr", "n", false, true).callback()
  assert_eq(vim.fn.getreg(ref_reg), "sub/file.lua:2")
end)

test("buffer without a file name warns instead of copying", function()
  vim.cmd("enew")
  vim.fn.setreg(ref_reg, "unchanged")
  vim.fn.maparg("<leader>yr", "n", false, true).callback()
  assert_eq(vim.fn.getreg(ref_reg), "unchanged")
  assert_eq(notifications[#notifications], "Buffer has no file name")
  vim.cmd("bwipeout!")
end)

vim.notify = real_notify
vim.cmd("bwipeout!")
vim.cmd("cd " .. vim.fn.fnameescape(saved_cwd))
vim.fn.delete(tmpdir, "rf")

-- claudecode.nvim -----------------------------------------------------------

local claude_commands = {
  "ClaudeCode",
  "ClaudeCodeFocus",
  "ClaudeCodeSelectModel",
  "ClaudeCodeAdd",
  "ClaudeCodeSend",
  "ClaudeCodeTreeAdd",
  "ClaudeCodeStatus",
  "ClaudeCodeStart",
  "ClaudeCodeStop",
  "ClaudeCodeOpen",
  "ClaudeCodeClose",
  "ClaudeCodeDiffAccept",
  "ClaudeCodeDiffDeny",
  "ClaudeCodeCloseAllDiffs",
}

test("claudecode.nvim loads on VeryLazy (server up without a keypress)", function()
  local plugin = require("lazy.core.config").plugins["claudecode.nvim"]
  assert_true(plugin ~= nil, "claudecode.nvim spec missing")
  local events = type(plugin.event) == "table" and plugin.event or { plugin.event }
  assert_true(
    vim.tbl_contains(events, "VeryLazy"),
    "claudecode.nvim not loaded on VeryLazy: " .. vim.inspect(plugin.event)
  )
end)

test("claudecode.nvim loads and registers its commands", function()
  require("lazy").load({ plugins = { "claudecode.nvim" } })
  assert_true(require("claudecode") ~= nil, "claudecode module missing")
  local cmds = vim.api.nvim_get_commands({})
  for _, name in ipairs(claude_commands) do
    assert_true(cmds[name] ~= nil, "missing command " .. name)
  end
end)

test("snacks terminal provider is available", function()
  assert_true(require("claudecode.terminal.snacks").is_available(), "snacks terminal not available")
end)

test("<leader>a* keymaps exist", function()
  for _, lhs in ipairs({
    "<leader>ac",
    "<leader>af",
    "<leader>ar",
    "<leader>aC",
    "<leader>am",
    "<leader>ab",
    "<leader>aa",
    "<leader>ad",
  }) do
    assert_true(vim.fn.maparg(lhs, "n") ~= "", "missing " .. lhs)
  end
  assert_true(vim.fn.maparg("<leader>as", "v") ~= "", "missing visual <leader>as")
end)

-- Stop the websocket server started by setup so no stale lock file is left
local notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function() end
pcall(vim.api.nvim_command, "ClaudeCodeStop")
vim.notify = notify

h.finish()

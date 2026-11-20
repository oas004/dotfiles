-- Session tests: lua/plugins/sessions.lua (persistence.nvim)
-- Run with: nvim --headless -c "luafile tests/sessions_test.lua"
--
-- Saving and restoring run in child nvims with their own XDG_STATE_HOME, so
-- the sessions they write never touch the real state dir.

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

h.out("\n=== Session Tests ===\n")

local tmp = vim.fn.resolve(vim.fn.tempname())
local project = tmp .. "/project"
local state = tmp .. "/state"
vim.fn.mkdir(project, "p")
vim.fn.mkdir(state, "p")
vim.fn.writefile({ "alpha" }, project .. "/a.txt")
vim.fn.writefile({ "beta" }, project .. "/b.txt")

-- Run a Lua script in a child nvim started in the project dir. The script
-- can write a JSON result to SESSIONS_TEST_OUT, which is returned decoded.
local function child(script)
  local file = tmp .. "/child.lua"
  local result_file = tmp .. "/result.json"
  vim.fn.delete(result_file)
  vim.fn.writefile(vim.split(script, "\n"), file)
  local proc = vim
    .system({ vim.v.progpath, "--headless", "-c", "luafile " .. vim.fn.fnameescape(file) }, {
      cwd = project,
      ---@diagnostic disable-next-line: assign-type-mismatch
      env = { XDG_STATE_HOME = state, SESSIONS_TEST_OUT = result_file },
    })
    :wait(60000)
  if vim.fn.filereadable(result_file) == 0 then
    return nil, "exit " .. tostring(proc.code) .. ": " .. (proc.stderr or "")
  end
  return vim.json.decode(table.concat(vim.fn.readfile(result_file), "\n"))
end

local function session_files()
  return vim.fn.glob(state .. "/*/sessions/*.vim", true, true)
end

-- Opens two files in a vsplit plus nvim-tree, a terminal split and a
-- trouble list, then quits, which saves the session.
local save_script = [[
vim.cmd("edit a.txt")
-- Headless nvims don't save sessions (checked below), so start saving the
-- way it starts with a UI attached
require("persistence").start()
vim.cmd("vsplit b.txt")
local file_buf = vim.api.nvim_get_current_buf()
require("nvim-tree.api").tree.open()
vim.cmd("botright split | terminal")
local ns = vim.api.nvim_create_namespace("sessions_test")
vim.diagnostic.set(ns, file_buf, { { lnum = 0, col = 0, message = "x", severity = 1 } })
vim.api.nvim_set_current_win(vim.fn.bufwinid(file_buf))
vim.cmd("Trouble diagnostics open")
vim.wait(3000, function()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "trouble" then
      return true
    end
  end
end, 20)
local fts = {}
for _, win in ipairs(vim.api.nvim_list_wins()) do
  table.insert(fts, vim.bo[vim.api.nvim_win_get_buf(win)].filetype)
end
local f = assert(io.open(vim.env.SESSIONS_TEST_OUT, "w"))
f:write(vim.json.encode({ fts = fts, active = require("persistence").active() }))
f:close()
vim.cmd("qa!")
]]

-- Restores the session for the project dir and reports the windows and
-- any errors.
local restore_script = [[
vim.cmd("messages clear")
require("persistence").load()
local wins = {}
for _, win in ipairs(vim.api.nvim_list_wins()) do
  local buf = vim.api.nvim_win_get_buf(win)
  table.insert(wins, {
    name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t"),
    buftype = vim.bo[buf].buftype,
  })
end
local f = assert(io.open(vim.env.SESSIONS_TEST_OUT, "w"))
f:write(vim.json.encode({ wins = wins, messages = vim.fn.execute("messages") }))
f:close()
vim.cmd("qa!")
]]

test("persistence is not loaded at startup", function()
  assert_true(not h.plugin_loaded("persistence.nvim"), "persistence.nvim loaded before a file was read")
end)

test("session keys exist with descs", function()
  for _, lhs in ipairs({ "<leader>ws", "<leader>wl", "<leader>wS", "<leader>wd" }) do
    local m = h.find_keymap("n", lhs)
    assert_true(m ~= nil and m.desc ~= nil and m.desc ~= "", lhs .. " not mapped with a desc")
  end
end)

-- The buffers picker deletes a buffer with a buffer-local <leader>q, which
-- would wait for timeoutlen if a global <leader>q... map existed
test("no global map starts with <leader>q", function()
  local prefix = vim.keycode("<leader>q")
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    assert_true(vim.keycode(m.lhs):sub(1, #prefix) ~= prefix, m.lhs .. " is mapped globally")
  end
end)

test("sessions leave out terminals and empty windows", function()
  local opts = vim.opt.sessionoptions:get()
  for _, unwanted in ipairs({ "terminal", "blank" }) do
    assert_true(not vim.tbl_contains(opts, unwanted), "sessionoptions has " .. unwanted)
  end
  for _, wanted in ipairs({ "buffers", "curdir", "tabpages", "winsize" }) do
    assert_true(vim.tbl_contains(opts, wanted), "sessionoptions lacks " .. wanted)
  end
end)

local saved, save_err = child(save_script)

test("quitting saves a session with the open files only", function()
  assert_true(saved ~= nil, "save child failed: " .. tostring(save_err))
  ---@cast saved -nil
  assert_true(saved.active, "persistence was not active after a file was opened")
  -- The terminal is checked through term:// in the session file below
  for _, ft in ipairs({ "NvimTree", "trouble" }) do
    assert_true(vim.tbl_contains(saved.fts, ft), ft .. " window was not open before saving: " .. vim.inspect(saved.fts))
  end
  local files = session_files()
  assert_eq(#files, 1, "session files")
  local text = table.concat(vim.fn.readfile(files[1]), "\n")
  assert_true(text:find("a.txt", 1, true) ~= nil, "a.txt not in the session")
  assert_true(text:find("b.txt", 1, true) ~= nil, "b.txt not in the session")
  for _, unwanted in ipairs({ "NvimTree_", "term://", "Trouble", "trouble" }) do
    assert_true(text:find(unwanted, 1, true) == nil, unwanted .. " is in the session")
  end
end)

local restored, restore_err = child(restore_script)

test("restoring brings back both files and nothing else", function()
  assert_true(restored ~= nil, "restore child failed: " .. tostring(restore_err))
  ---@cast restored -nil
  local names = vim.tbl_map(function(w)
    return w.name
  end, restored.wins)
  table.sort(names)
  assert_eq(names, { "a.txt", "b.txt" }, "restored windows")
  for _, w in ipairs(restored.wins) do
    assert_eq(w.buftype, "", w.name .. " buftype")
  end
  assert_true(not restored.messages:find("E%d+:"), "errors while restoring: " .. restored.messages)
end)

test("headless nvims don't save sessions", function()
  vim.cmd("silent edit " .. vim.fn.fnameescape(project .. "/a.txt"))
  vim.wait(2000, function()
    return h.plugin_loaded("persistence.nvim")
  end, 20)
  assert_true(h.plugin_loaded("persistence.nvim"), "persistence.nvim not loaded after reading a file")
  assert_true(not require("persistence").active(), "saving is on in a headless nvim")
  assert_true(not pcall(vim.api.nvim_get_autocmds, { group = "persistence" }), "save autocmd in a headless nvim")
end)

test("<leader>wd stops saving", function()
  require("persistence").start()
  h.find_keymap("n", "<leader>wd").callback()
  assert_true(not require("persistence").active(), "still saving after <leader>wd")
  -- stop() deletes the group holding the VimLeavePre save autocmd
  assert_true(
    not pcall(vim.api.nvim_get_autocmds, { event = "VimLeavePre", group = "persistence" }),
    "VimLeavePre save autocmd left"
  )
end)

test("no <leader> map is a prefix of another, no errors in :messages", function()
  h.assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
  h.assert_no_message_errors()
end)

vim.fn.delete(tmp, "rf")

h.finish()

-- Tests for which-key.nvim: lazy-loading, leader group names, :checkhealth
-- Run with: NVIM_APPNAME=<appname> nvim --headless -c "luafile tests/which_key_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local out, test, assert_true = h.out, h.test, h.assert_true

local function plugin()
  return require("lazy.core.config").plugins["which-key.nvim"]
end

--- which-key's tree node for lhs in mode (default normal) for the current
--- buffer, rebuilt from the current keymaps.
local function wk_node(lhs, mode)
  local m = require("which-key.buf").get({ mode = mode or "n", update = true })
  assert_true(m ~= nil, "which-key has no tree for the current buffer")
  return m.tree.root:find(require("which-key.util").keys(lhs, { norm = true }))
end

out("\n=== which-key Tests ===\n")

-- -c commands run before VimEnter, so VeryLazy has not fired yet here
test("which-key is not loaded at startup", function()
  assert_true(plugin() ~= nil, "which-key.nvim spec missing")
  assert_true(plugin()._.loaded == nil, "which-key.nvim loaded before VeryLazy")
  assert_true(package.loaded["which-key"] == nil, "which-key module required at startup")
end)

test("which-key is lazy-loaded on VeryLazy", function()
  local events = plugin().event
  events = type(events) == "table" and events or { events }
  assert_true(vim.tbl_contains(events, "VeryLazy"), "event is " .. vim.inspect(plugin().event))
end)

local function main()
  test("which-key is still not loaded after VimEnter", function()
    assert_true(plugin()._.loaded == nil, "which-key.nvim loaded before VeryLazy")
  end)

  test("which-key loads on VeryLazy without a keypress", function()
    -- lazy fires VeryLazy after UIEnter, which headless Neovim never gets,
    -- so pretend a UI attached.
    vim.api.nvim_exec_autocmds("UIEnter", {})
    vim.wait(5000, function() return plugin()._.loaded ~= nil end)
    assert_true(plugin()._.loaded ~= nil, "which-key.nvim not loaded after VeryLazy")
    -- setup itself is scheduled by which-key
    vim.wait(2000, function() return require("which-key.config").loaded end)
    assert_true(require("which-key.config").loaded, "which-key setup did not finish")
  end)

  vim.cmd("edit README.md")

  -- Same buffer-local map as LspAttach in plugins/language-server.lua
  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = 0, desc = "LSP: Code actions" })

  local groups = {
    ["<leader>a"] = "ai (Claude)",
    ["<leader>c"] = "code",
    ["<leader>n"] = "new",
    ["<leader>y"] = "yank",
  }
  for lhs, name in pairs(groups) do
    test(lhs .. " is shown as the " .. name .. " group", function()
      local node = wk_node(lhs)
      assert_true(node ~= nil, lhs .. " not in which-key's tree")
      assert_true(node:is_group(), lhs .. " is not a group")
      assert_true(node.desc == name, "desc is " .. tostring(node.desc))
    end)
  end

  test("<leader>c group holds code action and format", function()
    local node = wk_node("<leader>c")
    assert_true(node:find("a") and node:find("a").keymap, "<leader>ca missing from the group")
    assert_true(node:find("f") and node:find("f").keymap, "<leader>cf missing from the group")
  end)

  test("visual mode groups for <leader>a and <leader>y", function()
    for lhs, name in pairs({ ["<leader>a"] = "ai (Claude)", ["<leader>y"] = "yank" }) do
      local node = wk_node(lhs, "x")
      assert_true(node and node:is_group() and node.desc == name, lhs .. " group missing in visual mode")
    end
  end)

  -- README.md is tracked in this repo, so gitsigns attaches to it
  test("<leader>h is the git hunks group where gitsigns is attached", function()
    vim.wait(5000, function() return vim.fn.maparg("<leader>hs", "n") ~= "" end)
    assert_true(vim.fn.maparg("<leader>hs", "n") ~= "", "gitsigns did not attach to README.md")
    for _, mode in ipairs({ "n", "x" }) do
      local node = wk_node("<leader>h", mode)
      assert_true(node and node:is_group() and node.desc == "git hunks", "<leader>h group missing in mode " .. mode)
    end
  end)

  test("<leader>h group is hidden where nothing is mapped under it", function()
    vim.cmd("enew")
    assert_true(vim.fn.maparg("<leader>hs", "n") == "", "<leader>hs mapped in a scratch buffer")
    assert_true(wk_node("<leader>h") == nil, "empty <leader>h group is shown")
    vim.cmd("buffer README.md")
  end)

  test("<leader>? opens which-key for buffer-local maps", function()
    local m = vim.fn.maparg("<leader>?", "n", false, true)
    assert_true(m.callback ~= nil, "<leader>? not mapped")
    assert_true(m.desc == "Buffer-local keymaps (which-key)", "desc is " .. tostring(m.desc))
  end)

  test("no <leader> map is a prefix of another with which-key loaded", function()
    h.assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
  end)

  test("no errors in :messages after loading which-key", function()
    h.assert_no_message_errors()
  end)

  -- which-key's health check warns about overlapping keymaps (a map that is
  -- a prefix of another) and about mappings defined twice. Builtins and other
  -- plugins have overlaps outside <leader> (gc/gcc, nvim-surround's ys/yss),
  -- so only errors and <leader> overlaps fail the test.
  test(":checkhealth which-key has no errors or <leader> overlaps/duplicates", function()
    vim.cmd("checkhealth which-key")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    vim.cmd("tabclose")
    local text = table.concat(lines, "\n")
    assert_true(text:find("No issues reported", 1, true), "mapping issues reported:\n" .. text)
    assert_true(text:find("No duplicate mappings found", 1, true), "duplicates reported:\n" .. text)
    local leader_key = require("which-key.util").norm("<leader>")
    for _, line in ipairs(lines) do
      assert_true(not line:find("ERROR"), line)
      if line:find("overlaps with", 1, true) then
        assert_true(not line:find("<" .. leader_key, 1, true), line)
      end
    end
  end)

  -- VeryLazy also started claudecode.nvim's websocket server; stop it so no
  -- stale lock file is left (as in tests/ai_test.lua)
  local notify = vim.notify
  vim.notify = function() end
  pcall(vim.api.nvim_command, "ClaudeCodeStop")
  vim.notify = notify

  h.finish()
end

local function run()
  h.run(main)
end

if vim.v.vim_did_enter == 1 then
  run()
else
  vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = vim.schedule_wrap(run) })
end

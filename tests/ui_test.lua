-- Editor/UI tests: statusline, colorscheme, diagnostic keymaps, leader map
-- prefixes, file explorer, telescope config
-- Run with: nvim --headless -c "luafile tests/ui_test.lua"

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
  if not val then error(msg or "expected true") end
end

local function assert_not_nil(val, msg)
  if val == nil then error(msg or "expected non-nil") end
end

local function find_keymap(mode, lhs)
  local want = vim.api.nvim_replace_termcodes(lhs, true, true, true)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == want then
      return m
    end
  end
  return nil
end

local leader = vim.api.nvim_replace_termcodes(vim.g.mapleader or "\\", true, true, true)

--- Fail if any normal mode <leader> map is a strict prefix of another one.
--- Such a pair makes the shorter map wait for timeoutlen before it fires.
--- Covers global maps (including lazy's key handler stubs for plugins that
--- are not loaded yet) and the buffer-local maps of buf.
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

-- Wait for lazy to finish loading
vim.wait(3000, function()
  return require("lazy").stats().loaded > 0
end)

print("\n=== UI Tests ===\n")

-- Checked before anything below loads telescope
test("telescope-fzf-native is not loaded at startup", function()
  assert_true(not plugin_loaded("telescope.nvim"), "telescope loaded at startup")
  assert_true(not plugin_loaded("telescope-fzf-native.nvim"), "telescope-fzf-native loaded at startup")
end)

test("no <leader> map is a prefix of another (before lazy-loading)", function()
  assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
end)

-- Colorscheme overrides
test("nordic highlight overrides survive :colorscheme", function()
  local function comment_fg()
    return vim.api.nvim_get_hl(0, { name = "Comment" }).fg
  end
  assert_true(vim.g.colors_name == "nordic", "colorscheme is " .. tostring(vim.g.colors_name))
  assert_true(comment_fg() == 0xb8cde6, "Comment override not applied at startup")
  vim.cmd.colorscheme("default")
  vim.cmd.colorscheme("nordic")
  assert_true(comment_fg() == 0xb8cde6, "Comment override lost after :colorscheme nordic")
  assert_true(vim.api.nvim_get_hl(0, { name = "Search" }).bold == true, "Search override lost")
end)

-- Open a real file so BufReadPre fires and lazy loads event-triggered plugins
vim.cmd("edit README.md")
vim.wait(2000, function()
  return package.loaded["lualine"] ~= nil
end)

-- Lualine
test("lualine is loaded after opening a file", function()
  assert_not_nil(package.loaded["lualine"], "lualine was not required (setup never ran)")
end)

test("statusline is set by lualine", function()
  local sl = vim.o.statusline
  assert_true(sl ~= nil and sl ~= "", "statusline is empty")
  assert_true(sl:find("lualine", 1, true) ~= nil, "statusline not driven by lualine: " .. sl)
end)

test("lualine uses the nordic theme", function()
  local cfg = require("lualine").get_config()
  assert_true(cfg.options.theme == "nordic", "theme is " .. vim.inspect(cfg.options.theme))
end)

-- Diagnostic keymaps
test("<leader>e (next diagnostic) keymap exists", function()
  local m = find_keymap("n", "<leader>e")
  assert_not_nil(m, "<leader>e not mapped")
  assert_true(m.desc == "Next diagnostic", "unexpected desc: " .. tostring(m.desc))
end)

test("<leader>E (prev diagnostic) keymap exists", function()
  local m = find_keymap("n", "<leader>E")
  assert_not_nil(m, "<leader>E not mapped")
  assert_true(m.desc == "Prev diagnostic", "unexpected desc: " .. tostring(m.desc))
end)

test("diagnostic keymaps jump without errors", function()
  local buf = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace("ui_test")
  vim.diagnostic.set(ns, buf, {
    { lnum = 2, col = 0, message = "first", severity = vim.diagnostic.severity.WARN },
    { lnum = 5, col = 0, message = "second", severity = vim.diagnostic.severity.WARN },
  })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  find_keymap("n", "<leader>e").callback()
  assert_true(vim.api.nvim_win_get_cursor(0)[1] == 3, "next did not move to line 3")
  find_keymap("n", "<leader>E").callback()
  -- Already on the first diagnostic, so prev wraps to the last one
  assert_true(vim.api.nvim_win_get_cursor(0)[1] == 6, "prev did not wrap to line 6")
  vim.diagnostic.reset(ns, buf)
  -- Close any float opened by jump({ float = true })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      vim.api.nvim_win_close(win, true)
    end
  end
end)

-- File explorer
test("<leader>l toggles and <leader>L finds the current file in nvim-tree", function()
  local l = find_keymap("n", "<leader>l")
  assert_not_nil(l, "<leader>l not mapped")
  assert_true(l.desc == "nvim-tree: Toggle", "unexpected <leader>l desc: " .. tostring(l.desc))
  local L = find_keymap("n", "<leader>L")
  assert_not_nil(L, "<leader>L not mapped")
  assert_true(L.desc == "nvim-tree: Find current file", "unexpected <leader>L desc: " .. tostring(L.desc))
  assert_true(find_keymap("n", "<leader>lf") == nil, "<leader>lf still mapped (collides with <leader>l)")
end)

test("<leader>L opens nvim-tree on the current file", function()
  local file = vim.api.nvim_buf_get_name(0)
  require("lazy").load({ plugins = { "nvim-tree.lua" } })
  local L = find_keymap("n", "<leader>L")
  assert_not_nil(L and L.callback, "<leader>L has no callback after nvim-tree loaded")
  L.callback()
  vim.wait(500, function() return vim.bo.filetype == "NvimTree" end)
  assert_true(vim.bo.filetype == "NvimTree", "nvim-tree did not open and focus")
  local node = require("nvim-tree.api").tree.get_node_under_cursor()
  assert_true(node and node.absolute_path == file, "cursor not on current file: " .. tostring(node and node.absolute_path))
  -- Buffer-local maps in the tree (e.g. lazy ft keys) must not collide either
  assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
  require("nvim-tree.api").tree.close()
end)

-- Telescope
require("lazy").load({ plugins = { "telescope.nvim" } })

test("telescope-fzf-native loads with telescope", function()
  assert_true(plugin_loaded("telescope-fzf-native.nvim"), "telescope-fzf-native not loaded")
end)

test("no <leader> map is a prefix of another (after lazy-loading)", function()
  assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
end)

test("telescope ignore patterns keep .github and .gitignore", function()
  local patterns = require("telescope.config").values.file_ignore_patterns
  assert_not_nil(patterns, "file_ignore_patterns not set")
  local function ignored(path)
    for _, p in ipairs(patterns) do
      if path:find(p) then return true end
    end
    return false
  end
  assert_true(not ignored(".github/workflows/x.yml"), ".github/workflows/x.yml is ignored")
  assert_true(not ignored(".gitignore"), ".gitignore is ignored")
  assert_true(ignored(".git/config"), ".git/config is not ignored")
  assert_true(ignored("sub/.git/HEAD"), "sub/.git/HEAD is not ignored")
  assert_true(ignored("node_modules/foo/index.js"), "node_modules is not ignored")
end)

test("buffers picker does not map <Leader>q in insert mode", function()
  local mappings = require("telescope.config").pickers.buffers.mappings
  assert_true(mappings.i == nil or mappings.i["<Leader>q"] == nil, "<Leader>q still mapped in insert mode")
  assert_true(mappings.n["<Leader>q"] == "delete_buffer", "<Leader>q missing in normal mode")
end)

test("fzf-native extension is loaded", function()
  assert_not_nil(require("telescope").extensions.fzf, "fzf extension not loaded")
end)

test("find_files picker opens and closes", function()
  require("telescope.builtin").find_files()
  vim.wait(500)
  local prompt = vim.api.nvim_get_current_buf()
  assert_true(vim.bo[prompt].filetype == "TelescopePrompt", "picker did not open")
  require("telescope.actions").close(prompt)
end)

-- Summary
print("\n=== Results ===")
print(string.format("Passed: %d, Failed: %d", passed, failed))

if failed > 0 then
  vim.cmd("cq 1")  -- Exit with error code
else
  vim.cmd("qa!")
end

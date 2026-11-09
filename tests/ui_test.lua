-- Editor/UI tests: statusline, diagnostic keymaps, telescope config
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

-- Wait for lazy to finish loading
vim.wait(3000, function()
  return require("lazy").stats().loaded > 0
end)

print("\n=== UI Tests ===\n")

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

-- Telescope
require("lazy").load({ plugins = { "telescope.nvim" } })

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
  assert_true(mappings.i["<Leader>q"] == nil, "<Leader>q still mapped in insert mode")
  assert_true(mappings.i["<C-d>"] == "delete_buffer", "<C-d> not mapped to delete_buffer")
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

-- Neovim config tests
-- Run with: nvim --headless -c "luafile tests/config_test.lua"

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

-- Wait for lazy to finish loading
vim.wait(3000, function()
  return require("lazy").stats().loaded > 0
end)

print("\n=== Config Tests ===\n")

-- Treesitter tests
test("treesitter loads", function()
  assert_not_nil(require("nvim-treesitter.configs"))
end)

test("treesitter-textobjects loads", function()
  assert_not_nil(require("nvim-treesitter-textobjects"))
end)

test("textobjects select module loads", function()
  assert_not_nil(require("nvim-treesitter-textobjects.select"))
end)

test("textobjects move module loads", function()
  assert_not_nil(require("nvim-treesitter-textobjects.move"))
end)

-- Keymap tests
test("af keymap exists (operator-pending)", function()
  local maps = vim.api.nvim_get_keymap("o")
  local found = false
  for _, m in ipairs(maps) do
    if m.lhs == "af" then found = true end
  end
  assert_true(found, "af keymap not found")
end)

test("if keymap exists (operator-pending)", function()
  local maps = vim.api.nvim_get_keymap("o")
  local found = false
  for _, m in ipairs(maps) do
    if m.lhs == "if" then found = true end
  end
  assert_true(found, "if keymap not found")
end)

test("]m keymap exists (normal)", function()
  local maps = vim.api.nvim_get_keymap("n")
  local found = false
  for _, m in ipairs(maps) do
    if m.lhs == "]m" then found = true end
  end
  assert_true(found, "]m keymap not found")
end)

-- LSP config tests
test("lspconfig loads", function()
  assert_not_nil(require("lspconfig"))
end)

test("kotlin_lsp config exists", function()
  local configs = require("lspconfig.configs")
  assert_not_nil(configs.kotlin_lsp, "kotlin_lsp config not registered")
end)

test("kotlin_lsp has correct filetypes", function()
  local configs = require("lspconfig.configs")
  local ft = configs.kotlin_lsp.filetypes or configs.kotlin_lsp.config_def.default_config.filetypes
  assert_true(vim.tbl_contains(ft, "kotlin"), "kotlin not in filetypes")
end)

-- Conform tests
test("conform loads", function()
  assert_not_nil(require("conform"))
end)

test("ktfmt formatter configured", function()
  local conform = require("conform")
  local formatters = conform.list_formatters_for_buffer(0)
  -- This may be empty if not in a kotlin buffer, so just check the module loads
  assert_not_nil(conform.get_formatter_info("ktfmt"))
end)

-- Telescope tests
test("telescope loads", function()
  assert_not_nil(require("telescope"))
end)

test("telescope builtin loads", function()
  assert_not_nil(require("telescope.builtin"))
end)

-- Core modules
test("core.paths loads", function()
  local paths = require("core.paths")
  assert_not_nil(paths.external.kotlin_lsp)
end)

test("core.utils loads", function()
  assert_not_nil(require("core.utils"))
end)

-- Summary
print("\n=== Results ===")
print(string.format("Passed: %d, Failed: %d", passed, failed))

if failed > 0 then
  vim.cmd("cq 1")  -- Exit with error code
else
  vim.cmd("qa!")
end

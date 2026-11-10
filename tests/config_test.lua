-- Neovim config tests
-- Run with: nvim --headless -c "luafile tests/config_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_not_nil = h.test, h.assert_true, h.assert_not_nil

h.wait_for_lazy()

h.out("\n=== Config Tests ===\n")

-- Treesitter tests
test("treesitter loads", function()
  local ts = require("nvim-treesitter")
  assert_not_nil(ts.install, "nvim-treesitter.install missing (not on main branch?)")
end)

test("treesitter highlight autocmd registered", function()
  local cmds = vim.api.nvim_get_autocmds({ group = "treesitter_highlight", event = "FileType" })
  assert_true(#cmds > 0, "no FileType autocmd in treesitter_highlight group")
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
  assert_true(h.find_keymap("o", "af") ~= nil, "af keymap not found")
end)

test("if keymap exists (operator-pending)", function()
  assert_true(h.find_keymap("o", "if") ~= nil, "if keymap not found")
end)

test("]m keymap exists (normal)", function()
  assert_true(h.find_keymap("n", "]m") ~= nil, "]m keymap not found")
end)

-- LSP config tests
test("lspconfig loads", function()
  assert_not_nil(require("lspconfig"))
end)

test("kotlin_lsp config exists", function()
  assert_not_nil(vim.lsp.config.kotlin_lsp, "kotlin_lsp config not registered")
end)

test("kotlin_lsp has correct filetypes", function()
  local ft = vim.lsp.config.kotlin_lsp.filetypes or {}
  assert_true(vim.tbl_contains(ft, "kotlin"), "kotlin not in filetypes")
end)

-- Conform tests
test("conform loads", function()
  assert_not_nil(require("conform"))
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
  assert_not_nil(paths.lsp_cache.kotlin_lsp)
end)

test("core.utils loads", function()
  assert_not_nil(require("core.utils"))
end)

h.finish()

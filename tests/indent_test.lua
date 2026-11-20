-- Indent guide tests: snacks.indent (lua/plugins/theming.lua)
-- Run with: nvim --headless -c "luafile tests/indent_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

h.out("\n=== Indent Guide Tests ===\n")

local function snacks()
  return require("snacks")
end

-- Not the language servers: this is only about drawing
vim.lsp.enable({ "lua_ls" }, false)

local lines = {
  "local function f(x)", -- 1
  "  if x then", -- 2
  "    return 1", -- 3
  "  end", -- 4
  "end", -- 5
}

-- What is drawn at buffer line lnum, byte column col of the current window
local function cell(lnum, col)
  vim.cmd("redraw!")
  local pos = vim.fn.screenpos(0, lnum, col)
  return vim.fn.screenstring(pos.row, pos.col)
end

local function has_guides()
  -- Line 3 has guides for both indent levels, at columns 1 and 3
  return cell(3, 1) == "│" and cell(3, 3) == "│"
end

-- Show lines in a new buffer, set up with fn(buf) before it is drawn
local function show(fn)
  vim.cmd("enew")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  if fn then
    fn(buf)
  end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return buf
end

-- -c commands run before VimEnter, so this is before VeryLazy too
test("snacks is loaded at startup", function()
  assert_true(h.plugin_loaded("snacks.nvim"), "snacks.nvim not loaded")
end)

test("the first file read shows indent guides", function()
  local path = vim.fn.tempname() .. ".lua"
  vim.fn.writefile(lines, path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  assert_true(snacks().indent.enabled, "indent guides not enabled after the first file was read")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  assert_true(has_guides(), ("guides: [%s] [%s]"):format(cell(3, 1), cell(3, 3)))
  vim.cmd("bwipeout!")
  vim.fn.delete(path)
end)

test("nofile and help buffers show no indent guides", function()
  -- nvim-tree, lazy and Mason use nofile buffers
  for _, buftype in ipairs({ "nofile", "help" }) do
    show(function(buf)
      vim.bo[buf].buftype = buftype
    end)
    assert_true(not has_guides(), buftype .. " buffer shows guides")
    vim.cmd("bwipeout!")
  end
end)

test("the terminal (Claude Code) shows no indent guides", function()
  local filter = assert(snacks().config.indent.filter, "no indent filter")
  vim.cmd("terminal")
  local buf = vim.api.nvim_get_current_buf()
  assert_eq(vim.bo[buf].buftype, "terminal", "buftype")
  assert_true(not filter(buf, vim.api.nvim_get_current_win()), "filter allows the terminal")
  vim.cmd("bwipeout!")
end)

test("files flagged by snacks.bigfile show no indent guides", function()
  show(function(buf)
    vim.bo[buf].filetype = "bigfile"
  end)
  assert_true(not has_guides(), "bigfile buffer shows guides")
  vim.cmd("bwipeout!")
end)

test("<leader>ui turns the guides off and on", function()
  local m = h.find_keymap("n", "<leader>ui")
  assert_true(m ~= nil and m.callback ~= nil, "<leader>ui not mapped")
  ---@cast m -nil
  assert_eq(m.desc, "Toggle indent guides", "desc")
  show()
  assert_true(has_guides(), "no guides before the toggle")
  m.callback()
  assert_true(not snacks().indent.enabled, "still enabled")
  assert_true(not has_guides(), "guides still drawn after <leader>ui")
  m.callback()
  assert_true(snacks().indent.enabled, "not enabled again")
  assert_true(has_guides(), "guides not drawn after a second <leader>ui")
  vim.cmd("bwipeout!")
end)

test("guide colors come from the nordic overrides and survive :colorscheme", function()
  local function fg(name)
    return vim.api.nvim_get_hl(0, { name = name, link = false }).fg
  end
  assert_eq(fg("SnacksIndent"), 0x434C5E, "SnacksIndent fg")
  assert_eq(fg("SnacksIndentScope"), 0x60728A, "SnacksIndentScope fg")
  vim.cmd.colorscheme("default")
  vim.cmd.colorscheme("nordic")
  assert_eq(fg("SnacksIndent"), 0x434C5E, "SnacksIndent fg after :colorscheme nordic")
  assert_eq(fg("SnacksIndentScope"), 0x60728A, "SnacksIndentScope fg after :colorscheme nordic")
end)

h.finish()

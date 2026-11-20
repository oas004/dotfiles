-- trouble.nvim tests: lazy-loading, <leader>x maps, ]q/[q, diagnostics view
-- Run with: nvim --headless -c "luafile tests/lists_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

h.out("\n=== Lists (trouble.nvim) Tests ===\n")

local maps = {
  ["<leader>xx"] = "Diagnostics (workspace)",
  ["<leader>xX"] = "Diagnostics (buffer)",
  ["<leader>xs"] = "Symbols (buffer)",
  ["<leader>xr"] = "LSP definitions, references, implementations",
  ["<leader>xq"] = "Quickfix list",
  ["<leader>xl"] = "Location list",
}

local function trouble_wins()
  return vim.tbl_filter(function(win)
    return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "trouble"
  end, vim.api.nvim_list_wins())
end

local function press(lhs)
  vim.api.nvim_feedkeys(vim.keycode(lhs), "mx", false)
end

-- Scratch buffer with numbered lines, and a quickfix list with an entry on
-- lines 2, 4 and 6
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".txt")
local lines = {}
for i = 1, 8 do
  lines[i] = "line " .. i
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
vim.fn.setqflist(vim.tbl_map(function(lnum)
  return { bufnr = buf, lnum = lnum, col = 1, text = "item " .. lnum }
end, { 2, 4, 6 }))

test("trouble is not loaded at startup", function()
  assert_true(not h.plugin_loaded("trouble.nvim"), "trouble.nvim loaded at startup")
end)

test("<leader>x maps exist with descs", function()
  for lhs, desc in pairs(maps) do
    local m = h.find_keymap("n", lhs)
    assert_true(m ~= nil, lhs .. " not mapped")
    ---@cast m -nil
    assert_eq(m.desc, desc, lhs .. " desc")
  end
end)

test("]q and [q are the built-in :cnext/:cprevious without trouble", function()
  vim.cmd("cfirst")
  assert_eq(vim.fn.line("."), 2, "line after :cfirst")
  press("]q")
  assert_eq(vim.fn.line("."), 4, "line after ]q")
  vim.cmd("cfirst")
  press("2]q")
  assert_eq(vim.fn.line("."), 6, "line after 2]q from the first item")
  press("[q")
  assert_eq(vim.fn.line("."), 4, "line after [q")
  assert_true(not h.plugin_loaded("trouble.nvim"), "]q/[q loaded trouble.nvim")
end)

test("<leader>xX lists the buffer's diagnostics", function()
  vim.api.nvim_set_current_buf(buf)
  local ns = vim.api.nvim_create_namespace("lists_test")
  vim.diagnostic.set(ns, buf, {
    { lnum = 2, col = 0, message = "first problem", severity = vim.diagnostic.severity.ERROR },
    { lnum = 6, col = 0, message = "second problem", severity = vim.diagnostic.severity.WARN },
  })
  -- Another buffer's diagnostic, which the buffer view must leave out
  local other = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(other, vim.fn.tempname() .. ".txt")
  vim.api.nvim_buf_set_lines(other, 0, -1, false, { "other" })
  vim.diagnostic.set(ns, other, {
    { lnum = 0, col = 0, message = "elsewhere problem", severity = vim.diagnostic.severity.ERROR },
  })
  vim.cmd("messages clear")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local source_win = vim.api.nvim_get_current_win()
  press("<leader>xX")
  vim.wait(3000, function()
    return #trouble_wins() > 0
  end, 20)
  assert_true(h.plugin_loaded("trouble.nvim"), "trouble.nvim not loaded by <leader>xX")
  assert_eq(#trouble_wins(), 1, "trouble windows")
  local tbuf = vim.api.nvim_win_get_buf(trouble_wins()[1])
  vim.wait(3000, function()
    return table.concat(vim.api.nvim_buf_get_lines(tbuf, 0, -1, false), "\n"):find("second problem", 1, true) ~= nil
  end, 20)
  local text = table.concat(vim.api.nvim_buf_get_lines(tbuf, 0, -1, false), "\n")
  assert_true(text:find("first problem", 1, true) ~= nil, "first diagnostic not listed:\n" .. text)
  assert_true(text:find("second problem", 1, true) ~= nil, "second diagnostic not listed:\n" .. text)
  assert_true(text:find("elsewhere problem", 1, true) == nil, "other buffer's diagnostic listed:\n" .. text)

  -- With trouble open, ]q jumps through its items in the source window
  vim.api.nvim_set_current_win(source_win)
  press("]q")
  vim.wait(1000, function()
    return vim.fn.line(".") == 3
  end, 20)
  assert_eq({ vim.api.nvim_get_current_win(), vim.fn.line(".") }, { source_win, 3 }, "window and line after ]q")
  press("]q")
  vim.wait(1000, function()
    return vim.fn.line(".") == 7
  end, 20)
  assert_eq(vim.fn.line("."), 7, "line after the second ]q")
  h.assert_no_message_errors("after opening trouble")
  vim.diagnostic.reset(ns)
  vim.api.nvim_buf_delete(other, { force = true })
end)

test("pressing <leader>xX again closes the list", function()
  press("<leader>xX")
  vim.wait(2000, function()
    return #trouble_wins() == 0
  end, 20)
  assert_eq(#trouble_wins(), 0, "trouble windows")
end)

test("<leader>xq lists the quickfix list", function()
  press("<leader>xq")
  vim.wait(3000, function()
    local wins = trouble_wins()
    return #wins > 0
      and table
          .concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false), "\n")
          :find("item 6", 1, true)
        ~= nil
  end, 20)
  local wins = trouble_wins()
  assert_eq(#wins, 1, "trouble windows")
  local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(wins[1]), 0, -1, false), "\n")
  for _, item in ipairs({ "item 2", "item 4", "item 6" }) do
    assert_true(text:find(item, 1, true) ~= nil, item .. " not listed:\n" .. text)
  end
  press("<leader>xq")
  vim.wait(2000, function()
    return #trouble_wins() == 0
  end, 20)
end)

test("no <leader> map is a prefix of another", function()
  h.assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
end)

vim.api.nvim_buf_delete(buf, { force = true })
h.finish()

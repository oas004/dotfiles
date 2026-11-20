-- Completion tests: blink.cmp with Neovim's built-in vim.snippet
-- Run with: nvim --headless -c "luafile tests/completion_test.lua"
--
-- The keypress tests run asynchronously. Keys are fed into the typeahead and
-- each check is queued behind them as a <Plug> map, so it runs only after those
-- keys (and the ones vim.snippet and blink feed while handling them) have been
-- processed.

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local log, test, assert_true, assert_eq = h.out, h.test, h.assert_true, h.assert_eq

local function t(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

h.wait_for_lazy()

log("\n=== Completion Config Tests ===\n")

local cmp = require("blink.cmp")
local config = require("blink.cmp.config")

-- Language servers attach before the first InsertEnter and need blink's
-- capabilities, so it is not lazy-loaded (see lsp_test for the capabilities)
test("blink.cmp is loaded at startup", function()
  assert_true(h.plugin_loaded("blink.cmp"), "blink.cmp not loaded at startup")
end)

test("nvim-cmp, its sources and LuaSnip are not in the plugin list", function()
  local names = vim.tbl_map(function(p)
    return p.name
  end, require("lazy").plugins())
  for _, name in ipairs({ "nvim-cmp", "cmp-buffer", "cmp-nvim-lsp", "LuaSnip", "cmp_luasnip" }) do
    assert_true(not vim.tbl_contains(names, name), name .. " is still a plugin")
  end
end)

test("sources are lsp, path, snippets and buffer", function()
  assert_eq(config.sources.default, { "lsp", "path", "snippets", "buffer" }, "sources.default")
end)

test("friendly-snippets is installed for the snippets source", function()
  local plugin = require("lazy.core.config").plugins["friendly-snippets"]
  assert_true(plugin ~= nil, "friendly-snippets is not a plugin")
  assert_true(vim.fn.isdirectory(plugin.dir .. "/snippets") == 1, "no snippets dir in " .. plugin.dir)
end)

test("snippets expand with vim.snippet", function()
  assert_eq(config.snippets.preset, "default", "snippets.preset")
  local got
  local orig = vim.snippet.expand
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.snippet.expand = function(body)
    got = body
  end
  local ok, err = pcall(config.snippets.expand, "x$0")
  vim.snippet.expand = orig
  assert_true(ok, tostring(err))
  assert_eq(got, "x$0", "vim.snippet.expand body")
end)

-- blink wraps options that can differ per mode (insert, cmdline, terminal)
-- in a function, so call it to get the insert mode value
local function insert_mode_value(opt)
  if type(opt) == "function" then
    return opt({}, {})
  end
  return opt
end

test("nothing is selected or inserted until you move into the menu", function()
  local selection = config.completion.list.selection
  assert_eq(insert_mode_value(selection.preselect), false, "preselect")
  assert_eq(insert_mode_value(selection.auto_insert), false, "auto_insert")
end)

test("blink's signature help is off, <C-k> and <C-s> are left alone", function()
  assert_eq(config.signature.enabled, false, "signature.enabled")
  assert_true(config.keymap["<C-k>"] == nil, "<C-k> in blink's keymap")
  assert_true(config.keymap["<C-s>"] == nil, "<C-s> in blink's keymap")
end)

test("command-line completion is on, with blink's maps on : and /", function()
  assert_eq(config.cmdline.enabled, true, "cmdline.enabled")
  -- Set once blink's async setup (after the fuzzy matcher check) is done
  vim.wait(5000, function()
    return vim.startswith(vim.fn.maparg("<Tab>", "c", false, true).desc or "", "blink.cmp: ")
  end, 50)
  for _, lhs in ipairs({ "<Tab>", "<S-Tab>", "<C-y>", "<C-e>" }) do
    local m = vim.fn.maparg(lhs, "c", false, true)
    assert_true(
      vim.startswith(m.desc or "", "blink.cmp: "),
      "cmdline " .. lhs .. " not mapped by blink: " .. tostring(m.desc)
    )
  end
end)

test("every key from the nvim-cmp setup is mapped", function()
  for _, key in ipairs({
    "<C-Space>",
    "<Tab>",
    "<S-Tab>",
    "<CR>",
    "<C-y>",
    "<C-e>",
    "<Up>",
    "<Down>",
    "<C-p>",
    "<C-n>",
    "<C-u>",
    "<C-d>",
  }) do
    assert_true(type(config.keymap[key]) == "table" and #config.keymap[key] > 0, key .. " not mapped")
  end
  assert_eq(config.keymap.preset, "none", "keymap preset")
end)

test("the menu shows the source of each item", function()
  local columns = insert_mode_value(config.completion.menu.draw.columns)
  local found = false
  for _, column in ipairs(columns) do
    found = found or vim.tbl_contains(column, "source_name")
  end
  assert_true(found, "no source_name column in " .. vim.inspect(columns))
  local text = config.completion.menu.draw.components.source_name.text
  ---@diagnostic disable-next-line: missing-fields
  assert_eq(text({ source_name = "LSP" }), "[LSP]", "source_name text")
end)

-- The prebuilt matcher is fetched by the spec's build hook (:Lazy! restore
-- in CI). The implementation is set asynchronously after setup.
test("the prebuilt Rust fuzzy matcher is used", function()
  assert_eq(config.fuzzy.implementation, "prefer_rust", "fuzzy.implementation")
  vim.wait(5000, function()
    return require("blink.cmp.fuzzy").implementation_type == "rust"
  end, 50)
  assert_eq(require("blink.cmp.fuzzy").implementation_type, "rust", "fuzzy implementation in use")
end)

log("\n=== Keypress Tests ===\n")

local function line(n)
  if n then
    return vim.api.nvim_buf_get_lines(0, n - 1, n, false)[1]
  end
  return vim.api.nvim_get_current_line()
end

local function mode()
  return vim.api.nvim_get_mode().mode
end

local function col()
  return vim.api.nvim_win_get_cursor(0)[2]
end

-- blink sets its maps buffer-locally on InsertEnter
local function has_blink_map(m, lhs)
  local map = vim.fn.maparg(lhs, m, false, true)
  return map.buffer == 1 and vim.startswith(map.desc or "", "blink.cmp: ")
end

local function expand(body)
  config.snippets.expand(body)
end

-- A line of buffer words to complete from, with the cursor on an empty line
-- below it
local function words_line()
  vim.snippet.stop()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha_one alpha_two", "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
end

-- Label of the first item in the menu the last time menu_open() saw it.
-- alpha_one and alpha_two score the same, so which comes first depends on
-- blink's frecency history and cursor proximity, and differs between machines.
local first_item

-- Typing doesn't trigger the menu in headless Neovim, so open it
local function menu_open()
  if not cmp.is_menu_visible() then
    cmp.show()
    return false
  end
  local items = cmp.get_items() or {}
  if #items == 0 then
    return false
  end
  first_item = items[1].label
  assert_true(first_item == "alpha_one" or first_item == "alpha_two", "first item is " .. tostring(first_item))
  return true
end

-- Each step does something (fn, which may run actions and returns keys to
-- feed), then once those keys and anything they queued have been processed,
-- runs check. A check that returns false is retried, which is used to wait
-- for blink's scheduled commands and its async menu.
local steps = {}
local function step(name, fn, check)
  table.insert(steps, { name = name, fn = fn, check = check })
end

-- Typing in a placeholder can open the menu, and with the menu open
-- <Tab>/<S-Tab> select instead of jumping. cmp.hide() is scheduled, so wait
-- until the menu is really closed before the next key.
local function close_menu_step(name)
  step(name or "close the menu", function()
    cmp.hide()
    return ""
  end, function()
    return not cmp.is_visible()
  end)
end

step("blink maps <Tab>/<S-Tab> in insert and select mode", function()
  return ""
end, function()
  if not has_blink_map("i", "<Tab>") then
    return false
  end
  for _, m in ipairs({ "i", "s" }) do
    for _, lhs in ipairs({ "<Tab>", "<S-Tab>" }) do
      assert_true(has_blink_map(m, lhs), m .. " " .. lhs .. " not mapped by blink")
    end
  end
end)

step("expanding a snippet selects the first placeholder", function()
  expand("foo(${1:aaa}, ${2:bbb})")
  return ""
end, function()
  assert_true(vim.snippet.active(), "snippet not active")
  assert_eq(mode(), "s", "mode")
end)

step("typing replaces the first placeholder", function()
  return "X"
end, function()
  assert_eq(line(), "foo(X, bbb)", "line")
end)

close_menu_step()

step("<Tab> in insert mode jumps to the second placeholder", function()
  return "<Tab>"
end, function()
  if mode() ~= "s" then
    return false
  end
end)

step("typing replaces the second placeholder, giving foo(X, Y)", function()
  return "Y"
end, function()
  assert_eq(line(), "foo(X, Y)", "line")
end)

close_menu_step()

step("<S-Tab> jumps back to the first placeholder", function()
  return "<S-Tab>"
end, function()
  if mode() ~= "s" then
    return false
  end
  assert_eq(col(), #"foo(", "cursor")
end)

step("<Tab> in select mode jumps to the second placeholder", function()
  return "<Tab>"
end, function()
  if col() ~= #"foo(X, " then
    return false
  end
  assert_eq(mode(), "s", "mode")
end)

step("typing in select mode replaces the second placeholder", function()
  return "W"
end, function()
  assert_eq(line(), "foo(X, W)", "line")
end)

close_menu_step()

step("<Tab> on the last placeholder moves to the final tabstop", function()
  return "<Tab>"
end, function()
  -- Already in insert mode after typing W, so wait for the (scheduled) jump
  if col() ~= #"foo(X, W)" then
    return false
  end
  assert_eq(mode(), "i", "mode")
  assert_true(not vim.snippet.active({ direction = 1 }), "a placeholder is still ahead")
end)

step("clear the line", function()
  vim.snippet.stop()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
  return ""
end, function() end)

close_menu_step()

step("<Tab> with no menu and no snippet falls back to inserting indent", function()
  return "<Tab>"
end, function()
  return line():match("^%s+$") ~= nil
end)

step("the menu opens on buffer words inside a snippet, with nothing selected", function()
  words_line()
  expand("$1 end$2")
  return "alp"
end, function()
  if not menu_open() then
    return false
  end
  assert_true(vim.snippet.active({ direction = 1 }), "snippet not active")
  assert_eq(cmp.get_selected_item_idx(), nil, "selected item")
end)

step("<Tab> with the menu visible selects an item without inserting it", function()
  return "<Tab>"
end, function()
  if cmp.get_selected_item_idx() == nil then
    return false
  end
  assert_true(cmp.is_menu_visible(), "menu closed")
  assert_eq(mode(), "i", "mode")
  assert_eq(line(), "alp end", "line")
  assert_eq(col(), #"alp", "cursor")
end)

step("<C-e> closes the menu", function()
  return "<C-e>"
end, function()
  if cmp.is_menu_visible() then
    return false
  end
  assert_eq(line(), "alp end", "line")
end)

step("<Tab> after closing the menu jumps", function()
  return "<Tab>"
end, function()
  if col() ~= #"alp end" then
    return false
  end
  assert_true(not cmp.is_menu_visible(), "menu reopened")
end)

step("select mode with the menu open: snippet with three placeholders", function()
  words_line()
  expand("${1:a} ${2:b} ${3:c}")
  return "<Tab>"
end, function()
  if vim.fn.getcurpos()[3] - 1 ~= #"a " or mode() ~= "s" then
    return false
  end
end)

step("select mode with the menu open: type in the second placeholder", function()
  return "alp"
end, function()
  if not menu_open() then
    return false
  end
  assert_eq(line(), "a alp c", "line")
end)

step("select mode with the menu open: jump back to the first placeholder", function()
  vim.snippet.jump(-1)
  return ""
end, function()
  if mode() ~= "s" then
    return false
  end
  assert_true(cmp.is_menu_visible(), "menu closed on entering select mode")
end)

step("<Tab> in select mode jumps even with the menu open", function()
  return "<Tab>"
end, function()
  if col() ~= #"a " then
    return false
  end
  assert_eq(mode(), "s", "mode")
  assert_eq(cmp.get_selected_item_idx(), nil, "menu item selected")
end)

close_menu_step()

step("<CR> with nothing selected: menu open", function()
  vim.snippet.stop()
  words_line()
  return "alp"
end, function()
  if not menu_open() then
    return false
  end
  assert_eq(cmp.get_selected_item_idx(), nil, "selected item")
end)

step("<CR> with nothing selected accepts the first item, without a newline", function()
  return "<CR>"
end, function()
  if line(2) == "alp" then
    return false
  end
  assert_eq(line(2), first_item, "line 2")
  assert_eq(vim.api.nvim_buf_line_count(0), 2, "line count")
end)

close_menu_step()

step("<CR> without the menu inserts a newline", function()
  return "<CR>"
end, function()
  assert_eq(vim.api.nvim_buf_line_count(0), 3, "line count")
end)

step("<C-y> with nothing selected: menu open", function()
  words_line()
  return "alp"
end, function()
  return menu_open()
end)

step("<C-y> with nothing selected falls back to i_CTRL-Y instead of accepting", function()
  return "<C-y>"
end, function()
  assert_eq(line(2), "alph", "line 2")
end)

close_menu_step()

step("<Down>: menu open", function()
  words_line()
  return "alp"
end, function()
  return menu_open()
end)

step("<Down> selects an item without inserting it", function()
  return "<Down>"
end, function()
  if cmp.get_selected_item_idx() == nil then
    return false
  end
  assert_eq(line(2), "alp", "line 2")
end)

step("<C-y> accepts the selected item", function()
  return "<C-y>"
end, function()
  if line(2) == "alp" then
    return false
  end
  assert_eq(line(2), first_item, "line 2")
end)

close_menu_step()

step("<C-n> with the menu closed opens it without inserting", function()
  words_line()
  return "alp<C-n>"
end, function()
  if not cmp.is_menu_visible() or #(cmp.get_items() or {}) == 0 then
    return false
  end
  first_item = cmp.get_items()[1].label
  assert_eq(cmp.get_selected_item_idx(), nil, "selected item")
  assert_eq(line(2), "alp", "line 2")
end)

step("<C-n> with the menu open inserts the item as it selects it", function()
  return "<C-n>"
end, function()
  if line(2) == "alp" then
    return false
  end
  assert_eq(line(2), first_item, "line 2")
  assert_true(cmp.is_menu_visible(), "menu closed")
end)

local i = 0
local retries = 0
local SYNC = "<Plug>(completion-test-sync)"
local CHECK = "<Plug>(completion-test-check)"

-- Fed with remapping, so the <Plug> maps below fire
local function feed(keys)
  vim.api.nvim_feedkeys(t(keys), "t", false)
end

local function fail(name, err)
  h.fail(name, err)
  -- Later steps depend on this one
  feed("<Esc>")
  vim.schedule(h.finish)
end

local function next_step()
  i = i + 1
  local s = steps[i]
  if not s then
    feed("<Esc>")
    vim.schedule(h.finish)
    return
  end
  local ok, keys = pcall(s.fn)
  if not ok then
    return fail(s.name, keys)
  end
  -- The sync hop queues the check behind keys that vim.snippet and blink
  -- feed while processing these keys
  feed(keys .. SYNC)
end

local function check()
  local s = steps[i]
  local ok, res = pcall(s.check)
  if ok and res == false then
    retries = retries + 1
    if retries > 100 then
      local state = ("mode %s, cursor col %d, line %q, menu %s, snippet %s"):format(
        mode(),
        col(),
        line(),
        cmp.is_menu_visible() and "open" or "closed",
        vim.snippet.active() and "active" or "inactive"
      )
      return fail(s.name, "timed out waiting (" .. state .. ")")
    end
    vim.defer_fn(function()
      feed(CHECK)
    end, 20)
    return
  end
  retries = 0
  if not ok then
    return fail(s.name, res)
  end
  h.pass(s.name)
  next_step()
end

vim.keymap.set({ "i", "s" }, SYNC, function()
  feed(CHECK)
end)
vim.keymap.set({ "i", "s" }, CHECK, check)

-- Safety net so a stuck key sequence fails instead of hanging
vim.defer_fn(function()
  h.fail("keypress tests", "timed out at step " .. i .. (steps[i] and (" (" .. steps[i].name .. ")") or ""))
  h.finish()
end, 30000)

-- blink's buffer source skips nofile buffers, so complete in a real file
local path = vim.fn.tempname() .. ".txt"
vim.fn.writefile({ "" }, path)
vim.o.showmode = false
vim.cmd("silent edit " .. vim.fn.fnameescape(path))
feed("i")
next_step()

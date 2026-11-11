-- Core keymap tests: lua/core/keymaps.lua and the LSP keymaps in non-LSP buffers
-- Run with: nvim --headless -c "luafile tests/keymaps_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local out, test, assert_true, assert_eq = h.out, h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

local config_dir = vim.fn.resolve(vim.fn.stdpath("config"))

-- Re-run core/keymaps.lua with vim.keymap.set stubbed, to see every map it defines
local function captured_maps()
  local maps = {}
  local orig = vim.keymap.set
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.keymap.set = function(mode, lhs, rhs, opts)
    table.insert(maps, { mode = mode, lhs = lhs, rhs = rhs, opts = opts or {} })
  end
  local ok, err = pcall(dofile, config_dir .. "/lua/core/keymaps.lua")
  vim.keymap.set = orig
  if not ok then
    error(err)
  end
  return maps
end

out("\n=== Keymap Tests ===\n")

local maps = captured_maps()

test("core/keymaps.lua defines maps", function()
  assert_true(#maps > 0, "no maps captured")
end)

test("every core keymap has a desc", function()
  local missing = {}
  for _, m in ipairs(maps) do
    if not m.opts.desc or m.opts.desc == "" then
      table.insert(missing, vim.inspect(m.mode) .. " " .. m.lhs)
    end
  end
  assert_true(#missing == 0, "missing desc: " .. table.concat(missing, ", "))
end)

test("core/keymaps.lua leaves LSP and builtin keys alone", function()
  local lhs = {}
  for _, m in ipairs(maps) do
    lhs[m.lhs] = true
  end
  for _, key in ipairs({ "Y", "j", "k", "gr", "gd", "gD", "gI", "gy", "<D-b>", "<D-A-b>", "<A-F7>", "<S-F6>", "<A-CR>" }) do
    assert_true(not lhs[key], key .. " is still mapped in core/keymaps.lua")
  end
end)

test("config does not map gr globally", function()
  assert_eq(vim.fn.maparg("gr", "n"), "", "gr rhs")
end)

test("built-in LSP defaults grr/grn/gra/gri/gO are intact", function()
  for _, lhs in ipairs({ "grr", "grn", "gri", "gO" }) do
    assert_true(vim.fn.maparg(lhs, "n") ~= "", lhs .. " not mapped")
  end
  assert_true(vim.fn.maparg("gra", "n") ~= "", "gra not mapped in normal mode")
  assert_true(vim.fn.maparg("gra", "x") ~= "", "gra not mapped in visual mode")
end)

test("gd and friends have no map in a non-LSP scratch buffer", function()
  vim.cmd("enew")
  vim.bo.buftype = "nofile"
  local bufnr = vim.api.nvim_get_current_buf()
  assert_eq(#vim.lsp.get_clients({ bufnr = bufnr }), 0, "LSP clients in scratch buffer")
  local buf_maps = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    buf_maps[m.lhs] = true
  end
  for _, lhs in ipairs({ "gd", "gD", "gI", "gy", "gs", "<D-b>", "<D-A-b>", "<A-F7>", "<S-F6>", "<A-CR>" }) do
    assert_true(not buf_maps[lhs], lhs .. " has a buffer-local map")
    assert_eq(vim.fn.maparg(lhs, "n"), "", lhs .. " has a global map")
  end
end)

test("gl, <leader>e and <leader>E stay global", function()
  for _, lhs in ipairs({ "gl", "<leader>e", "<leader>E" }) do
    local m = vim.fn.maparg(lhs, "n", false, true)
    assert_true(m.lhs ~= nil, lhs .. " not mapped")
    assert_eq(m.buffer, 0, lhs .. " buffer")
  end
end)

test("<C-s> in insert mode saves, leaves insert mode and fires InsertLeave", function()
  local path = vim.fn.tempname() .. ".txt"
  vim.fn.writefile({ "" }, path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  local left = 0
  local id = vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = 0,
    callback = function()
      left = left + 1
    end,
  })
  vim.api.nvim_feedkeys(vim.keycode("ihello<C-s>"), "mx", false)
  vim.api.nvim_del_autocmd(id)
  assert_eq(vim.fn.mode(), "n", "mode after <C-s>")
  assert_eq(left, 1, "InsertLeave count")
  assert_true(not vim.bo.modified, "buffer still modified")
  assert_eq(vim.fn.readfile(path)[1], "hello", "file contents")
  vim.cmd("bwipeout!")
  vim.fn.delete(path)
end)

test("<C-s> in normal and visual mode saves", function()
  local path = vim.fn.tempname() .. ".txt"
  vim.fn.writefile({ "a" }, path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "b" })
  vim.api.nvim_feedkeys(vim.keycode("<C-s>"), "mx", false)
  assert_eq(vim.fn.readfile(path)[1], "b", "normal mode save")

  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "c" })
  vim.api.nvim_feedkeys(vim.keycode("v<C-s>"), "mx", false)
  assert_eq(vim.fn.mode(), "n", "mode after visual <C-s>")
  assert_eq(vim.fn.readfile(path)[1], "c", "visual mode save")
  vim.cmd("bwipeout!")
  vim.fn.delete(path)
end)

-- In-process LSP server that answers signature help requests. Every request
-- method is appended to log.
local function fake_signature_server(log)
  return h.fake_lsp_server({
    log = log,
    capabilities = { signatureHelpProvider = { triggerCharacters = { "(" } } },
    results = { ["textDocument/signatureHelp"] = { signatures = { { label = "add(a, b)" } } } },
  })
end

test("<C-k> in insert mode shows signature help in LSP buffers only, <C-s> still saves", function()
  local path = vim.fn.tempname() .. ".txt"
  vim.fn.writefile({ "" }, path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  assert_eq(h.find_keymap("i", "<C-K>", buf), nil, "<C-k> mapped before an LSP attached")

  local log = {}
  local client_id = vim.lsp.start({
    name = "keymaps_test_signature",
    cmd = fake_signature_server(log),
    root_dir = vim.fn.fnamemodify(path, ":h"),
  }, { bufnr = buf })
  assert_true(client_id ~= nil, "fake LSP client did not start")
  ---@cast client_id -nil
  vim.wait(2000, function()
    local client = vim.lsp.get_client_by_id(client_id)
    return client ~= nil and client.initialized == true
  end)

  local m = h.find_keymap("i", "<C-K>", buf)
  assert_true(m ~= nil, "<C-k> has no buffer-local insert map after LspAttach")
  ---@cast m -nil
  assert_eq(m.callback, vim.lsp.buf.signature_help, "<C-k> callback")
  assert_eq(m.desc, "LSP: Show function signature", "<C-k> desc")

  vim.api.nvim_feedkeys(vim.keycode("i<C-k><Esc>"), "mx", false)
  vim.wait(2000, function()
    return vim.tbl_contains(log, "textDocument/signatureHelp")
  end)
  assert_true(vim.tbl_contains(log, "textDocument/signatureHelp"), "no signatureHelp request: " .. vim.inspect(log))

  -- The save map, not Neovim's signature help default, still owns insert <C-s>
  assert_eq(h.find_keymap("i", "<C-S>", buf), nil, "<C-s> has a buffer-local insert map")
  assert_eq(vim.fn.maparg("<C-s>", "i", false, true).desc, "Save file", "insert <C-s> desc")
  vim.api.nvim_feedkeys(vim.keycode("ihello<C-s>"), "mx", false)
  assert_eq(vim.fn.mode(), "n", "mode after <C-s>")
  assert_true(not vim.bo.modified, "buffer still modified")
  assert_eq(vim.fn.readfile(path)[1], "hello", "file contents")

  vim.lsp.buf_detach_client(buf, client_id)
  vim.wait(2000, function()
    return h.find_keymap("i", "<C-K>", buf) == nil
  end)
  assert_eq(h.find_keymap("i", "<C-K>", buf), nil, "<C-k> still mapped after the client detached")
  assert_eq(vim.fn.maparg("<C-k>", "i"), "", "<C-k> has an insert map after detach")
  -- With the map gone, <C-k> enters digraphs again
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  vim.api.nvim_feedkeys(vim.keycode("cc<C-k>e:<Esc>"), "mx", false)
  assert_eq(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], "ë", "digraph after detach")

  local client = vim.lsp.get_client_by_id(client_id)
  if client then
    h.stop_client(client)
  end
  vim.cmd("bwipeout!")
  vim.fn.delete(path)
end)

h.finish()

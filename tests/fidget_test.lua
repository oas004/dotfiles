-- LSP progress tests: fidget.nvim (lua/plugins/language-server.lua)
-- Run with: nvim --headless -c "luafile tests/fidget_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

h.out("\n=== LSP Progress Tests ===\n")

-- In-process server that reports $/progress right after initialize, the way
-- jdtls and kotlin-lsp report a project import. send(value) sends another
-- progress notification for the same token.
local dispatchers
local function progress_server(d)
  dispatchers = d
  local closing = false
  return {
    request = function(method, _, callback)
      local result = method == "initialize" and { capabilities = {} } or vim.NIL
      vim.schedule(function()
        callback(nil, result)
      end)
      return true, 1
    end,
    notify = function(method)
      if method == "exit" and not closing then
        closing = true
        vim.schedule(function()
          d.on_exit(0, 0)
        end)
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      if not closing then
        closing = true
        vim.schedule(function()
          d.on_exit(0, 15)
        end)
      end
    end,
  }
end

local function send(value)
  dispatchers.notification("$/progress", { token = "import", value = value })
end

-- Text of the fidget window, or nil if it isn't open
local function fidget_text()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "fidget" then
      return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
  end
  return nil
end

test("fidget is not loaded before an LSP client attaches", function()
  assert_true(not h.plugin_loaded("fidget.nvim"), "fidget.nvim loaded at startup")
end)

local notify_before = vim.notify
local client
test("fidget loads when an LSP client attaches", function()
  vim.cmd("enew")
  local id = vim.lsp.start({ name = "fidget_test", cmd = progress_server, root_dir = vim.fn.getcwd() })
  assert_true(id ~= nil, "fake client did not start")
  ---@cast id -nil
  vim.wait(2000, function()
    local c = vim.lsp.get_client_by_id(id)
    return c ~= nil and c.initialized == true and h.plugin_loaded("fidget.nvim")
  end, 20)
  client = assert(vim.lsp.get_client_by_id(id))
  assert_true(h.plugin_loaded("fidget.nvim"), "fidget.nvim not loaded after LspAttach")
end)

test("fidget does not replace vim.notify", function()
  assert_eq(vim.notify, notify_before, "vim.notify after loading fidget")
end)

test("progress from a server shows in the fidget window", function()
  assert_true(client ~= nil, "no client")
  send({ kind = "begin", title = "Importing Gradle project", percentage = 0 })
  send({ kind = "report", message = "Resolving dependencies", percentage = 40 })
  vim.wait(3000, function()
    local text = fidget_text()
    return text ~= nil and text:find("Resolving dependencies", 1, true) ~= nil
  end, 20)
  local text = fidget_text()
  assert_true(text ~= nil, "no fidget window")
  ---@cast text -nil
  assert_true(text:find("Importing Gradle project", 1, true) ~= nil, "title not shown: " .. text)
  assert_true(text:find("Resolving dependencies", 1, true) ~= nil, "message not shown: " .. text)
  assert_true(text:find("fidget_test", 1, true) ~= nil, "client name not shown: " .. text)
end)

test("the progress is cleared after it ends", function()
  send({ kind = "end", message = "Done" })
  -- fidget keeps finished items on screen for a few seconds
  local closed = vim.wait(10000, function()
    local text = fidget_text()
    return text == nil or text:find("Importing Gradle project", 1, true) == nil
  end, 50)
  assert_true(closed, "progress still shown: " .. tostring(fidget_text()))
end)

if client then
  h.stop_client(client)
end
vim.cmd("bwipeout!")

h.finish()

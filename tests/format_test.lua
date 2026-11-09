-- Formatting config tests (conform.nvim)
-- Run with: NVIM_APPNAME=<appname> nvim --headless -c "luafile tests/format_test.lua"

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
  if not val then error(msg or "expected true", 2) end
end

local function assert_eq(actual, expected, msg)
  if not vim.deep_equal(actual, expected) then
    error(string.format("%s: expected %s, got %s", msg or "mismatch",
      vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

-- Wait for lazy to finish loading
vim.wait(3000, function()
  return require("lazy").stats().loaded > 0
end)

print("\n=== Format Tests ===\n")

--- Create a scratch buffer with the given filetype (no FileType autocmds, so no LSP starts).
local function scratch(ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("eventignore", "FileType", { scope = "global" })
  vim.bo[buf].filetype = ft
  vim.api.nvim_set_option_value("eventignore", "", { scope = "global" })
  return buf
end

--- The format_on_save function passed to conform.setup, read from the lazy spec.
local function format_on_save_fn()
  local plugin = require("lazy.core.config").plugins["conform.nvim"]
  assert_true(plugin ~= nil, "conform.nvim spec not found")
  local opts = require("lazy.core.plugin").values(plugin, "opts", false)
  assert_true(type(opts.format_on_save) == "function", "format_on_save is not a function")
  return opts.format_on_save
end

local function conform_loaded()
  return require("lazy.core.config").plugins["conform.nvim"]._.loaded ~= nil
end

-- These run first, before anything below requires conform and loads it.
test("conform is not loaded at startup", function()
  assert_true(not conform_loaded(), "conform.nvim loaded at startup")
  assert_true(package.loaded["conform"] == nil, "conform module required at startup")
end)

test(":KotlinFormat and :JavaFormat exist before conform is loaded", function()
  local cmds = vim.api.nvim_get_commands({})
  assert_eq(cmds.KotlinFormat and cmds.KotlinFormat.definition, "Format Kotlin buffer with ktfmt", "KotlinFormat")
  assert_eq(cmds.JavaFormat and cmds.JavaFormat.definition, "Format Java buffer with google-java-format", "JavaFormat")
end)

test("<leader>cf is mapped before conform is loaded", function()
  local map = vim.fn.maparg("<leader>cf", "n", false, true)
  assert_eq(map.desc, "Format buffer", "<leader>cf desc")
end)

--- An in-process language server that can format: it inserts "// <name>" at
--- the top of the buffer. Every request method is appended to log as "<name>:<method>".
local function fake_server(name, log)
  return function(dispatchers)
    local closing = false
    local id = 0
    return {
      request = function(method, _, callback)
        id = id + 1
        table.insert(log, name .. ":" .. method)
        local result = nil
        if method == "initialize" then
          result = { capabilities = { documentFormattingProvider = true } }
        elseif method == "textDocument/formatting" then
          local pos = { line = 0, character = 0 }
          result = { { range = { start = pos, ["end"] = pos }, newText = "// " .. name .. "\n" } }
        end
        vim.schedule(function() callback(nil, result) end)
        return true, id
      end,
      notify = function(method)
        if method == "exit" then
          closing = true
          vim.schedule(function() dispatchers.on_exit(0, 0) end)
        end
        return true
      end,
      is_closing = function() return closing end,
      terminate = function()
        if not closing then
          closing = true
          vim.schedule(function() dispatchers.on_exit(0, 15) end)
        end
      end,
    }
  end
end

test("first save of a C file loads conform and formats with clangd only", function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local path = dir .. "/m.c"
  vim.fn.writefile({ "int main(void) { return 0; }" }, path)
  -- No FileType autocmds, so the real clangd does not start
  vim.api.nvim_set_option_value("eventignore", "FileType", { scope = "global" })
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  vim.api.nvim_set_option_value("eventignore", "", { scope = "global" })
  local buf = vim.api.nvim_get_current_buf()
  assert_eq(vim.bo[buf].filetype, "c", "filetype")

  local log = {}
  local ids = {}
  for _, name in ipairs({ "other", "clangd" }) do
    ids[name] = vim.lsp.start({ name = name, cmd = fake_server(name, log), root_dir = dir }, { bufnr = buf })
  end
  vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = buf }) == 2
  end)
  assert_eq(#vim.lsp.get_clients({ bufnr = buf }), 2, "fake clients attached")
  assert_true(not conform_loaded(), "conform.nvim loaded before the first save")

  vim.cmd("silent write")
  local lines = vim.fn.readfile(path)
  for _, id in pairs(ids) do
    local c = vim.lsp.get_client_by_id(id)
    if c then c:stop(true) end
  end
  vim.cmd("bwipeout!")
  vim.fn.delete(dir, "rf")

  assert_true(conform_loaded(), "conform.nvim not loaded by the first save")
  -- Formatted once, and only by the client named clangd
  assert_eq(lines, { "// clangd", "int main(void) { return 0; }" }, "saved file")
  assert_true(vim.list_contains(log, "clangd:textDocument/formatting"), "clangd not asked to format")
  assert_true(not vim.list_contains(log, "other:textDocument/formatting"), "other client asked to format")
end)

-- Runs in a child nvim (same config, NVIM_APPNAME is inherited) so conform is
-- not loaded yet. Prints a JSON result on stdout.
local kotlin_format_child = [[
local plugin = require("lazy.core.config").plugins["conform.nvim"]
local loaded_before = plugin._.loaded ~= nil
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)
vim.o.eventignore = "FileType"
vim.bo[buf].filetype = "kotlin"
vim.o.eventignore = ""
local msgs = {}
vim.notify = function(msg) table.insert(msgs, msg) end
local ok, err = pcall(vim.cmd.KotlinFormat)
io.stdout:write(vim.json.encode({
  loaded_before = loaded_before,
  loaded_after = plugin._.loaded ~= nil,
  ok = ok,
  err = tostring(err),
  msgs = msgs,
}))
vim.cmd("qa!")
]]

test(":KotlinFormat loads conform and formats", function()
  local script = vim.fn.tempname() .. ".lua"
  vim.fn.writefile(vim.split(kotlin_format_child, "\n"), script)
  local proc = vim.system({ vim.v.progpath, "--headless", "-c", "luafile " .. vim.fn.fnameescape(script) },
    { text = true, stdin = false }):wait(30000)
  vim.fn.delete(script)
  local ok, res = pcall(vim.json.decode, proc.stdout or "")
  assert_true(ok and type(res) == "table", "child nvim printed no result (exit " .. tostring(proc.code) .. "): "
    .. tostring(proc.stdout) .. tostring(proc.stderr))
  assert_true(not res.loaded_before, "conform.nvim already loaded in the child")
  assert_true(res.ok, res.err)
  assert_true(res.loaded_after, "conform.nvim not loaded by :KotlinFormat")
  -- Which message depends on whether ktfmt is installed, but conform ran
  assert_eq(#res.msgs, 1, "notifications " .. vim.inspect(res.msgs))
  assert_true(res.msgs[1]:find("Kotlin file", 1, true) ~= nil, res.msgs[1])
end)

test("conform.setup ran with format_on_save", function()
  assert_true(#vim.api.nvim_get_autocmds({ group = "Conform", event = "BufWritePre" }) == 1,
    "no Conform BufWritePre autocmd")
end)

test("formatters_by_ft: kotlin uses ktfmt", function()
  assert_eq(require("conform").formatters_by_ft.kotlin, { "ktfmt" }, "kotlin")
end)

test("formatters_by_ft: java uses google-java-format", function()
  assert_eq(require("conform").formatters_by_ft.java, { "google-java-format" }, "java")
end)

test("formatters_by_ft: rust uses rustfmt", function()
  assert_eq(require("conform").formatters_by_ft.rust, { "rustfmt" }, "rust")
end)

test("formatters_by_ft: json uses jq/prettierd/prettier", function()
  local json = require("conform").formatters_by_ft.json
  assert_eq({ json[1], json[2], json[3], json.stop_after_first },
    { "jq", "prettierd", "prettier", true }, "json")
end)

test("ktfmt runs with --kotlinlang-style", function()
  local buf = scratch("kotlin")
  local config = require("conform").get_formatter_config("ktfmt", buf)
  assert_true(config ~= nil, "no ktfmt formatter config")
  local runner = require("conform.runner")
  local cmd = runner.build_cmd("ktfmt", runner.build_context(buf, config), config)
  vim.api.nvim_buf_delete(buf, { force = true })
  if type(cmd) == "string" then
    cmd = vim.split(cmd, " ", { trimempty = true })
  end
  assert_eq(vim.list_slice(cmd, 2), { "--kotlinlang-style", "-" }, "ktfmt args")
end)

-- Filetypes formatted by their language server only, and the server
local lsp_only = {
  haskell = "hls", lhaskell = "hls",
  c = "clangd", cpp = "clangd", objc = "clangd", objcpp = "clangd",
}

for ft, server in vim.spairs(lsp_only) do
  test("formatters_by_ft: " .. ft .. " formats with " .. server .. " only", function()
    assert_eq(require("conform").formatters_by_ft[ft], { lsp_format = "fallback", name = server }, ft)
  end)
end

local on_save = { java = 5000, rust = 5000 }
for ft in pairs(lsp_only) do
  on_save[ft] = 10000
end

for ft, timeout in vim.spairs(on_save) do
  test("format_on_save returns options for " .. ft, function()
    local buf = scratch(ft)
    local res = format_on_save_fn()(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert_true(type(res) == "table", "expected table, got " .. vim.inspect(res))
    assert_true(not res.async, "format_on_save must be synchronous")
    assert_eq(res.lsp_format, "fallback", "lsp_format")
    assert_eq(res.timeout_ms, timeout, "timeout_ms")
  end)
end

for _, ft in ipairs({ "kotlin", "json", "lua" }) do
  test("format_on_save returns nil for " .. ft, function()
    local buf = scratch(ft)
    local res = format_on_save_fn()(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert_eq(res, nil, ft)
  end)
end

for ft, timeout in vim.spairs({ c = 10000, rust = 5000, kotlin = 5000 }) do
  test("<leader>cf formats " .. ft .. " with conform", function()
    local map = vim.fn.maparg("<leader>cf", "n", false, true)
    assert_true(not vim.tbl_isempty(map), "<leader>cf not mapped")
    assert_eq(map.desc, "Format buffer", "<leader>cf desc")
    assert_true(map.callback ~= nil, "<leader>cf has no Lua callback")
    local buf = scratch(ft)
    vim.api.nvim_set_current_buf(buf)
    local conform = require("conform")
    local orig = conform.format
    local got ---@type table?
    conform.format = function(opts) got = opts end
    local ok, err = pcall(map.callback)
    conform.format = orig
    vim.api.nvim_buf_delete(buf, { force = true })
    assert_true(ok, tostring(err))
    assert_true(got ~= nil, "<leader>cf did not call conform.format")
    ---@cast got -nil
    assert_eq(got.lsp_format, "fallback", "lsp_format")
    assert_eq(got.timeout_ms, timeout, "timeout_ms")
  end)
end

test("<leader>fm is no longer mapped", function()
  assert_true(vim.tbl_isempty(vim.fn.maparg("<leader>fm", "n", false, true)),
    "<leader>fm still mapped (collides with <leader>f)")
end)

test("none-ls is not configured", function()
  assert_true(require("lazy.core.config").plugins["none-ls.nvim"] == nil, "none-ls still in spec")
end)

-- ktfmt and google-java-format are installed by Mason (vim.g.mason_tools in
-- language-server.lua), and mason.setup() puts mason/bin first on PATH, so
-- conform should run Mason's copies. On CI they must be installed (by
-- .github/scripts/ci_warmup.lua); locally they are skipped until Mason has
-- installed them.
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"
local samples = {
  { tool = "ktfmt", ft = "kotlin", input = { "fun  main( ) { println( 1 ) }" },
    want = { "fun main() {", "    println(1)", "}" } },
  { tool = "google-java-format", ft = "java", input = { "class A {  void f( ) { } }" },
    want = { "class A {", "  void f() {}", "}" } },
}
for _, s in ipairs(samples) do
  if vim.fn.executable(mason_bin .. s.tool) == 1 or vim.env.CI then
    test("conform formats " .. s.ft .. " with Mason's " .. s.tool, function()
      assert_eq(vim.fn.exepath(s.tool), mason_bin .. s.tool, s.tool .. " on PATH")
      local buf = scratch(s.ft)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, s.input)
      local err ---@type string?
      require("conform").format({ bufnr = buf, formatters = { s.tool }, async = false, timeout_ms = 30000 },
        function(e) err = e end)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert_true(err == nil, tostring(err))
      assert_eq(lines, s.want, s.tool .. " output")
    end)
  else
    print("- conform formats " .. s.ft .. " with Mason's " .. s.tool .. " (skipped: not installed)")
  end
end


-- Summary
print("\n=== Results ===")
print(string.format("Passed: %d, Failed: %d", passed, failed))

if failed > 0 then
  vim.cmd("cq 1")  -- Exit with error code
else
  vim.cmd("qa!")
end

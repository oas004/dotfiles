-- LSP and completion tests
-- Run with: nvim --headless -c "luafile tests/lsp_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, skip = h.test, h.skip
local assert_true, assert_not_nil, assert_eq = h.assert_true, h.assert_not_nil, h.assert_eq

-- Call a config's cmd function with vim.lsp.rpc.start stubbed out, and return
-- the argv it would have spawned
local function resolve_cmd(cmd, root_dir)
  if type(cmd) == "table" then
    return cmd
  end
  local captured
  local orig = vim.lsp.rpc.start
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.rpc.start = function(argv)
    captured = argv
    return {}
  end
  local ok, err = pcall(cmd, {}, { root_dir = root_dir })
  vim.lsp.rpc.start = orig
  if not ok then
    error(err)
  end
  return captured
end

local function has_arg(argv, pattern)
  for _, a in ipairs(argv or {}) do
    if a:find(pattern) then
      return true
    end
  end
  return false
end

-- Open a file in a fresh buffer and wait for the named client to attach
local function attach(path, lines, name, timeout)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()
  vim.wait(timeout or 15000, function()
    return #vim.lsp.get_clients({ bufnr = bufnr, name = name }) > 0
  end, 100)
  return vim.lsp.get_clients({ bufnr = bufnr, name = name })[1], bufnr
end

h.wait_for_lazy()

local tmp = vim.fn.tempname()
-- Unique project names, so the per-root cache dirs created below can be removed again
local proj = "lsp-test-" .. vim.fn.getpid()
local created_dirs = {}
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"

h.out("\n=== LSP Config Tests ===\n")

test("lsp-zero is not installed as a plugin", function()
  assert_true(require("lazy.core.config").plugins["lsp-zero.nvim"] == nil, "lsp-zero.nvim still in spec")
end)

test("cmp capabilities applied to all servers", function()
  local caps = vim.lsp.config["*"].capabilities
  assert_not_nil(caps, "no global capabilities")
  ---@cast caps -nil
  local expected = require("cmp_nvim_lsp").default_capabilities().textDocument.completion
  assert_true(
    vim.deep_equal(caps.textDocument.completion, expected),
    "completion capabilities differ from cmp_nvim_lsp: " .. vim.inspect(caps.textDocument.completion)
  )
end)

test("lua_ls has diagnostics.globals = { 'vim' }", function()
  local globals = vim.tbl_get(vim.lsp.config.lua_ls, "settings", "Lua", "diagnostics", "globals")
  assert_true(globals and vim.tbl_contains(globals, "vim"), "vim not in globals")
end)

test("lua_ls is force-stopped if it hangs on exit", function()
  assert_eq(vim.lsp.config.lua_ls.exit_timeout, 2000, "exit_timeout")
end)

test("clangd cmd includes --fallback-style=LLVM", function()
  local cmd = vim.lsp.config.clangd.cmd
  assert_true(type(cmd) == "table" and vim.tbl_contains(cmd, "--fallback-style=LLVM"), vim.inspect(cmd))
end)

test("hls uses ormolu", function()
  assert_eq(vim.tbl_get(vim.lsp.config.hls, "settings", "haskell", "formattingProvider"), "ormolu")
end)

-- Mirrors project_dir() in language-server.lua: folder name plus a short hash of the root
local function cache_dir(base, root)
  local r = vim.fs.normalize(root)
  return base .. "/" .. vim.fs.basename(r) .. "-" .. vim.fn.sha256(r):sub(1, 8)
end

test("jdtls cmd has JVM memory args and per-root workspace", function()
  local paths = require("core.paths")
  local a, b = tmp .. "/" .. proj .. "-a", tmp .. "/" .. proj .. "-b"
  table.insert(created_dirs, cache_dir(paths.lsp_cache.jdtls, a))
  table.insert(created_dirs, cache_dir(paths.lsp_cache.jdtls, b))
  local argv = resolve_cmd(vim.lsp.config.jdtls.cmd, a)
  assert_true(has_arg(argv, "^%-%-jvm%-arg=%-Xmx%d+g$"), "no -Xmx: " .. vim.inspect(argv))
  assert_true(has_arg(argv, "MaxMetaspaceSize="), "no MaxMetaspaceSize: " .. vim.inspect(argv))
  assert_eq(argv[vim.fn.index(argv, "-data") + 2], cache_dir(paths.lsp_cache.jdtls, a), "-data dir")

  local other = resolve_cmd(vim.lsp.config.jdtls.cmd, b)
  assert_eq(other[vim.fn.index(other, "-data") + 2], cache_dir(paths.lsp_cache.jdtls, b), "-data dir per root")
end)

test("jdtls workspaces differ for same-named projects in different places", function()
  local paths = require("core.paths")
  local a, b = tmp .. "/x/" .. proj, tmp .. "/y/" .. proj
  table.insert(created_dirs, cache_dir(paths.lsp_cache.jdtls, a))
  table.insert(created_dirs, cache_dir(paths.lsp_cache.jdtls, b))
  local da = resolve_cmd(vim.lsp.config.jdtls.cmd, a)
  local db = resolve_cmd(vim.lsp.config.jdtls.cmd, b)
  local wa, wb = da[vim.fn.index(da, "-data") + 2], db[vim.fn.index(db, "-data") + 2]
  assert_true(wa ~= wb, "same workspace for both: " .. tostring(wa))
end)

test("jdtls has no hard-coded JavaSE-17 runtime", function()
  assert_true(
    vim.tbl_get(vim.lsp.config.jdtls, "settings", "java", "configuration", "runtimes") == nil,
    "runtimes still configured"
  )
end)

test("jdtls java.home follows JAVA_HOME and is never empty", function()
  local java = vim.tbl_get(vim.lsp.config.jdtls, "settings", "java") or {}
  local env = vim.env.JAVA_HOME
  if env and env ~= "" then
    assert_eq(java.home, env, "java.home")
  else
    assert_eq(java.home, nil, "java.home without JAVA_HOME")
  end
  -- vscode-java's java.jdt.ls.java.home is a client-side setting that jdtls
  -- itself never reads, so it must not replace java.home here
  assert_eq(vim.tbl_get(java, "jdt", "ls", "java", "home"), nil, "java.jdt.ls.java.home")
end)

-- Same list as language-server.lua
local listed =
  { "gradle_ls", "jedi_language_server", "lua_ls", "hls", "clangd", "jdtls", "kotlin_lsp", "rust_analyzer" }

test("listed servers are enabled", function()
  for _, name in ipairs(listed) do
    assert_true(vim.lsp.is_enabled(name), name .. " not enabled")
  end
end)

test("servers outside the list are not enabled", function()
  for _, name in ipairs({ "yamlls", "jsonls", "html", "ts_ls", "terraformls", "dockerls" }) do
    assert_true(not vim.lsp.is_enabled(name), name .. " is enabled")
  end
  local enabled
  if vim.lsp.get_configs then
    enabled = vim.tbl_map(function(c)
      return c.name
    end, vim.lsp.get_configs({ enabled = true }))
  else
    -- Neovim 0.11 has no public way to list enabled configs
    -- (vim.lsp.get_configs is 0.12+), so read the private table there.
    enabled = vim.tbl_keys(vim.lsp._enabled_configs)
  end
  for _, name in ipairs(enabled) do
    assert_true(vim.tbl_contains(listed, name), "unexpected server enabled: " .. name)
  end
end)

test("mason-lspconfig does not auto-enable installed servers", function()
  local settings = require("mason-lspconfig.settings").current
  assert_eq(settings.automatic_enable, false, "automatic_enable")
end)

test("rust_analyzer comes from rustup, not Mason", function()
  local ensure = require("mason-lspconfig.settings").current.ensure_installed
  assert_true(not vim.tbl_contains(ensure, "rust_analyzer"), "rust_analyzer in ensure_installed")
end)

test("Mason installs kotlin-lsp, ktfmt and google-java-format", function()
  local ensure = require("mason-lspconfig.settings").current.ensure_installed
  assert_true(vim.tbl_contains(ensure, "kotlin_lsp"), "kotlin_lsp not in ensure_installed")
  local map = require("mason-lspconfig").get_mappings().lspconfig_to_package
  assert_eq(map.kotlin_lsp, "kotlin-lsp", "kotlin_lsp package")
  local tools = vim.g.mason_tools or {}
  assert_true(vim.tbl_contains(tools, "ktfmt"), "ktfmt not in vim.g.mason_tools")
  assert_true(vim.tbl_contains(tools, "google-java-format"), "google-java-format not in vim.g.mason_tools")
  local registry = require("mason-registry")
  registry.refresh() -- synchronous without a callback
  for _, name in ipairs(vim.list_extend({ "kotlin-lsp" }, tools)) do
    assert_true(registry.has_package(name), name .. " is not in the Mason registry")
  end
  -- The cmd below runs this name, so it must be what the package links into mason/bin
  local bin = registry.get_package("kotlin-lsp").spec.bin
  assert_true(bin and bin["intellij-server"] ~= nil, "kotlin-lsp has no intellij-server bin: " .. vim.inspect(bin))
end)

test("kotlin_lsp config exists with kotlin filetype", function()
  local cfg = vim.lsp.config.kotlin_lsp
  assert_not_nil(cfg, "kotlin_lsp not configured")
  ---@cast cfg -nil
  assert_true(vim.tbl_contains(cfg.filetypes or {}, "kotlin"), "kotlin not in filetypes")
  assert_true(vim.tbl_contains(cfg.root_markers or {}, "settings.gradle.kts"), "settings.gradle.kts not a root marker")
end)

test("kotlin_lsp cmd runs Mason's intellij-server with per-root --system-path", function()
  local paths = require("core.paths")
  local root = tmp .. "/" .. proj .. "-kt"
  table.insert(created_dirs, cache_dir(paths.lsp_cache.kotlin_lsp, root))
  local argv = resolve_cmd(vim.lsp.config.kotlin_lsp.cmd, root)
  assert_eq(argv[1], "intellij-server", "binary")
  assert_true(vim.tbl_contains(argv, "--stdio"), "no --stdio")
  assert_eq(argv[vim.fn.index(argv, "--system-path") + 2], cache_dir(paths.lsp_cache.kotlin_lsp, root), "--system-path")
end)

h.out("\n=== Completion Tests ===\n")

test("cmp has nvim_lsp and buffer sources", function()
  local names = vim.tbl_map(function(s)
    return s.name
  end, require("cmp").get_config().sources)
  for _, want in ipairs({ "nvim_lsp", "buffer" }) do
    assert_true(vim.tbl_contains(names, want), want .. " not in " .. vim.inspect(names))
  end
end)

test("cmp-buffer is installed", function()
  assert_not_nil(require("cmp_buffer"), "cmp_buffer missing")
end)

test("cmp keeps existing mappings", function()
  local mapping = require("cmp").get_config().mapping
  for _, key in ipairs({ "<C-Space>", "<Tab>", "<S-Tab>", "<CR>", "<C-U>", "<C-D>" }) do
    assert_not_nil(mapping[key], key .. " not mapped")
  end
end)

h.out("\n=== LSP Runtime Tests ===\n")

test("LSP keymaps stay until the last client detaches", function()
  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  local function buf_map(lhs, mode)
    local m = vim.fn.maparg(lhs, mode or "n", false, true)
    return m.buffer == 1 and m or nil
  end
  local ids = {}
  for _, name in ipairs({ "fake_a", "fake_b" }) do
    table.insert(ids, vim.lsp.start({ name = name, cmd = h.fake_lsp_server(), root_dir = tmp }, { bufnr = bufnr }))
  end
  vim.wait(2000, function()
    return #vim.lsp.get_clients({ bufnr = bufnr }) == 2
  end, 20)
  assert_eq(#vim.lsp.get_clients({ bufnr = bufnr }), 2, "fake clients attached")
  assert_true(buf_map("gd"), "gd not mapped after attach")

  vim.lsp.buf_detach_client(bufnr, ids[1])
  assert_true(buf_map("gd"), "gd removed while fake_b is still attached")
  assert_true(buf_map("<F4>", "x"), "<F4> (visual) removed while fake_b is still attached")

  vim.lsp.buf_detach_client(bufnr, ids[2])
  for _, lhs in ipairs({
    "gd",
    "gD",
    "gI",
    "gy",
    "gs",
    "<F2>",
    "<F4>",
    "<leader>ca",
    "<leader>cr",
    "<D-b>",
    "<D-A-b>",
    "<A-F7>",
    "<S-F6>",
    "<A-CR>",
  }) do
    assert_true(not buf_map(lhs), lhs .. " still mapped after the last client detached")
  end
  assert_true(not buf_map("<F4>", "x"), "<F4> (visual) still mapped after the last client detached")
  -- No buffer-local gd left, so the builtin applies again
  assert_true(vim.tbl_isempty(vim.fn.maparg("gd", "n", false, true)), "gd still mapped")

  h.stop_clients(vim.tbl_map(vim.lsp.get_client_by_id, ids))
  vim.cmd("bwipeout!")
end)

-- Start a fake server with capabilities on a new buffer, wait for it to
-- initialize, and return the client and buffer. Request methods go to log.
local function start_fake(name, capabilities, results, log)
  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  local id = vim.lsp.start({
    name = name,
    cmd = h.fake_lsp_server({ capabilities = capabilities, results = results, log = log }),
    root_dir = tmp,
  }, { bufnr = bufnr })
  assert_not_nil(id, name .. " did not start")
  ---@cast id -nil
  vim.wait(2000, function()
    local c = vim.lsp.get_client_by_id(id)
    return c ~= nil and c.initialized == true
  end, 20)
  return assert(vim.lsp.get_client_by_id(id)), bufnr
end

local function count(log, method)
  return #vim.tbl_filter(function(m)
    return m == method
  end, log)
end

local function wait_for_request(log, method, n)
  vim.wait(2000, function()
    return count(log, method) >= (n or 1)
  end, 20)
  return count(log, method)
end

local zero_range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } }

test("inlay hints are on, and <leader>uh toggles them everywhere", function()
  local log = {}
  -- textDocumentSync, since 0.11 asks for hints after didOpen/didChange
  local client, bufnr = start_fake("fake_hints", { inlayHintProvider = true, textDocumentSync = 1 }, {
    ["textDocument/inlayHint"] = { { position = { line = 0, character = 1 }, label = ": int", kind = 1 } },
  }, log)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "x = 1" })
  assert_true(vim.lsp.inlay_hint.is_enabled(), "inlay hints not enabled globally")
  assert_true(vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), "inlay hints not enabled in the buffer")
  assert_true(wait_for_request(log, "textDocument/inlayHint") > 0, "no inlayHint request: " .. vim.inspect(log))

  local m = h.find_keymap("n", "<leader>uh")
  assert_true(m ~= nil and m.callback ~= nil, "<leader>uh not mapped")
  ---@cast m -nil
  assert_eq(m.desc, "Toggle inlay hints", "<leader>uh desc")
  m.callback()
  assert_true(not vim.lsp.inlay_hint.is_enabled(), "still enabled after <leader>uh")
  assert_true(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), "still enabled in the buffer after <leader>uh")
  m.callback()
  assert_true(vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), "not enabled again after a second <leader>uh")

  h.stop_client(client)
  vim.cmd("bwipeout!")
end)

-- 0.12 has vim.lsp.codelens.enable() and a global grx; 0.11 needs refresh()
local native_codelens = vim.lsp.codelens.enable ~= nil

local function lenses(bufnr)
  if native_codelens then
    -- 0.12's signature; make lint type-checks against the 0.11 runtime
    ---@diagnostic disable-next-line: param-type-mismatch
    return vim.lsp.codelens.get({ bufnr = bufnr })
  end
  return vim.lsp.codelens.get(bufnr)
end

test("code lenses are fetched and kept up to date", function()
  local log = {}
  local client, bufnr = start_fake("fake_lens", { codeLensProvider = { resolveProvider = false } }, {
    ["textDocument/codeLens"] = { { range = zero_range, command = { title = "2 references", command = "noop" } } },
  }, log)
  assert_true(wait_for_request(log, "textDocument/codeLens") > 0, "no codeLens request: " .. vim.inspect(log))
  vim.wait(1000, function()
    return #lenses(bufnr) > 0
  end, 20)
  assert_eq(#lenses(bufnr), 1, "code lenses stored for the buffer")

  -- Editing in insert mode and leaving it asks for the lenses again
  local before = count(log, "textDocument/codeLens")
  vim.api.nvim_feedkeys("ix\27", "x", false)
  assert_true(
    wait_for_request(log, "textDocument/codeLens", before + 1) > before,
    "no codeLens request after an edit: " .. vim.inspect(log)
  )

  for _, lhs in ipairs(native_codelens and { "<leader>cl" } or { "<leader>cl", "grx" }) do
    local m = h.find_keymap("n", lhs, bufnr)
    assert_true(m ~= nil, lhs .. " not mapped in the buffer")
    ---@cast m -nil
    assert_eq(m.callback, vim.lsp.codelens.run, lhs .. " callback")
  end
  if native_codelens then
    assert_true(vim.fn.maparg("grx", "n") ~= "", "built-in grx missing")
  end

  h.stop_client(client)
  vim.cmd("bwipeout!")
end)

if not native_codelens then
  test("0.11: code lens refresh stops when the last client detaches", function()
    local log = {}
    local client, bufnr = start_fake("fake_lens_detach", { codeLensProvider = {} }, {
      ["textDocument/codeLens"] = {},
    }, log)
    wait_for_request(log, "textDocument/codeLens")
    assert_true(#vim.api.nvim_get_autocmds({ group = "user_codelens_" .. bufnr }) > 0, "no refresh autocmds")
    vim.lsp.buf_detach_client(bufnr, client.id)
    vim.wait(1000, function()
      return not pcall(vim.api.nvim_get_autocmds, { group = "user_codelens_" .. bufnr })
    end, 20)
    assert_true(
      not pcall(vim.api.nvim_get_autocmds, { group = "user_codelens_" .. bufnr }),
      "refresh autocmds left after detach"
    )
    h.stop_client(client)
    vim.cmd("bwipeout!")
  end)

  test("0.11: no code lens refresh for servers without code lenses", function()
    local client, bufnr = start_fake("fake_no_lens", {}, {}, {})
    assert_true(
      not pcall(vim.api.nvim_get_autocmds, { group = "user_codelens_" .. bufnr }),
      "refresh autocmds created for a server without code lenses"
    )
    h.stop_client(client)
    vim.cmd("bwipeout!")
  end)
else
  skip("0.11: code lens refresh stops when the last client detaches", "0.12 refreshes code lenses itself")
  skip("0.11: no code lens refresh for servers without code lenses", "0.12 refreshes code lenses itself")
end

if vim.fn.executable(mason_bin .. "lua-language-server") == 1 then
  test("lua_ls attaches with globals and buffer keymaps", function()
    local client, bufnr = attach(tmp .. "/lua/t.lua", { "vim.print(1)" }, "lua_ls")
    assert_not_nil(client, "lua_ls did not attach")
    local globals = vim.tbl_get(client.config.settings, "Lua", "diagnostics", "globals")
    assert_true(globals and vim.tbl_contains(globals, "vim"), "running client lacks globals")
    assert_eq(vim.tbl_get(client.config.settings, "Lua", "hint", "enable"), true, "Lua.hint.enable")
    assert_not_nil(
      vim.tbl_get(client.config.capabilities, "textDocument", "completion", "completionItem", "resolveSupport"),
      "running client lacks cmp capabilities"
    )

    -- maparg() on the current buffer prefers buffer-local maps and normalizes
    -- keys like <D-A-b>, so .buffer == 1 means the map is buffer-local
    assert_eq(vim.api.nvim_get_current_buf(), bufnr, "current buffer")
    local function buf_map(mode, lhs)
      local m = vim.fn.maparg(lhs, mode, false, true)
      return m.buffer == 1 and m or nil
    end
    for _, lhs in ipairs({
      "<leader>ca",
      "<leader>cr",
      "gs",
      "<F2>",
      "<F4>",
      "gd",
      "gD",
      "gI",
      "gy",
      "<D-b>",
      "<D-A-b>",
      "<A-F7>",
      "<S-F6>",
      "<A-CR>",
    }) do
      assert_true(buf_map("n", lhs), lhs .. " not mapped in buffer")
    end
    assert_true(buf_map("x", "<F4>"), "<F4> not mapped in visual mode")
    assert_eq(buf_map("n", "gd").desc, "LSP: Go to definition", "gd desc")
    -- gi/go would shadow builtins, <F3> would bypass conform, gr is left to
    -- the built-in grr/grn/gra/gri defaults, gl is a global diagnostic map
    for _, lhs in ipairs({ "gi", "go", "<F3>", "gr", "gl" }) do
      assert_true(not buf_map("n", lhs), lhs .. " should not be mapped in buffer")
    end
    -- Stopping the only client removes the maps again
    h.stop_client(client)
    assert_eq(#vim.lsp.get_clients({ bufnr = bufnr }), 0, "lua_ls still attached")
    h.assert_no_message_errors("after lua_ls stopped")
    for _, lhs in ipairs({ "gd", "<leader>ca", "<D-b>" }) do
      assert_true(not buf_map("n", lhs), lhs .. " still mapped in buffer after lua_ls stopped")
    end
  end)
else
  skip("lua_ls runtime attach", "lua-language-server not installed")
end

-- The clangd config runs plain "clangd", which resolves to Mason's copy
-- because mason.setup() puts mason/bin first on PATH. Only test that one, not
-- whatever else is on PATH (e.g. Apple's /usr/bin/clangd on macOS).
if vim.fn.executable(mason_bin .. "clangd") == 1 then
  test("clangd attaches with fallback style and formats on save", function()
    local path = tmp .. "/c/m.c"
    local client = attach(path, { "int main(){return 0;}" }, "clangd")
    assert_not_nil(client, "clangd did not attach")
    local cmd = client.config.cmd
    assert_true(type(cmd) == "table" and vim.tbl_contains(cmd, "--fallback-style=LLVM"), vim.inspect(cmd))
    assert_eq(vim.fn.exepath("clangd"), mason_bin .. "clangd", "clangd on PATH")
    vim.wait(1000)
    vim.cmd("silent write")
    assert_eq(vim.fn.readfile(path)[1], "int main() { return 0; }", "file not formatted on save")
    h.stop_client(client)
    assert_eq(vim.lsp.get_client_by_id(client.id), nil, "clangd still running")
    h.assert_no_message_errors("after clangd stopped")
  end)
else
  skip("clangd runtime attach", "Mason clangd not installed")
end

-- kotlin_lsp's cmd runs plain "intellij-server", which must resolve to
-- Mason's copy in the same way. The smoke test checks that it attaches.
if vim.fn.executable(mason_bin .. "intellij-server") == 1 then
  test("intellij-server on PATH is Mason's kotlin-lsp", function()
    assert_eq(vim.fn.exepath("intellij-server"), mason_bin .. "intellij-server", "intellij-server on PATH")
  end)
else
  skip("kotlin-lsp on PATH", "Mason kotlin-lsp not installed")
end

vim.fn.delete(tmp, "rf")
for _, dir in ipairs(created_dirs) do
  vim.fn.delete(dir, "rf")
end

h.finish()

-- LSP and completion tests
-- Run with: nvim --headless -c "luafile tests/lsp_test.lua"

local failed = 0
local passed = 0
local skipped = 0

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

local function skip(name, reason)
  print("- " .. name .. " (skipped: " .. reason .. ")")
  skipped = skipped + 1
end

local function assert_true(val, msg)
  if not val then error(msg or "expected true", 2) end
end

local function assert_not_nil(val, msg)
  if val == nil then error(msg or "expected non-nil", 2) end
end

local function assert_eq(a, b, msg)
  if a ~= b then error((msg or "values differ") .. ": " .. vim.inspect(a) .. " ~= " .. vim.inspect(b), 2) end
end

-- Call a config's cmd function with vim.lsp.rpc.start stubbed out, and return
-- the argv it would have spawned
local function resolve_cmd(cmd, root_dir)
  if type(cmd) == "table" then return cmd end
  local captured
  local orig = vim.lsp.rpc.start
  vim.lsp.rpc.start = function(argv) captured = argv; return {} end
  local ok, err = pcall(cmd, {}, { root_dir = root_dir })
  vim.lsp.rpc.start = orig
  if not ok then error(err) end
  return captured
end

local function has_arg(argv, pattern)
  for _, a in ipairs(argv or {}) do
    if a:find(pattern) then return true end
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

-- Wait for lazy to finish loading
vim.wait(3000, function()
  return require("lazy").stats().loaded > 0
end)

local tmp = vim.fn.tempname()
-- Unique project names, so the per-root cache dirs created below can be removed again
local proj = "lsp-test-" .. vim.fn.getpid()
local created_dirs = {}
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"

print("\n=== LSP Config Tests ===\n")

test("lsp-zero is not installed as a plugin", function()
  assert_true(require("lazy.core.config").plugins["lsp-zero.nvim"] == nil, "lsp-zero.nvim still in spec")
end)

test("cmp capabilities applied to all servers", function()
  local caps = vim.lsp.config["*"].capabilities
  assert_not_nil(caps, "no global capabilities")
  local expected = require("cmp_nvim_lsp").default_capabilities().textDocument.completion
  assert_true(vim.deep_equal(caps.textDocument.completion, expected),
    "completion capabilities differ from cmp_nvim_lsp: " .. vim.inspect(caps.textDocument.completion))
end)

test("lua_ls has diagnostics.globals = { 'vim' }", function()
  local globals = vim.tbl_get(vim.lsp.config.lua_ls, "settings", "Lua", "diagnostics", "globals")
  assert_true(globals and vim.tbl_contains(globals, "vim"), "vim not in globals")
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
  assert_true(vim.tbl_get(vim.lsp.config.jdtls, "settings", "java", "configuration", "runtimes") == nil,
    "runtimes still configured")
end)

test("kotlin_lsp config exists with kotlin filetype", function()
  local cfg = vim.lsp.config.kotlin_lsp
  assert_not_nil(cfg, "kotlin_lsp not configured")
  assert_true(vim.tbl_contains(cfg.filetypes or {}, "kotlin"), "kotlin not in filetypes")
  assert_true(vim.tbl_contains(cfg.root_markers or {}, "settings.gradle.kts"), "settings.gradle.kts not a root marker")
end)

test("kotlin_lsp cmd uses external binary and per-root --system-path", function()
  local paths = require("core.paths")
  local root = tmp .. "/" .. proj .. "-kt"
  table.insert(created_dirs, cache_dir(paths.lsp_cache.kotlin_lsp, root))
  local argv = resolve_cmd(vim.lsp.config.kotlin_lsp.cmd, root)
  assert_eq(argv[1], paths.external.kotlin_lsp, "binary")
  assert_true(vim.tbl_contains(argv, "--stdio"), "no --stdio")
  assert_eq(argv[vim.fn.index(argv, "--system-path") + 2], cache_dir(paths.lsp_cache.kotlin_lsp, root), "--system-path")
end)

print("\n=== Completion Tests ===\n")

test("cmp has nvim_lsp, luasnip and buffer sources", function()
  local names = vim.tbl_map(function(s) return s.name end, require("cmp").get_config().sources)
  for _, want in ipairs({ "nvim_lsp", "luasnip", "buffer" }) do
    assert_true(vim.tbl_contains(names, want), want .. " not in " .. vim.inspect(names))
  end
end)

test("cmp-buffer and cmp_luasnip are installed", function()
  assert_not_nil(require("cmp_buffer"), "cmp_buffer missing")
  assert_not_nil(require("cmp_luasnip"), "cmp_luasnip missing")
end)

test("cmp expands snippets with LuaSnip", function()
  local ls = require("luasnip")
  local called = false
  local orig = ls.lsp_expand
  ls.lsp_expand = function() called = true end
  local ok, err = pcall(require("cmp").get_config().snippet.expand, { body = "x$0" })
  ls.lsp_expand = orig
  assert_true(ok, tostring(err))
  assert_true(called, "luasnip.lsp_expand not called")
end)

test("cmp keeps existing mappings", function()
  local mapping = require("cmp").get_config().mapping
  for _, key in ipairs({ "<C-Space>", "<Tab>", "<S-Tab>", "<CR>", "<C-U>", "<C-D>" }) do
    assert_not_nil(mapping[key], key .. " not mapped")
  end
end)

print("\n=== LSP Runtime Tests ===\n")

if vim.fn.executable(mason_bin .. "lua-language-server") == 1 then
  test("lua_ls attaches with globals and buffer keymaps", function()
    local client, bufnr = attach(tmp .. "/lua/t.lua", { "vim.print(1)" }, "lua_ls")
    assert_not_nil(client, "lua_ls did not attach")
    local globals = vim.tbl_get(client.config.settings, "Lua", "diagnostics", "globals")
    assert_true(globals and vim.tbl_contains(globals, "vim"), "running client lacks globals")
    assert_not_nil(vim.tbl_get(client.config.capabilities, "textDocument", "completion", "completionItem", "resolveSupport"),
      "running client lacks cmp capabilities")

    -- maparg() on the current buffer prefers buffer-local maps and normalizes
    -- keys like <D-A-b>, so .buffer == 1 means the map is buffer-local
    assert_eq(vim.api.nvim_get_current_buf(), bufnr, "current buffer")
    local function buf_map(mode, lhs)
      local m = vim.fn.maparg(lhs, mode, false, true)
      return m.buffer == 1 and m or nil
    end
    for _, lhs in ipairs({ "<leader>ca", "gs", "<F2>", "<F4>", "gd", "gD", "gI", "gy",
                           "<D-b>", "<D-A-b>", "<A-F7>", "<S-F6>", "<A-CR>" }) do
      assert_true(buf_map("n", lhs), lhs .. " not mapped in buffer")
    end
    assert_true(buf_map("x", "<F4>"), "<F4> not mapped in visual mode")
    assert_eq(buf_map("n", "gd").desc, "LSP: Go to definition", "gd desc")
    -- gi/go would shadow builtins, <F3> would bypass conform, gr is left to
    -- the built-in grr/grn/gra/gri defaults, gl is a global diagnostic map
    for _, lhs in ipairs({ "gi", "go", "<F3>", "gr", "gl" }) do
      assert_true(not buf_map("n", lhs), lhs .. " should not be mapped in buffer")
    end
    -- Format-on-save is only for hls and clangd
    local ok = pcall(vim.api.nvim_get_autocmds, { group = "user_lsp_format_" .. bufnr })
    assert_true(not ok, "lua buffer got an LSP format-on-save autocmd")
    vim.lsp.stop_client(client.id, true)
  end)
else
  skip("lua_ls runtime attach", "lua-language-server not installed")
end

if vim.fn.executable(mason_bin .. "clangd") == 1 or vim.fn.executable("clangd") == 1 then
  test("clangd attaches with fallback style and formats on save", function()
    local path = tmp .. "/c/m.c"
    local client = attach(path, { "int main(){return 0;}" }, "clangd")
    assert_not_nil(client, "clangd did not attach")
    assert_true(vim.tbl_contains(client.config.cmd, "--fallback-style=LLVM"), vim.inspect(client.config.cmd))
    vim.wait(1000)
    vim.cmd("silent write")
    assert_eq(vim.fn.readfile(path)[1], "int main() { return 0; }", "file not formatted on save")
    vim.lsp.stop_client(client.id, true)
  end)
else
  skip("clangd runtime attach", "clangd not installed")
end

-- Summary
print("\n=== Results ===")
print(string.format("Passed: %d, Failed: %d, Skipped: %d", passed, failed, skipped))

for _, c in ipairs(vim.lsp.get_clients()) do
  c:stop(true)
end
vim.fn.delete(tmp, "rf")
for _, dir in ipairs(created_dirs) do
  vim.fn.delete(dir, "rf")
end

if failed > 0 then
  vim.cmd("cq 1")  -- Exit with error code
else
  vim.cmd("qa!")
end

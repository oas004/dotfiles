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

test("conform is loaded", function()
  assert_true(package.loaded["conform"] ~= nil, "conform not loaded at startup")
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

for _, ft in ipairs({ "java", "rust" }) do
  test("format_on_save returns options for " .. ft, function()
    local buf = scratch(ft)
    local res = format_on_save_fn()(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert_true(type(res) == "table", "expected table, got " .. vim.inspect(res))
    assert_true(not res.async, "format_on_save must be synchronous")
  end)
end

for _, ft in ipairs({ "kotlin", "haskell", "c", "cpp", "json", "lua" }) do
  test("format_on_save returns nil for " .. ft, function()
    local buf = scratch(ft)
    local res = format_on_save_fn()(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    assert_eq(res, nil, ft)
  end)
end

test("<leader>fm is mapped in normal mode", function()
  local map = vim.fn.maparg("<leader>fm", "n", false, true)
  assert_true(not vim.tbl_isempty(map), "<leader>fm not mapped")
  assert_true(map.callback ~= nil, "<leader>fm has no Lua callback")
end)

test(":KotlinFormat and :JavaFormat exist", function()
  local cmds = vim.api.nvim_get_commands({})
  assert_true(cmds.KotlinFormat ~= nil, "KotlinFormat missing")
  assert_true(cmds.JavaFormat ~= nil, "JavaFormat missing")
end)

test("none-ls is not configured", function()
  assert_true(require("lazy.core.config").plugins["none-ls.nvim"] == nil, "none-ls still in spec")
end)


-- Summary
print("\n=== Results ===")
print(string.format("Passed: %d, Failed: %d", passed, failed))

if failed > 0 then
  vim.cmd("cq 1")  -- Exit with error code
else
  vim.cmd("qa!")
end

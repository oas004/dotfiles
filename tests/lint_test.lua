-- Linter tests: lua/plugins/lint.lua (nvim-lint with detekt, shellcheck and
-- selene). Checks that need a linter binary are skipped when it isn't
-- installed (Mason installs all three, see vim.g.mason_tools).
-- Run with: nvim --headless -c "luafile tests/lint_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, skip, assert_true, assert_eq = h.test, h.skip, h.assert_true, h.assert_eq

h.wait_for_lazy()

-- Only linting is under test, so keep language servers out of the sample files
vim.lsp.enable({ "kotlin_lsp", "lua_ls", "gradle_ls" }, false)

local tmpdir = vim.fn.tempname()

---@param rel string path below tmpdir
---@param lines string[]
---@return string path
local function write(rel, lines)
  local path = tmpdir .. "/" .. rel
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  return path
end

local function open(path)
  vim.cmd("silent edit " .. vim.fn.fnameescape(path))
  return vim.api.nvim_get_current_buf()
end

---@param buf integer
---@param linter string
---@return vim.Diagnostic[]
local function diagnostics(buf, linter)
  return vim.diagnostic.get(buf, { namespace = require("lint").get_namespace(linter) })
end

---@param buf integer
---@param linter string
---@param ms integer
---@param pred? fun(diags: vim.Diagnostic[]): boolean
---@return vim.Diagnostic[]
local function wait_for(buf, linter, ms, pred)
  pred = pred or function(d)
    return #d > 0
  end
  vim.wait(ms, function()
    return pred(diagnostics(buf, linter))
  end, 50)
  return diagnostics(buf, linter)
end

local function codes(diags)
  local list = vim.tbl_map(function(d)
    return d.code
  end, diags)
  table.sort(list)
  return list
end

h.out("\n=== Lint Tests ===\n")

test("nvim-lint is not loaded at startup or for files without a linter", function()
  assert_eq(package.loaded["lint"], nil, "lint module at startup")
  open(write("notes.txt", { "hello" }))
  assert_eq(package.loaded["lint"], nil, "lint module after opening a .txt file")
end)

-- Every try_lint call from here on, as "<linter> <cwd>"
local calls = {}
local lint = require("lint")
local orig_try_lint = lint.try_lint
---@diagnostic disable-next-line: duplicate-set-field
lint.try_lint = function(names, opts)
  table.insert(calls, tostring(names) .. " " .. tostring(opts and opts.cwd))
  return orig_try_lint(names, opts)
end

local function calls_for(linter)
  return vim.tbl_filter(function(c)
    return vim.startswith(c, linter .. " ")
  end, calls)
end

-- Leave insert mode in buf, which fires InsertLeave
local function insert_leave()
  vim.api.nvim_feedkeys(vim.keycode("i<Esc>"), "x", false)
end

if vim.fn.executable("shellcheck") == 1 then
  local sh = write("scripts/run.sh", { "#!/bin/sh", "echo $1" })

  test("shellcheck reports problems in a shell script when it is opened", function()
    local buf = open(sh)
    assert_eq(vim.bo[buf].filetype, "sh", "filetype")
    local diags = wait_for(buf, "shellcheck", 10000)
    assert_eq(codes(diags), { 2086 }, "shellcheck codes")
    assert_eq(diags[1].lnum, 1, "line of the unquoted $1")
  end)

  test("shellcheck runs on save but not on InsertLeave", function()
    local buf = open(sh)
    calls = {}
    insert_leave()
    assert_eq(calls_for("shellcheck"), {}, "calls on InsertLeave")
    vim.api.nvim_buf_set_lines(buf, 1, 2, false, { 'echo "$1"' })
    vim.cmd("silent write")
    assert_eq(#calls_for("shellcheck"), 1, "calls on save")
    local diags = wait_for(buf, "shellcheck", 10000, function(d)
      return #d == 0
    end)
    assert_eq(codes(diags), {}, "shellcheck codes after fixing the quoting")
  end)

  test("setting the filetype to bash lints the buffer", function()
    local buf = open(write("scripts/no-extension", { "echo $1" }))
    assert_eq(diagnostics(buf, "shellcheck"), {}, "diagnostics before :set filetype")
    vim.bo[buf].filetype = "bash"
    assert_eq(codes(wait_for(buf, "shellcheck", 10000)), { 2086, 2148 }, "shellcheck codes")
  end)
else
  skip("shellcheck", "shellcheck not installed")
end

if vim.fn.executable("selene") == 1 then
  local with_config = write("selene-project/init.lua", { "local unused = 1" })
  write("selene-project/selene.toml", { 'std = "lua51"' })
  local without_config = write("plain/init.lua", { "local unused = 1" })

  test("selene lints Lua files in a project with a selene.toml", function()
    calls = {}
    local buf = open(with_config)
    local diags = wait_for(buf, "selene", 10000)
    assert_eq(codes(diags), { "unused_variable" }, "selene codes")
    local root = vim.uv.fs_realpath(vim.fs.dirname(with_config))
    local got = vim.tbl_map(function(c)
      return "selene " .. vim.uv.fs_realpath(c:sub(#"selene " + 1))
    end, calls_for("selene"))
    assert_eq(got, { "selene " .. root }, "selene runs from the selene.toml directory")
  end)

  test("selene lints the unsaved buffer on InsertLeave", function()
    local buf = open(with_config)
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "local also_unused = 2" })
    insert_leave()
    local diags = wait_for(buf, "selene", 10000, function(d)
      return #d == 2
    end)
    assert_eq(#diags, 2, "selene diagnostics after adding an unused variable")
    assert_true(vim.bo[buf].modified, "buffer was saved")
    vim.cmd("silent edit!")
  end)

  test("selene doesn't run without a selene.toml", function()
    calls = {}
    local buf = open(without_config)
    insert_leave()
    vim.cmd("silent write")
    assert_eq(calls_for("selene"), {}, "selene calls")
    assert_eq(diagnostics(buf, "selene"), {}, "selene diagnostics")
  end)
else
  skip("selene", "selene not installed")
end

-- A Gradle project with a Kotlin file that has three detekt findings
local kt = write("gradle-app/app/src/main/kotlin/sample/Sample.kt", {
  "package sample", -- 1
  "", -- 2
  "class Sample {", -- 3
  "    fun magic(x: Int): Int = x * 42", -- 4
  "", -- 5
  "    fun empty() {", -- 6
  "    }", -- 7
  "}", -- 8
})
local gradle_root = tmpdir .. "/gradle-app"
write("gradle-app/settings.gradle.kts", { 'rootProject.name = "app"' })

test("detekt analyses only the buffer's file, from the Gradle project root", function()
  local buf = open(kt)
  local def = lint.linters.detekt()
  assert_eq(def.args, { "--input", vim.api.nvim_buf_get_name(buf) }, "args without project config")
  assert_eq(def.cwd, vim.uv.fs_realpath(gradle_root), "cwd")
  assert_eq(def.stdin, false, "stdin")
  assert_eq(def.append_fname, false, "append_fname")
end)

test("detekt uses the project's config and baseline", function()
  local config = write("gradle-app/config/detekt/detekt.yml", { "style:", "  MagicNumber:", "    active: false" })
  local baseline = write("gradle-app/config/detekt/baseline.xml", { "<SmellBaseline/>" })
  local buf = open(kt)
  local def = lint.linters.detekt()
  local root = vim.uv.fs_realpath(gradle_root)
  assert_eq(def.args, {
    "--input",
    vim.api.nvim_buf_get_name(buf),
    "--config",
    root .. "/config/detekt/detekt.yml",
    "--build-upon-default-config",
    "--baseline",
    root .. "/config/detekt/baseline.xml",
  }, "args with project config")
  vim.fn.delete(config)
  vim.fn.delete(baseline)
end)

test("detekt's parser reads its console output", function()
  open(kt)
  local output = table.concat({
    "/x/Sample.kt:4:34: This expression contains a magic number. Consider defining it to a well named constant. [MagicNumber]",
    "/x/Sample.kt:6:17: This empty block of code can be removed. [EmptyFunctionBlock]",
    "",
    "Analysis failed with 2 weighted issues.",
  }, "\n")
  local diags = lint.linters.detekt().parser(output, vim.api.nvim_get_current_buf(), "/x")
  assert_eq(#diags, 2, "diagnostics")
  assert_eq({ diags[1].lnum, diags[1].col, diags[1].code }, { 3, 33, "MagicNumber" }, "first diagnostic")
  assert_eq(diags[2].source, "detekt", "source")
  assert_eq(diags[2].severity, vim.diagnostic.severity.WARN, "severity")
end)

if vim.fn.executable("detekt") == 1 and vim.fn.executable("java") == 1 then
  test("detekt reports findings on open, and honours the project config on save", function()
    calls = {}
    local buf = open(kt)
    local start = vim.uv.now()
    local diags = wait_for(buf, "detekt", 60000)
    h.out(("  (detekt took %d ms)"):format(vim.uv.now() - start))
    assert_eq(codes(diags), { "EmptyFunctionBlock", "MagicNumber" }, "detekt codes")
    local magic = vim.tbl_filter(function(d)
      return d.code == "MagicNumber"
    end, diags)[1]
    assert_eq(magic.lnum, 3, "MagicNumber line")

    insert_leave()
    assert_eq(#calls_for("detekt"), 1, "detekt calls after InsertLeave")

    local config = write("gradle-app/config/detekt/detekt.yml", { "style:", "  MagicNumber:", "    active: false" })
    vim.cmd("silent write")
    diags = wait_for(buf, "detekt", 60000, function(d)
      return #d == 1
    end)
    assert_eq(codes(diags), { "EmptyFunctionBlock" }, "detekt codes with MagicNumber turned off")
    vim.fn.delete(config)
  end)
else
  skip("detekt run", "detekt or java not installed")
end

test("missing linters are skipped without messages", function()
  -- Only git on PATH (gitsigns needs it). Not /usr/bin: CI runners have
  -- shellcheck preinstalled there.
  local bin = tmpdir .. "/git-only-bin"
  vim.fn.mkdir(bin, "p")
  vim.uv.fs_symlink(vim.fn.exepath("git"), bin .. "/git")
  local path = vim.env.PATH
  vim.env.PATH = bin
  local ok, err = pcall(function()
    calls = {}
    vim.cmd("messages clear")
    for _, file in ipairs({
      write("missing/run.sh", { "#!/bin/sh", "echo $1" }),
      kt,
      write("missing/selene.toml", { 'std = "lua51"' }) and write("missing/init.lua", { "local unused = 1" }),
    }) do
      open(file)
      vim.cmd("silent write")
    end
    assert_eq(calls, {}, "try_lint calls without linters on PATH")
    h.assert_no_message_errors()
  end)
  vim.env.PATH = path
  assert_true(ok, err)
end)

vim.cmd("enew")
vim.fn.delete(tmpdir, "rf")

h.finish()

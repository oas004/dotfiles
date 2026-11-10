-- Tests for lua/core/package-manager.lua: lazy.nvim is bootstrapped at the
-- commit in lazy-lock.json. Each case starts a child nvim with an empty temp
-- data dir, so it clones lazy.nvim from GitHub.
-- Run with: NVIM_APPNAME=<appname> nvim --headless -c "luafile tests/package_manager_test.lua"

local failed = 0
local passed = 0

local function out(line)
  io.stdout:write(line .. "\n")
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    out("✓ " .. name)
    passed = passed + 1
  else
    out("✗ " .. name .. ": " .. tostring(err))
    failed = failed + 1
  end
end

local function assert_eq(expected, actual, msg)
  if expected ~= actual then
    error(string.format("%s: expected %s, got %s", msg or "mismatch", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local config_dir = vim.fn.stdpath("config")
local package_manager = config_dir .. "/lua/core/package-manager.lua"
local tmp = vim.fn.tempname()

-- Stands in for lazy.nvim's module in the child, so lazy.setup() doesn't
-- install every plugin into the temp dir. Only the bootstrap is under test.
local stub = "lua package.preload.lazy = function() return { setup = function() end } end"

-- A lazy.nvim commit older than the stable tag (v11.17.4), and one that is on
-- no branch at all (the head of folke/lazy.nvim pull request #1), which the
-- clone doesn't contain.
local OLD_COMMIT = "e6a8824858757ca9cd4f5ae1a72d845fa5c46a39"
local PR_COMMIT = "177cef104c823ec5453ca3d58a25e1c37490f2e3"

local function git(dir, ...)
  local res = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
  assert(res.code == 0, "git " .. table.concat({ ... }, " ") .. " failed: " .. (res.stderr or ""))
  return vim.trim(res.stdout)
end

--- Start a child nvim with empty data/state/cache dirs under tmp/<name> and
--- return its stdpath("data") and stderr. env is added to the child's
--- environment (LAZY is removed unless env sets it). args go before +qa!.
local function start(name, env, args)
  local base = tmp .. "/" .. name
  local child_env = vim.fn.environ()
  child_env.LAZY = nil
  child_env = vim.tbl_extend("force", child_env, {
    XDG_DATA_HOME = base .. "/data",
    XDG_STATE_HOME = base .. "/state",
    XDG_CACHE_HOME = base .. "/cache",
  }, env or {})
  local cmd = { vim.v.progpath, "--headless", "--cmd", stub }
  vim.list_extend(cmd, args or {})
  vim.list_extend(cmd, { "-c", "lua io.stdout:write(vim.fn.stdpath('data'))", "+qa!" })
  local res = vim.system(cmd, { env = child_env, clear_env = true, text = true }):wait(120000)
  assert_eq(0, res.code, "child nvim exit code (stderr: " .. (res.stderr or "") .. ")")
  return res.stdout, res.stderr
end

--- Start a child nvim that only runs package-manager.lua, with a config dir
--- of its own whose lazy-lock.json contains lockfile (none if nil). env and
--- args are passed on to start(), args after package-manager.lua.
local function start_with_lockfile(name, lockfile, env, args)
  local config_home = tmp .. "/" .. name .. "/config"
  vim.fn.mkdir(config_home .. "/nvim", "p")
  if lockfile then
    vim.fn.writefile(vim.split(lockfile, "\n"), config_home .. "/nvim/lazy-lock.json")
  end
  env = vim.tbl_extend("force", { XDG_CONFIG_HOME = config_home, NVIM_APPNAME = "nvim" }, env or {})
  return start(name, env, vim.list_extend({ "-u", "NONE", "-c", "luafile " .. package_manager }, args or {}))
end

local function lock_with(commit)
  return vim.json.encode({ ["lazy.nvim"] = { branch = "main", commit = commit } })
end

local function lazy_head(data)
  return git(data .. "/lazy/lazy.nvim", "rev-parse", "HEAD")
end

local function stable(data)
  return git(data .. "/lazy/lazy.nvim", "rev-parse", "stable^{commit}")
end

out("\n=== Package Manager Tests ===\n")

test("starting this config clones lazy.nvim at its lazy-lock.json commit", function()
  local lock = vim.json.decode(table.concat(vim.fn.readfile(config_dir .. "/lazy-lock.json"), "\n"))
  local data = start("config")
  assert_eq(lock["lazy.nvim"].commit, lazy_head(data), "lazy.nvim HEAD")
end)

test("a locked commit older than stable is checked out", function()
  local data = start_with_lockfile("old", lock_with(OLD_COMMIT))
  assert_eq(OLD_COMMIT, lazy_head(data), "lazy.nvim HEAD")
end)

test("a locked commit that is on no branch is fetched", function()
  local data = start_with_lockfile("pr", lock_with(PR_COMMIT))
  assert_eq(PR_COMMIT, lazy_head(data), "lazy.nvim HEAD")
end)

test("no lockfile stays on stable", function()
  local data = start_with_lockfile("missing", nil)
  assert_eq(stable(data), lazy_head(data), "lazy.nvim HEAD")
end)

test("an invalid lockfile stays on stable", function()
  local data = start_with_lockfile("invalid", "{ not json")
  assert_eq(stable(data), lazy_head(data), "lazy.nvim HEAD")
end)

test("a lockfile without lazy.nvim stays on stable", function()
  local data = start_with_lockfile("no-entry", vim.json.encode({ ["other.nvim"] = { commit = OLD_COMMIT } }))
  assert_eq(stable(data), lazy_head(data), "lazy.nvim HEAD")
end)

test("a locked commit that doesn't exist warns and stays on stable", function()
  local data, stderr = start_with_lockfile("bogus", lock_with(string.rep("0", 39) .. "1"))
  assert_eq(stable(data), lazy_head(data), "lazy.nvim HEAD")
  assert(stderr:find("Failed to check out lazy.nvim", 1, true), "no warning in stderr: " .. stderr)
end)

test("$LAZY is used instead of cloning", function()
  local lazy = tmp .. "/lazy-checkout"
  local stdout = start_with_lockfile("env", lock_with(OLD_COMMIT), { LAZY = lazy }, {
    "-c", "lua io.stdout:write(vim.o.rtp .. '\\n')",
  })
  local rtp, data = unpack(vim.split(stdout, "\n"))
  assert(vim.uv.fs_stat(data .. "/lazy/lazy.nvim") == nil, "lazy.nvim was cloned although $LAZY is set")
  assert_eq(lazy, vim.split(rtp, ",")[1], "first runtimepath entry")
end)

vim.fn.delete(tmp, "rf")

out("\n=== Results ===")
out(string.format("Passed: %d, Failed: %d", passed, failed))
if failed > 0 then
  vim.cmd("cq 1")
else
  vim.cmd("qa!")
end

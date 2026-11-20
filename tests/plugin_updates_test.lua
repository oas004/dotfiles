-- Tests for plugin updates (#41): the lazy.nvim update checker is off, and
-- scripts/plugins.sh (make update / make restore) does what it says. The
-- script runs in a temporary git repo with a stub nvim and a stub
-- tests/run.sh, so no real plugin is updated.
-- Run with: nvim --headless -c "luafile tests/plugin_updates_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

local root = vim.fn.resolve(vim.fn.stdpath("config"))

h.out("\n=== Plugin Update Tests ===\n")

test("lazy.nvim's update checker is off", function()
  assert_eq(require("lazy.core.config").options.checker.enabled, false, "checker.enabled")
end)

-- make prints the commands of a target with -n
local function make_n(target, env)
  local res = vim.system({ "make", "-n", target }, { cwd = root, text = true, env = env }):wait()
  assert_eq(res.code, 0, "make -n " .. target .. ": " .. (res.stderr or ""))
  return vim.trim(res.stdout)
end

test("make update and make restore run scripts/plugins.sh", function()
  assert_eq(make_n("update"), "scripts/plugins.sh update", "make -n update")
  assert_eq(make_n("restore"), "scripts/plugins.sh restore", "make -n restore")
end)

test("only make lint sets VIMRUNTIME", function()
  -- nvim sets $VIMRUNTIME for its child processes, so start from a clean env
  local probe = vim.fn.tempname() .. ".mk"
  vim.fn.writefile({
    "include Makefile",
    "probe:",
    '\t@echo "[$${VIMRUNTIME:-}]"',
  }, probe)
  local res = vim
    .system({ "make", "-s", "-f", probe, "probe" }, {
      cwd = root,
      text = true,
      clear_env = true,
      env = { PATH = vim.env.PATH, HOME = vim.env.HOME },
    })
    :wait()
  vim.fn.delete(probe)
  assert_eq(vim.trim(res.stdout or ""), "[]", "VIMRUNTIME in a non-lint target")
  local lint = make_n("lint", { VIMRUNTIME = "/some/runtime" })
  assert_true(
    lint:find('VIMRUNTIME="/some/runtime" lua-language-server', 1, true) ~= nil,
    "lint does not pass VIMRUNTIME to lua-language-server:\n" .. lint
  )
end)

-- A temporary git repo with scripts/plugins.sh, a lockfile and a stub
-- tests/run.sh, plus a stub nvim. The stub answers the script's
-- stdpath("config") and has("nvim-0.12") probes from STUB_CONFIG and
-- STUB_012, logs every other call to STUB_LOG, and on ":Lazy! update" moves
-- alpha.nvim and nvim-treesitter to new commits in the lockfile, the way
-- lazy does (nvim-treesitter only moves on 0.12, where it isn't pinned).
local LOCK = {
  "{",
  '  "alpha.nvim": { "branch": "main", "commit": "aaaa" },',
  '  "nvim-treesitter": { "branch": "main", "commit": "pin0" },',
  '  "zeta.nvim": { "branch": "main", "commit": "zzzz" }',
  "}",
}

local STUB_NVIM = [=[#!/usr/bin/env bash
args="$*"
case "$args" in
  *'stdpath("config")'*) printf '%s' "$STUB_CONFIG"; exit 0 ;;
  *'has("nvim-0.12")'*) printf '%s' "$STUB_012"; exit 0 ;;
esac
printf '%s\n' "$args" >>"$STUB_LOG"
lock="$STUB_CONFIG/lazy-lock.json"
case "$args" in
  *'+Lazy! update nvim-treesitter'*)
    sed -i.bak 's/"commit": "pin0"/"commit": "head"/' "$lock" && rm -f "$lock.bak" ;;
  *'+Lazy! update'*)
    sed -i.bak 's/"commit": "aaaa"/"commit": "bbbb"/' "$lock" && rm -f "$lock.bak"
    if [ "$STUB_012" = 1 ]; then
      sed -i.bak 's/"commit": "pin0"/"commit": "head"/' "$lock" && rm -f "$lock.bak"
    fi ;;
esac
exit 0
]=]

local function git(repo, ...)
  local res = vim.system({ "git", "-C", repo, ... }, { text = true }):wait()
  assert_eq(res.code, 0, "git " .. table.concat({ ... }, " ") .. ": " .. (res.stderr or ""))
  return res.stdout
end

local function make_repo()
  local repo = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(repo .. "/scripts", "p")
  vim.fn.mkdir(repo .. "/tests", "p")
  vim.fn.writefile(vim.fn.readfile(root .. "/scripts/plugins.sh"), repo .. "/scripts/plugins.sh")
  vim.fn.writefile(LOCK, repo .. "/lazy-lock.json")
  vim.fn.writefile(
    { "#!/usr/bin/env bash", 'echo "stub tests ran"', 'exit "${STUB_TESTS_RC:-0}"' },
    repo .. "/tests/run.sh"
  )
  vim.fn.setfperm(repo .. "/tests/run.sh", "rwxr-xr-x")
  local stub = repo .. "/stub-nvim"
  vim.fn.writefile(vim.split(STUB_NVIM, "\n"), stub)
  vim.fn.setfperm(stub, "rwxr-xr-x")
  git(repo, "init", "-q")
  git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "add", ".")
  git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
  return repo
end

---@return { code: integer, out: string, calls: string[], lock: string[] }
local function run_script(repo, cmd, opts)
  opts = opts or {}
  local log = repo .. "/nvim-calls.log"
  vim.fn.delete(log)
  local res = vim
    .system({ "bash", repo .. "/scripts/plugins.sh", cmd }, {
      text = true,
      env = {
        NVIM = repo .. "/stub-nvim",
        STUB_CONFIG = opts.config or repo,
        STUB_012 = opts.nvim_012 and "1" or "0",
        STUB_LOG = log,
        STUB_TESTS_RC = tostring(opts.tests_rc or 0),
      },
    })
    :wait(30000)
  return {
    code = res.code,
    out = (res.stdout or "") .. (res.stderr or ""),
    calls = vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {},
    lock = vim.fn.readfile(repo .. "/lazy-lock.json"),
  }
end

local function called(calls, needle)
  for _, c in ipairs(calls) do
    if c:find(needle, 1, true) then
      return true
    end
  end
  return false
end

local function ts_commit(lock)
  for _, l in ipairs(lock) do
    local commit = l:match('^  "nvim%-treesitter": .*"commit": "(%w+)"')
    if commit then
      return commit
    end
  end
end

for _, v in ipairs({ { "0.11", false }, { "0.12", true } }) do
  local name, nvim_012 = v[1], v[2]

  test(name .. ": update updates, tests and shows the lockfile diff without committing", function()
    local repo = make_repo()
    local r = run_script(repo, "update", { nvim_012 = nvim_012 })
    assert_eq(r.code, 0, "exit code; output:\n" .. r.out)
    assert_true(called(r.calls, "+Lazy! update"), "no :Lazy! update: " .. vim.inspect(r.calls))
    assert_true(called(r.calls, "ts.update(vim.g.treesitter_parsers)"), "parsers not updated before quitting")
    assert_true(r.out:find("stub tests ran", 1, true) ~= nil, "tests/run.sh not run")
    assert_true(
      r.out:find('+  "alpha.nvim": { "branch": "main", "commit": "bbbb" },', 1, true) ~= nil,
      "no diff:\n" .. r.out
    )
    assert_true(r.out:find("Tests passed", 1, true) ~= nil, "no result message")
    assert_eq(r.lock[2], '  "alpha.nvim": { "branch": "main", "commit": "bbbb" },', "updated entry")
    assert_eq(ts_commit(r.lock), "pin0", "nvim-treesitter entry")
    assert_true(git(repo, "status", "--porcelain", "lazy-lock.json") ~= "", "lockfile was committed")
    assert_eq(vim.trim(git(repo, "rev-list", "--count", "HEAD")), "1", "commits")
    vim.fn.delete(repo, "rf")
  end)

  test(
    name .. ": restore restores" .. (nvim_012 and ", moves nvim-treesitter to main, keeps its entry" or ""),
    function()
      local repo = make_repo()
      local r = run_script(repo, "restore", { nvim_012 = nvim_012 })
      assert_eq(r.code, 0, "exit code; output:\n" .. r.out)
      assert_true(called(r.calls, "+Lazy! restore"), "no :Lazy! restore: " .. vim.inspect(r.calls))
      assert_eq(called(r.calls, "+Lazy! update nvim-treesitter"), nvim_012, ":Lazy! update nvim-treesitter")
      assert_eq(r.lock, LOCK, "lockfile")
      vim.fn.delete(repo, "rf")
    end
  )
end

test("update exits non-zero when the tests fail, and says how to go back", function()
  local repo = make_repo()
  local r = run_script(repo, "update", { tests_rc = 1 })
  assert_true(r.code ~= 0, "exit code 0")
  assert_true(r.out:find("git checkout -- lazy-lock.json && make restore", 1, true) ~= nil, "no hint:\n" .. r.out)
  vim.fn.delete(repo, "rf")
end)

test("update refuses to start when lazy-lock.json has uncommitted changes", function()
  local repo = make_repo()
  local lock = vim.deepcopy(LOCK)
  lock[4] = '  "zeta.nvim": { "branch": "main", "commit": "edit" }'
  vim.fn.writefile(lock, repo .. "/lazy-lock.json")
  local r = run_script(repo, "update")
  assert_true(r.code ~= 0, "exit code 0")
  assert_true(r.out:find("uncommitted changes", 1, true) ~= nil, "no message:\n" .. r.out)
  assert_true(not called(r.calls, "Lazy!"), "lazy ran anyway: " .. vim.inspect(r.calls))
  vim.fn.delete(repo, "rf")
end)

test("the script refuses a config dir other than the checkout", function()
  local repo = make_repo()
  local r = run_script(repo, "restore", { config = vim.fn.tempname() })
  assert_true(r.code ~= 0, "exit code 0")
  assert_true(r.out:find("but this checkout is", 1, true) ~= nil, "no message:\n" .. r.out)
  assert_eq(r.calls, {}, "nvim calls")
  vim.fn.delete(repo, "rf")
end)

h.finish()

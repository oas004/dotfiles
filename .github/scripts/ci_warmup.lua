-- CI warm-up, run once before tests/run.sh:
--   nvim --headless -c "luafile .github/scripts/ci_warmup.lua"
--
-- Starting the config kicks off background work: Mason installing the
-- servers in mason-lspconfig's ensure_installed, nvim-treesitter compiling
-- missing parsers, the lazy.nvim update checker. Each test starts a fresh
-- nvim that would restart and then abandon that work, so wait here until
-- it settles. "Settled" means nvim has had no child processes for
-- WARMUP_QUIET_MS. The script always exits 0; install failures show up in
-- the report and in the tests that need the missing tool.

local quiet_ms = tonumber(vim.env.WARMUP_QUIET_MS) or 20000
local max_ms = tonumber(vim.env.WARMUP_MAX_MS) or 900000

local start = vim.uv.now()
local quiet_since = nil
local last_progress = 0

local function out(s)
  io.stdout:write(s .. "\n")
end

local function report(reason)
  out(string.format("warm-up finished after %ds: %s", (vim.uv.now() - start) / 1000, reason))

  local ok, registry = pcall(require, "mason-registry")
  if ok then
    local names = registry.get_installed_package_names()
    table.sort(names)
    out("mason packages: " .. table.concat(names, ", "))
  end

  local ok_ts, ts_info = pcall(require, "nvim-treesitter.info")
  if ok_ts and ts_info.installed_parsers then
    out("treesitter parsers: " .. table.concat(ts_info.installed_parsers(), ", "))
  end

  out("=== :messages ===")
  out(vim.fn.execute("messages"))
end

local timer = vim.uv.new_timer()
timer:start(1000, 1000, vim.schedule_wrap(function()
  local now = vim.uv.now()
  local children = vim.api.nvim_get_proc_children(vim.fn.getpid())

  if #children > 0 then
    quiet_since = nil
  else
    quiet_since = quiet_since or now
  end

  if now - last_progress >= 30000 then
    last_progress = now
    out(string.format("waiting: %ds elapsed, %d child processes", (now - start) / 1000, #children))
  end

  local reason
  if quiet_since and now - quiet_since >= quiet_ms then
    reason = string.format("no child processes for %ds", quiet_ms / 1000)
  elseif now - start >= max_ms then
    reason = string.format("gave up after %ds (%d child processes still running)", max_ms / 1000, #children)
  end
  if reason then
    timer:stop()
    report(reason)
    vim.cmd("qall!")
  end
end))

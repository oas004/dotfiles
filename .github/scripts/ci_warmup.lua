-- CI warm-up, run once before tests/run.sh:
--   nvim --headless -c "luafile .github/scripts/ci_warmup.lua"
--
-- Starting the config kicks off background work: nvim-treesitter compiling
-- missing parsers, the lazy.nvim update checker. Each test starts a fresh
-- nvim that would restart and then abandon that work, so wait here until
-- it settles.
--
-- mason-lspconfig skips ensure_installed in headless mode, so without help
-- CI would have no language servers. This script installs the same servers
-- with :MasonInstall, which blocks in headless mode and exits non-zero if any
-- install fails (set WARMUP_MASON=0 to skip that). The server list is read
-- from mason-lspconfig's settings table, the only non-public piece here.
--
-- "Settled" means no Mason package is installing and nvim has had no child
-- processes for WARMUP_QUIET_MS. Apart from Mason install failures the
-- script exits 0; other problems show up in the tests that need the tool.

local quiet_ms = tonumber(vim.env.WARMUP_QUIET_MS) or 20000
local max_ms = tonumber(vim.env.WARMUP_MAX_MS) or 900000

local start = vim.uv.now()
local quiet_since = nil
local last_progress = 0

local function out(s)
  io.stdout:write(s .. "\n")
end

local ok_registry, registry = pcall(require, "mason-registry")
local ensure_installed = {}

if ok_registry and vim.env.WARMUP_MASON ~= "0" then
  local ok_settings, settings = pcall(require, "mason-lspconfig.settings")
  if ok_settings then
    ensure_installed = settings.current.ensure_installed or {}
  end
  registry.refresh() -- synchronous without a callback
  local map = require("mason-lspconfig").get_mappings().lspconfig_to_package
  local missing = {}
  for _, server in ipairs(ensure_installed) do
    local pkg = map[server]
    if pkg and not registry.is_installed(pkg) then
      table.insert(missing, pkg)
    end
  end
  if #missing > 0 then
    out("installing: " .. table.concat(missing, ", "))
    vim.cmd("MasonInstall " .. table.concat(missing, " "))
  end
end

local function mason_busy()
  if not ok_registry then
    return false
  end
  for _, pkg in ipairs(registry.get_all_packages()) do
    if pkg:is_installing() then
      return true
    end
  end
  return false
end

local function report(reason)
  out(string.format("warm-up finished after %ds: %s", (vim.uv.now() - start) / 1000, reason))

  if ok_registry then
    local names = registry.get_installed_package_names()
    table.sort(names)
    out("mason packages: " .. table.concat(names, ", "))
    local ok_map, map = pcall(function()
      return require("mason-lspconfig").get_mappings().lspconfig_to_package
    end)
    for _, server in ipairs(ensure_installed) do
      local pkg = ok_map and map[server]
      local installed = pkg and registry.is_installed(pkg)
      out(string.format("  %s (%s): %s", server, pkg or "?", installed and "installed" or "MISSING"))
    end
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

  local busy = #children > 0 or mason_busy()
  if busy then
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

-- Startup smoke test, driven by tests/run.sh.
--
-- Start Neovim with the files to open as arguments and run this script:
--   nvim --headless sample.lua sample.rs -c "luafile tests/startup_smoke.lua"
--
-- Every file in the argument list is opened with :edit. Files with a known
-- extension must get their LSP client (see `expected` below); the test waits
-- up to SMOKE_WAIT_MS for them (default 60000 on CI, 30000 otherwise), then
-- another SMOKE_SETTLE_MS (default 2000) so a server that crashes right after
-- attaching is still caught. It fails if an expected client did not attach or
-- has stopped, if :messages contains an error (any case), a Vim error code
-- such as "E5108:", an LSP client exit or a deprecation warning, if an
-- ERROR-level vim.notify was recorded by the --cmd hook in run.sh, or if an
-- opened buffer has no filetype.
--
-- This file is not named *_test.lua on purpose: it needs files passed on the
-- command line, so run.sh invokes it separately.

local wait_ms = tonumber(vim.env.SMOKE_WAIT_MS) or (vim.env.CI and 60000 or 30000)
local settle_ms = tonumber(vim.env.SMOKE_SETTLE_MS) or 2000

-- Extension -> LSP client that must attach, and whether its server is
-- installed. Expectations for missing servers are skipped locally, but on CI
-- (where every server is installed) a missing server is a failure.
local expected = {
  lua = { client = "lua_ls", available = function() return vim.fn.executable("lua-language-server") == 1 end },
  rs = { client = "rust_analyzer", available = function() return vim.fn.executable("rust-analyzer") == 1 end },
  -- Mason's kotlin-lsp package links its launcher as intellij-server
  kt = { client = "kotlin_lsp", available = function() return vim.fn.executable("intellij-server") == 1 end },
}

-- Lowercased :messages lines containing any of these fail the test.
local bad_patterns = {
  "error", -- E5108: Error executing lua ..., Check log for errors, ...
  "quit with exit code", -- Client rust_analyzer quit with exit code 1 and signal 0
  "exited with code", -- LSP[name]: ... exited with code
  "deprecated", -- vim.deprecate() and plugin deprecation notices
}

local failures = {}

local function fail(msg)
  table.insert(failures, msg)
end

local function out(msg)
  io.stdout:write(msg .. "\n")
end

local files = vim.fn.argv() --[[@as string[] ]]
if #files == 0 then
  fail("no files given on the command line")
end

for _, f in ipairs(files) do
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(f))
  if not ok then
    fail(":edit " .. f .. " failed: " .. tostring(err))
  end
end

local function client_names(buf)
  return vim.tbl_map(function(c)
    return c.name
  end, vim.lsp.get_clients({ bufnr = buf }))
end

local function main()
  -- buffer -> client name that must attach to it
  local want = {}
  for _, f in ipairs(files) do
    local buf = vim.fn.bufnr(f)
    local exp = expected[vim.fn.fnamemodify(f, ":e")]
    if buf ~= -1 and exp then
      if exp.available() then
        want[buf] = exp.client
      elseif vim.env.CI then
        fail(exp.client .. " is not installed, cannot check " .. f)
      else
        out(string.format("- %s: not checking %s (server not installed)", vim.fn.fnamemodify(f, ":t"), exp.client))
      end
    end
  end

  local function all_attached()
    for buf, name in pairs(want) do
      if #vim.lsp.get_clients({ bufnr = buf, name = name }) == 0 then
        return false
      end
    end
    return true
  end

  local start = vim.uv.now()
  vim.wait(wait_ms, all_attached, 100)
  local waited = vim.uv.now() - start
  vim.wait(settle_ms)

  for _, f in ipairs(files) do
    local buf = vim.fn.bufnr(f)
    if buf == -1 then
      fail("buffer not found for " .. f)
    else
      local names = client_names(buf)
      out(string.format("%s: filetype=%s lsp=[%s]", vim.fn.fnamemodify(f, ":t"), vim.bo[buf].filetype,
        table.concat(names, ",")))
      if vim.bo[buf].filetype == "" then
        fail("no filetype detected for " .. f)
      end
      if want[buf] and not vim.list_contains(names, want[buf]) then
        fail(string.format("%s not attached to %s after %d ms", want[buf], f, waited))
      end
    end
  end

  -- Recorded by the --cmd hook in run.sh, if present. A plugin that replaces
  -- vim.notify later hides subsequent notifications from this hook.
  -- selene: allow(global_usage)
  ---@diagnostic disable-next-line: undefined-field
  for _, msg in ipairs(_G.startup_smoke_errors or {}) do
    fail("vim.notify ERROR: " .. msg)
  end

  local messages = vim.fn.execute("messages")
  for line in messages:gmatch("[^\n]+") do
    local lower = line:lower()
    local bad = line:find("%f[%w]E%d+:") ~= nil
    for _, pat in ipairs(bad_patterns) do
      bad = bad or lower:find(pat, 1, true) ~= nil
    end
    if bad then
      fail("message: " .. line)
    end
  end

  out("=== :messages ===\n" .. messages)
  if #failures > 0 then
    out("=== Smoke test FAILED ===")
    for _, msg in ipairs(failures) do
      out("  " .. msg)
    end
    vim.cmd("cquit 1")
  else
    out(string.format("=== Smoke test passed (%d files, clients attached after %d ms) ===", #files, waited))
    vim.cmd("qall!")
  end
end

local function run()
  local ok, err = pcall(main)
  if not ok then
    out("smoke test aborted: " .. tostring(err))
    vim.cmd("cquit 1")
  end
end

-- -c commands run before VimEnter; wait for startup to finish so plugins
-- loaded on VimEnter/VeryLazy are part of the test.
if vim.v.vim_did_enter == 1 then
  vim.schedule(run)
else
  vim.api.nvim_create_autocmd("VimEnter", { once = true, nested = true, callback = run })
end

-- Startup smoke test, driven by tests/run.sh.
--
-- Start Neovim with the files to open as arguments and run this script:
--   nvim --headless sample.lua sample.rs -c "luafile tests/startup_smoke.lua"
--
-- Every file in the argument list is opened with :edit. After SMOKE_WAIT_MS
-- (default 3000) the test fails if :messages contains "Error" or a Vim error
-- code such as "E5108:", if an ERROR-level vim.notify was recorded by the
-- --cmd hook in run.sh, or if an opened buffer has no filetype.
--
-- This file is not named *_test.lua on purpose: it needs files passed on the
-- command line, so run.sh invokes it separately.

local wait_ms = tonumber(vim.env.SMOKE_WAIT_MS) or 3000

local failures = {}

local function fail(msg)
  table.insert(failures, msg)
end

local files = vim.fn.argv()
if #files == 0 then
  fail("no files given on the command line")
end

for _, f in ipairs(files) do
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(f))
  if not ok then
    fail(":edit " .. f .. " failed: " .. tostring(err))
  end
end

vim.defer_fn(function()
  for _, f in ipairs(files) do
    local buf = vim.fn.bufnr(f)
    if buf == -1 then
      fail("buffer not found for " .. f)
    else
      local clients = vim.tbl_map(function(c)
        return c.name
      end, vim.lsp.get_clients({ bufnr = buf }))
      io.stdout:write(string.format("%s: filetype=%s lsp=[%s]\n", vim.fn.fnamemodify(f, ":t"),
        vim.bo[buf].filetype, table.concat(clients, ",")))
      if vim.bo[buf].filetype == "" then
        fail("no filetype detected for " .. f)
      end
    end
  end

  -- Recorded by the --cmd hook in run.sh, if present. A plugin that replaces
  -- vim.notify later hides subsequent notifications from this hook.
  for _, msg in ipairs(_G.startup_smoke_errors or {}) do
    fail("vim.notify ERROR: " .. msg)
  end

  local messages = vim.fn.execute("messages")
  for line in messages:gmatch("[^\n]+") do
    if line:find("Error", 1, true) or line:find("%f[%w]E%d+:") then
      fail("message: " .. line)
    end
  end

  io.stdout:write("=== :messages ===\n" .. messages .. "\n")
  if #failures > 0 then
    io.stdout:write("=== Smoke test FAILED ===\n")
    for _, msg in ipairs(failures) do
      io.stdout:write("  " .. msg .. "\n")
    end
    vim.cmd("cquit 1")
  else
    io.stdout:write(string.format("=== Smoke test passed (%d files, waited %d ms) ===\n", #files, wait_ms))
    vim.cmd("qall!")
  end
end, wait_ms)

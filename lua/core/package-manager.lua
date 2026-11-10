-- https://github.com/folke/lazy.nvim?tab=readme-ov-file#-installation
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

-- The lazy.nvim commit recorded in lazy-lock.json, or nil if the lockfile is
-- missing, can't be parsed or has no lazy.nvim entry.
local function locked_lazy_commit()
  local lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json"
  local ok, lock = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
  end)
  local entry = ok and type(lock) == "table" and lock["lazy.nvim"]
  local commit = type(entry) == "table" and entry.commit
  if type(commit) == "string" and commit:match("^%x+$") then
    return commit
  end
end

-- $LAZY points at a lazy.nvim checkout to use instead, so leave lazypath alone
if not vim.env.LAZY and not vim.uv.fs_stat(lazypath) then
  -- bootstrap lazy.nvim
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
  -- Check out the locked commit, so lazy.nvim doesn't start on (and write
  -- into lazy-lock.json) whatever stable is today. A blobless clone fetches
  -- commits it lacks on checkout; the explicit fetch covers servers that
  -- ignored --filter. If neither works, stay on stable.
  local commit = locked_lazy_commit()
  if commit then
    local function checkout()
      return vim.fn.system({ "git", "-C", lazypath, "checkout", "--quiet", commit })
    end
    out = checkout()
    if vim.v.shell_error ~= 0 then
      vim.fn.system({ "git", "-C", lazypath, "fetch", "--quiet", "origin", commit })
      out = checkout()
    end
    if vim.v.shell_error ~= 0 then
      vim.api.nvim_echo({
        { "Failed to check out lazy.nvim " .. commit .. " from lazy-lock.json, using stable:\n", "WarningMsg" },
        { out, "WarningMsg" },
      }, true, {})
    end
  end
end

vim.opt.rtp:prepend(vim.env.LAZY or lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
  checker = { enabled = true, notify = false }, -- automatically check for plugin updates
  performance = {
    cache = {
      enabled = true,
    },
    reset_packpath = true,
    rtp = {
      reset = true,
      -- disable some rtp plugins
      disabled_plugins = {
        "gzip",
        "netrwPlugin",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
  ui = {
    -- Reduce UI updates
    throttle = 50,
  },
})

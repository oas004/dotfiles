require("config.options")
require("config.package-manager")
require("config.keymaps")

-- LSP cache cleanup command
vim.api.nvim_create_user_command('CleanupLSPCache', function()
  local cache_dirs = {
    vim.fn.stdpath("cache") .. "/kotlin-lsp",
    vim.fn.stdpath("data") .. "/jdtls",
  }
  for _, dir in ipairs(cache_dirs) do
    if vim.fn.isdirectory(dir) == 1 then
      vim.fn.system("rm -rf " .. vim.fn.shellescape(dir))
      vim.notify("Cleaned: " .. dir, vim.log.levels.INFO)
    end
  end
  vim.notify("LSP cache cleanup complete. Restart Neovim.", vim.log.levels.INFO)
end, { desc = "Clean LSP caches (Kotlin & Java)" })

local custom = require('custom.git')
--
--#region Custom Git Plugin
--
vim.api.nvim_create_user_command('CustomGitStatus', function(opts)
  custom.git_status({
    full = opts.bang,
    scratch = true,
  })
end, { bang = true })

vim.keymap.set('n', '<Leader>gs', function() custom.git_status({ scratch = true }) end,  { desc = 'git status (short)' })
vim.keymap.set('n', '<Leader>gS', function() custom.git_status({ full = true, scratch = true }) end, { desc = 'git status (full)' })
--
--#endregion


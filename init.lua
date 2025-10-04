require("config.options")
require("config.package-manager")
require("config.keymaps")

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


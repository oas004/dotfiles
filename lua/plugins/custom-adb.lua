vim.api.nvim_create_user_command('CustomAdbDevices', function(opts)
  require('custom.adb').devices({ long = opts.bang })
end, { bang = true })

pcall(function() require('telescope').load_extension('adb') end)

vim.keymap.set('n', '<Leader>ad', function()
  require('telescope').extensions.adb.devices({})
end, { desc = 'ADB: pick device' })

-- Adb Install Part

-- :AdbPickInstall (bang => allow downgrade)
vim.api.nvim_create_user_command('AdbPickInstall', function(opts)
  require('custom.adb').install_from_picker({ downgrade = opts.bang })
end, { bang = true })

-- :AdbInstall path/to/file.apk
vim.api.nvim_create_user_command('AdbInstall', function(opts)
  require('custom.adb').install(opts.args, {})
end, { nargs = 1, complete = 'file' })

-- Hotkeys
vim.keymap.set('n', '<Leader>ai', function()
  require('custom.adb').install_from_picker({})
end, { desc = 'ADB: pick & install APK' })

vim.keymap.set('n', '<Leader>aI', function()
  require('custom.adb').install_from_picker({ downgrade = true })
end, { desc = 'ADB: pick & install (downgrade)' })

return {
  {
    "nvim-telescope/telescope.nvim",
    optional = true,  -- only run if Telescope is installed
    keys = {
      { "<Leader>ad", function() require("telescope").extensions.adb.devices({}) end, desc = "ADB: pick device" },
      { "<Leader>ai", function() require("custom.adb").install_from_picker({}) end, desc = "ADB: pick & install APK" },
      { "<Leader>aI", function() require("custom.adb").install_from_picker({ downgrade = true }) end, desc = "ADB: pick & install (downgrade)" },
    },
    config = function()
      -- your module with install() / install_from_picker()
      -- lives in lua/custom/adb/init.lua
      pcall(function() require("telescope").load_extension("adb") end) -- if you made the extension
    end,
  },
}

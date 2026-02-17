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
      -- Load telescope extension
      pcall(function() require("telescope").load_extension("adb") end)

      -- Setup all ADB commands and keymaps
      require("custom.adb.commands").setup()
    end,
  },
}

local function everforest()
    return {
        "sainnhe/everforest",
        config = function ()
            vim.cmd("colorscheme everforest")
        end
    }
end

local function nordic()
  return {
    "AlexvZyl/nordic.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("nordic").load()
    end,
  }
end

return {
    nordic(),
    {
        "nvim-lualine/lualine.nvim",
        vent = "BufReadPre",
    },
}

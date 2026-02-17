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
      require("nordic").setup({
        -- Disable italic comments for better readability
        reduced_blue = true,
      })
      require("nordic").load()

      -- Override highlight groups for better comment and search visibility
      local highlights = {
        -- Comments: brighter and more visible
        Comment = { fg = "#b8cde6", italic = false },
        -- Search highlighting: better contrast
        Search = { bg = "#4c5a73", fg = "#eceff4", bold = true },
        IncSearch = { bg = "#88c0d0", fg = "#2e3440", bold = true },
        -- Visual selection: more visible
        Visual = { bg = "#3b4252" },
        -- Line numbers and sign column
        LineNr = { fg = "#616e88" },
        SignColumn = { bg = "NONE" },
      }

      for group, colors in pairs(highlights) do
        vim.api.nvim_set_hl(0, group, colors)
      end
    end,
  }
end

return {
    nordic(),
    {
        "nvim-lualine/lualine.nvim",
        event = "BufReadPre",
    },
}

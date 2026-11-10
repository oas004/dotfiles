local function nordic()
  return {
    "AlexvZyl/nordic.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("nordic").setup({
        -- Reduce the overall amount of blue in the theme (diverges from base Nord)
        reduced_blue = true,
      })
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

      -- Reapply the overrides every time nordic is loaded, so they survive
      -- a :colorscheme nordic (which clears all highlights first).
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("nordic_overrides", { clear = true }),
        pattern = "nordic",
        callback = function()
          for group, colors in pairs(highlights) do
            vim.api.nvim_set_hl(0, group, colors)
          end
        end,
      })

      vim.cmd.colorscheme("nordic")
    end,
  }
end

return {
  nordic(),
  {
    "nvim-lualine/lualine.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        -- nordic.nvim ships a lualine theme at lua/lualine/themes/nordic.lua
        theme = "nordic",
      },
    },
  },
}

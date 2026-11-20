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
        -- Indent guides (snacks.indent): dimmer than listchars (NonText),
        -- and the current scope a step brighter
        SnacksIndent = { fg = "#434C5E" },
        SnacksIndentScope = { fg = "#60728A" },
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

  -- https://github.com/folke/snacks.nvim/blob/main/docs/indent.md
  -- Indent guides, with the scope around the cursor highlighted. Only in
  -- normal file buffers: help, terminals (the Claude Code terminal),
  -- nvim-tree, lazy and Mason all have a buftype and are skipped, and so
  -- are files snacks.bigfile flagged.
  {
    "folke/snacks.nvim",
    -- snacks turns indent guides on at the first BufReadPost after it is
    -- set up. Loaded later (claudecode loads it on VeryLazy), the file
    -- given on the command line would have no guides.
    lazy = false,
    keys = {
      {
        "<leader>ui",
        function()
          local indent = require("snacks").indent
          if indent.enabled then
            indent.disable()
          else
            indent.enable()
          end
        end,
        desc = "Toggle indent guides",
      },
    },
    opts = {
      indent = {
        enabled = true,
        -- The scope moves with the cursor; without animation it just
        -- switches.
        animate = { enabled = false },
        filter = function(buf)
          return vim.g.snacks_indent ~= false
            and vim.b[buf].snacks_indent ~= false
            and vim.bo[buf].buftype == ""
            and vim.bo[buf].filetype ~= "bigfile"
        end,
      },
    },
  },
}

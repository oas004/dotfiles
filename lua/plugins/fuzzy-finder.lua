-- https://github.com/nvim-telescope/telescope.nvim
return {
  {
    "nvim-telescope/telescope.nvim",
    -- Follows master: releases lag behind it, and v0.2.2 still passes file
    -- names through the shell in the previewer's mime type check (fixed in
    -- 1e1bab7). lazy-lock.json holds the commit actually installed.
    -- also depends on ripgrep: `brew install ripgrep`
    dependencies = {
      "nvim-lua/plenary.nvim",
      -- Listed here rather than as its own spec so it loads with telescope
      -- instead of at startup.
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
      local utils = require("core.utils")
      local telescope = utils.safe_require("telescope", "Failed to load telescope")
      if not telescope then
        return
      end

      telescope.setup({
        defaults = {
          -- Lua patterns matched against the relative path. Anchor ".git" to a
          -- path component so .github/ and .gitignore are not hidden.
          file_ignore_patterns = { "^%.git/", "/%.git/", "node_modules/" },
          -- Performance optimizations
          layout_strategy = "horizontal",
          sorting_strategy = "ascending",
          scroll_strategy = "cycle",
          cache_picker = {
            num_pickers = 10,
          },
          -- Reduce lag on file preview
          preview = {
            timeout = 150,
            treesitter = false, -- disable treesitter in previews for speed
          },
          -- Better performance for large repos
          vimgrep_arguments = {
            "rg",
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
            "--smart-case",
            "--trim", -- trim whitespace
          },
        },
        pickers = {
          buffers = {
            sort_lastused = true,
            -- Insert mode uses telescope's default <M-d> for delete_buffer;
            -- a <Leader> map there would fire while typing in the prompt
            mappings = {
              n = {
                ["<Leader>q"] = "delete_buffer",
              },
            },
          },
          find_files = {
            hidden = false,
          },
        },
      })

      -- telescope-fzf-native is a compiled C sorter and does not need the
      -- fzf binary. pcall covers the case where `make` has not been run.
      pcall(telescope.load_extension, "fzf")
    end,
    keys = {
      -- Android Studio-like keybindings (Mac)
      {
        "<D-S-o>",
        function()
          require("telescope.builtin").find_files()
        end,
        desc = "Go to file (Cmd+Shift+O)",
      },
      {
        "<D-o>",
        function()
          require("telescope.builtin").lsp_document_symbols()
        end,
        desc = "Go to symbol in file (Cmd+O)",
      },
      {
        "<D-A-o>",
        function()
          require("telescope.builtin").lsp_workspace_symbols()
        end,
        desc = "Go to symbol (Cmd+Opt+O)",
      },
      {
        "<D-S-f>",
        function()
          require("telescope.builtin").live_grep()
        end,
        desc = "Find in path (Cmd+Shift+F)",
      },
      {
        "<D-e>",
        function()
          require("telescope.builtin").oldfiles()
        end,
        desc = "Recent files (Cmd+E)",
      },

      -- Fallback leader-based bindings (for terminals that don't pass Cmd)
      {
        "<Leader>f",
        function()
          require("telescope.builtin").live_grep()
        end,
        desc = "Find in files",
      },
      {
        "<Leader>p",
        function()
          require("telescope.builtin").find_files()
        end,
        desc = "Find files",
      },
      {
        "<Leader>o",
        function()
          require("telescope.builtin").buffers()
        end,
        desc = "Open buffers",
      },
      {
        "<Leader>s",
        function()
          require("telescope.builtin").lsp_document_symbols()
        end,
        desc = "Document symbols",
      },
      {
        "<Leader>S",
        function()
          require("telescope.builtin").lsp_workspace_symbols()
        end,
        desc = "Workspace symbols",
      },
      {
        "<Leader>r",
        function()
          require("telescope.builtin").oldfiles()
        end,
        desc = "Recent files",
      },
    },
  },
}

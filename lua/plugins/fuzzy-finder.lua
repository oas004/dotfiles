-- https://github.com/nvim-telescope/telescope.nvim
return {
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.5",
        -- also depends on ripgrep: `brew install ripgrep`
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            local utils = require('core.utils')
            local telescope = utils.safe_require('telescope', 'Failed to load telescope')
            if not telescope then return end

            telescope.setup({
                defaults = {
                    file_ignore_patterns = { "node_modules", ".git" },
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
                        mappings = {
                            i = {
                                ["<Leader>q"] = "delete_buffer",
                            },
                            n = {
                                ["<Leader>q"] = "delete_buffer",
                            }
                        }
                    },
                    find_files = {
                        hidden = false,
                    },
                }
            })

            -- Load extensions safely
            local extensions = { "adb" }

            -- Try to load fzf if available
            if vim.fn.executable("fzf") == 1 then
              table.insert(extensions, "fzf")
            end

            for _, ext in ipairs(extensions) do
              local ok, _ = utils.safe_call(function()
                telescope.load_extension(ext)
              end, string.format("Failed to load %s telescope extension", ext))
            end
        end,
        keys = {
            { "<Leader>f", function() require("telescope.builtin").live_grep({}) end },
            { "<Leader>p", function() require("telescope.builtin").find_files() end },
            { "<Leader>o", function() require("telescope.builtin").buffers() end },
        }
    },
    {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
    }
}

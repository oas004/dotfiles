-- https://github.com/nvim-telescope/telescope.nvim
return {
    {
        "nvim-telescope/telescope.nvim",
        tag = "0.1.5",
        -- also depends on ripgrep: `brew install ripgrep`
        dependencies = { "nvim-lua/plenary.nvim" },
        config = function()
            require("telescope").setup({
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
                }
            })

            -- Load custom extensions safely
            local ok, err = pcall(function()
              require("telescope").load_extension("adb")
            end)
            if not ok then
              vim.notify(string.format("Failed to load adb telescope extension: %s", err), vim.log.levels.WARN)
            end
        end,
        keys = {
            { "<Leader>f", function() require("telescope.builtin").live_grep({}) end },
            { "<Leader>p", function() require("telescope.builtin").find_files() end },
            { "<Leader>o", function() require("telescope.builtin").buffers() end },
        }
    }
}

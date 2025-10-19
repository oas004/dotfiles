return {
    -- https://github.com/nvim-treesitter/nvim-treesitter
    {
        "nvim-treesitter/nvim-treesitter",
        build = ":TSUpdate",
        config = function()
            require("nvim-treesitter.configs").setup({
                -- A list of parser names, or "all" (the five listed parsers should always be installed)
                -- Reference: https://github.com/nvim-treesitter/nvim-treesitter?tab=readme-ov-file#supported-languages
                ensure_installed = {
                    -- required
                    "c",
                    "lua",
                    "vim",
                    "vimdoc",
                    "query",

                    -- optional
                    "go",
                    "gomod",
                    "gosum",
                    "gowork",
                    "javascript",
                    "json",
                    "kotlin",
                    "typescript",
                    "yaml",
                },
                textobjects = { "nvim-treesitter/nvim-treesitter-textobjects" },
                -- Install parsers synchronously (only applied to `ensure_installed`)
                sync_install = false,

                -- Automatically install missing parsers when entering buffer
                -- Recommendation: set to false if you don"t have `tree-sitter` CLI installed locally
                auto_install = false,

                highlight = {
                    enable = true,
                    additional_vim_regex_highlighting = false,
                },
                textobjects = {
                    move = {
                      enable = true,
                      set_jumps = true,
                      goto_next_start = { ["]m"] = "@function.outer" },
                      goto_previous_start = { ["[m"] = "@function.outer" },
                      goto_next_end = { ["]M"] = "@function.outer" },
                      goto_previous_end = { ["[M"] = "@function.outer" },
                    },
                    select = {
                      enable = true,
                      lookahead = true,
                      keymaps = {
                        ["af"] = "@function.outer",
                        ["if"] = "@function.inner",
                      },
                    },
                }
            })
        end,
    },
}

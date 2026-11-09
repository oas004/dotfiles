-- https://github.com/folke/which-key.nvim
-- Shows a popup with the available keys after a prefix such as <leader>.
-- Only group names are registered here; the maps themselves (and their
-- desc) live where they are defined.
return {
    {
        "folke/which-key.nvim",
        version = "^3", -- the spec format below is the v3 one
        event = "VeryLazy",
        opts = {
            spec = {
                { "<leader>a", group = "ai (Claude)", mode = { "n", "v" } },
                { "<leader>c", group = "code" },
                { "<leader>h", group = "git hunks", mode = { "n", "x" } },
                { "<leader>n", group = "new" },
                { "<leader>y", group = "yank", mode = { "n", "x" } },
            },
        },
        keys = {
            {
                "<leader>?",
                function() require("which-key").show({ global = false }) end,
                desc = "Buffer-local keymaps (which-key)",
            },
        },
    },
}

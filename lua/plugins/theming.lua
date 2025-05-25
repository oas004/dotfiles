local function everforest()
    return {
        "sainnhe/everforest",
        config = function ()
            vim.cmd("colorscheme everforest")
        end
    }
end

return {
    everforest(),
    {
        "nvim-lualine/lualine.nvim",
        vent = "BufReadPre",
    },
}

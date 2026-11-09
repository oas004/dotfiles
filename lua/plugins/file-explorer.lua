local function toggle()
    local api = require("nvim-tree.api")
    local current_buf = vim.api.nvim_get_current_buf()
    local current_buftype = vim.api.nvim_get_option_value("filetype", { buf = current_buf })
    if current_buftype == "NvimTree" then
        api.tree.close()
    else
        api.tree.focus()
    end
end

local function find_file()
    require("nvim-tree.api").tree.find_file({ open = true, focus = true })
end

return {
    {
        "nvim-tree/nvim-tree.lua",
        version = "^1",
        lazy = true,  -- Only load when needed
        cmd = { "NvimTreeToggle", "NvimTreeFocus", "NvimTreeFindFile" },
        keys = {
            { "<Leader>l", toggle, mode = "n", desc = "nvim-tree: Toggle" },
            { "<Leader>L", find_file, mode = "n", desc = "nvim-tree: Find current file" },
        },
        dependencies = { "nvim-tree/nvim-web-devicons" },
        config = function()
            require("nvim-tree").setup({
                disable_netrw = true,
                update_focused_file = {
                    enable = true,
                },
                view = {
                    width = {
                        min = 30,
                        max = -1,
                        padding = 0,
                    },
                    float = {
                        enable = false,
                    },
                },
            })
        end,
    },
}

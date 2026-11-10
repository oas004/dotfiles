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
    lazy = true, -- Only load when needed
    cmd = { "NvimTreeToggle", "NvimTreeFocus", "NvimTreeFindFile" },
    keys = {
      { "<Leader>l", toggle, mode = "n", desc = "nvim-tree: Toggle" },
      { "<Leader>L", find_file, mode = "n", desc = "nvim-tree: Find current file" },
    },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    -- netrw is disabled, so `nvim <dir>` (or `:edit <dir>`) would show an
    -- empty buffer. Load nvim-tree the first time a directory buffer is
    -- entered and let its hijack_directories handler take over. After
    -- that nvim-tree's own autocmd handles directories.
    init = function()
      local group = vim.api.nvim_create_augroup("NvimTreeLazyDirectory", { clear = true })
      vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        desc = "Load nvim-tree when a directory is opened",
        callback = function(args)
          if vim.fn.isdirectory(vim.api.nvim_buf_get_name(args.buf)) == 0 then
            return
          end
          vim.api.nvim_del_augroup_by_id(group)
          require("lazy").load({ plugins = { "nvim-tree.lua" } })
          vim.api.nvim_exec_autocmds("BufEnter", { group = "NvimTree", buffer = args.buf, modeline = false })
        end,
      })
    end,
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

-- https://github.com/nvim-telescope/telescope.nvim

local function picker(name)
  return function()
    require("telescope.builtin")[name]()
  end
end

-- Android Studio-like keybindings (Mac). Terminals that don't pass Cmd
-- through use the <leader>f maps below.
local keys = {
  { "<D-S-o>", picker("find_files"), desc = "Go to file (Cmd+Shift+O)" },
  { "<D-o>", picker("lsp_document_symbols"), desc = "Go to symbol in file (Cmd+O)" },
  { "<D-A-o>", picker("lsp_workspace_symbols"), desc = "Go to symbol (Cmd+Opt+O)" },
  { "<D-S-f>", picker("live_grep"), desc = "Find in path (Cmd+Shift+F)" },
  { "<D-e>", picker("oldfiles"), desc = "Recent files (Cmd+E)" },
}

-- Pickers under the <leader>f (find) group. The single-letter maps they
-- replaced stay as aliases for now. <leader>f itself is the group prefix,
-- so its old live grep map is only on <leader>fg.
local leader_pickers = {
  { "ff", "find_files", "Find files", alias = "p" },
  { "fg", "live_grep", "Grep in files" },
  { "fb", "buffers", "Buffers", alias = "o" },
  { "fr", "oldfiles", "Recent files", alias = "r" },
  { "fs", "lsp_document_symbols", "Document symbols", alias = "s" },
  { "fS", "lsp_workspace_symbols", "Workspace symbols", alias = "S" },
}
for _, p in ipairs(leader_pickers) do
  table.insert(keys, { "<Leader>" .. p[1], picker(p[2]), desc = p[3] })
  if p.alias then
    local desc = p[3] .. " (old map, use <leader>" .. p[1] .. ")"
    table.insert(keys, { "<Leader>" .. p.alias, picker(p[2]), desc = desc })
  end
end

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
    keys = keys,
  },
}

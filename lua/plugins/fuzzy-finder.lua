-- Pickers from snacks.picker (https://github.com/folke/snacks.nvim).
-- snacks.nvim is also used by claudecode.nvim and other plugin specs; lazy.nvim
-- merges their opts into one setup() call.
-- Grep needs ripgrep (`brew install ripgrep`).

local function picker(name, opts)
  return function()
    require("snacks").picker[name](opts)
  end
end

-- Android Studio-like keybindings (Mac). Terminals that don't pass Cmd
-- through use the <leader>f maps below.
local keys = {
  { "<D-S-o>", picker("files"), desc = "Go to file (Cmd+Shift+O)" },
  { "<D-o>", picker("lsp_symbols"), desc = "Go to symbol in file (Cmd+O)" },
  { "<D-A-o>", picker("lsp_workspace_symbols"), desc = "Go to symbol (Cmd+Opt+O)" },
  { "<D-S-f>", picker("grep"), desc = "Find in path (Cmd+Shift+F)" },
  { "<D-e>", picker("recent"), desc = "Recent files (Cmd+E)" },
}

-- Pickers under the <leader>f (find) and <leader>g (git) groups. Lowercase
-- is the current buffer and uppercase the whole workspace where both exist
-- (fs/fS, fd/fD). The single-letter maps from before the find group stay as
-- aliases for now. <leader>gg is left for lazygit.
local leader_pickers = {
  { "ff", "files", "Find files", alias = "p" },
  { "fg", "grep", "Grep in files" },
  { "fb", "buffers", "Buffers", alias = "o" },
  { "fr", "recent", "Recent files", alias = "r" },
  { "fs", "lsp_symbols", "Document symbols", alias = "s" },
  { "fS", "lsp_workspace_symbols", "Workspace symbols", alias = "S" },
  { "fd", "diagnostics_buffer", "Diagnostics (buffer)" },
  { "fD", "diagnostics", "Diagnostics (workspace)" },
  { "fh", "help", "Help tags" },
  { "fk", "keymaps", "Keymaps" },
  { "fw", "grep_word", "Grep word under cursor or selection", mode = { "n", "x" } },
  { "f.", "resume", "Resume last picker" },
  { "gs", "git_status", "Git status" },
  { "gl", "git_log", "Git log" },
  { "gL", "git_log_file", "Git log (current file)" },
}
for _, p in ipairs(leader_pickers) do
  table.insert(keys, { "<Leader>" .. p[1], picker(p[2]), mode = p.mode, desc = p[3] })
  if p.alias then
    local desc = p[3] .. " (old map, use <leader>" .. p[1] .. ")"
    table.insert(keys, { "<Leader>" .. p.alias, picker(p[2]), desc = desc })
  end
end

-- Hidden files and files ignored by git are left out by default (toggle them
-- in a picker with <M-h> and <M-i>). .git/ is always excluded; node_modules/
-- is excluded even where no .gitignore lists it. .github/ and .gitignore show
-- up once hidden files are on.
local exclude = { "node_modules" }

return {
  {
    "folke/snacks.nvim",
    keys = keys,
    opts = {
      picker = {
        sources = {
          files = { exclude = exclude },
          grep = { exclude = exclude },
          grep_word = { exclude = exclude },
          buffers = {
            -- The delete keys from the telescope config, on top of snacks'
            -- own <C-x> (input) and dd (list)
            win = {
              input = {
                keys = {
                  ["<M-d>"] = { "bufdelete", mode = { "n", "i" } },
                  ["<Leader>q"] = { "bufdelete", mode = "n" },
                },
              },
            },
          },
        },
      },
    },
  },
}

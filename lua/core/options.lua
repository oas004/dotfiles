vim.g.mapleader = " "
-- Set explicitly (the default is also backslash) so it is defined before
-- lazy.nvim loads filetype plugins that map <localleader>.
vim.g.maplocalleader = "\\"

local opt = vim.opt

opt.clipboard = "unnamedplus" -- use system clipboard

-- ui
opt.termguicolors = true -- true color support
-- Highlight only the current line number. cursorline was slow with Vim's
-- regex syntax highlighting, but it is cheap with treesitter.
opt.cursorline = true
opt.cursorlineopt = "number"
opt.wrap = false -- nowrap
opt.signcolumn = "yes" -- always show, so text does not shift when signs appear
opt.breakindent = true -- wrapped lines keep their indent (when wrap is on)
-- Show tabs, trailing spaces and non-breaking spaces
opt.list = true
opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- windows
opt.splitright = true -- :vsplit opens to the right
opt.splitbelow = true -- :split opens below

-- Ask to save instead of failing on :q with unsaved changes
opt.confirm = true

-- line numbers
opt.number = true -- show line numbers
opt.relativenumber = true -- show relative line numbers

-- indents
opt.tabstop = 2
opt.softtabstop = 2
opt.shiftwidth = 2
opt.expandtab = true

opt.smartindent = true
opt.autoindent = true

opt.shiftround = true -- round-off indents to align

-- backups
opt.swapfile = false
opt.backup = false

-- undo history (stored in the default undodir, stdpath("state")/undo)
opt.undofile = true

-- search
opt.hlsearch = true
opt.incsearch = true
-- Case-insensitive unless the pattern has an uppercase letter, like
-- live grep's rg --smart-case. * and # don't use smartcase, so they ignore
-- case too; \C in a pattern forces case-sensitive matching.
opt.ignorecase = true
opt.smartcase = true
-- Preview :s replacements as you type, with off-screen matches in a split
opt.inccommand = "split"

opt.scrolloff = 8
opt.sidescrolloff = 8

-- ms of idle before CursorHold fires (default 4000). Lower means the
-- CursorHold autoreload check below notices changed files sooner.
opt.updatetime = 250

-- Regex syntax highlighting (buffers without a treesitter parser) stops
-- after this column. Treesitter highlighting ignores it.
opt.synmaxcol = 300
opt.redrawtime = 1500 -- ms before hlsearch and regex syntax give up on a redraw

-- Reload files changed on disk by other programs (e.g. AI coding agents
-- such as Claude Code editing files while they are open here).
opt.autoread = true

local autoreload = vim.api.nvim_create_augroup("AutoReloadChangedFiles", { clear = true })

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "TermLeave", "TermClose" }, {
  group = autoreload,
  desc = "Check if files changed on disk",
  callback = function()
    -- :checktime is not allowed in the command-line window
    if vim.fn.getcmdwintype() == "" then
      pcall(vim.cmd.checktime)
    end
  end,
})

vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = autoreload,
  desc = "Notify when a buffer was reloaded from disk",
  callback = function(args)
    local name = vim.fn.fnamemodify(args.file, ":~:.")
    vim.notify("File changed on disk, buffer reloaded: " .. name, vim.log.levels.INFO)
  end,
})

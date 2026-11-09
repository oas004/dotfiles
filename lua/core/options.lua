vim.g.mapleader = " "

local opt = vim.opt

opt.clipboard = "unnamedplus" -- use system clipboard

-- ui
opt.termguicolors = true -- true color support
opt.cursorline = false -- disable for performance (especially on macOS)
opt.wrap = false -- nowrap

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

opt.scrolloff = 8
opt.sidescrolloff = 8

-- ms of idle before CursorHold fires (default 4000). Lower means the
-- CursorHold autoreload check below notices changed files sooner.
opt.updatetime = 250

-- Performance optimizations
opt.lazyredraw = true -- don't redraw during macros/scripts
opt.synmaxcol = 300 -- don't syntax highlight long lines
opt.redrawtime = 1500 -- prevent slow rendering

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

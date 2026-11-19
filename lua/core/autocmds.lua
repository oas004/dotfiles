-- General editing autocmds

local group = vim.api.nvim_create_augroup("user_editing", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  desc = "Briefly highlight yanked text",
  callback = function()
    vim.hl.on_yank()
  end,
})

-- Commit messages and rebase todo lists are new text each time, so they
-- start at the top.
local no_restore = { gitcommit = true, gitrebase = true }

-- Reloads (:edit, and the autoread :checktime in core/options.lua when e.g.
-- Claude Code changes the file) fire BufReadPost too, but Neovim puts the
-- cursor back where it was after the reload, so they need no special case.
vim.api.nvim_create_autocmd("BufReadPost", {
  group = group,
  desc = "Restore the cursor position from the last time the file was open",
  callback = function(args)
    -- Files loaded in the background (bufload(), as LSP rename does) run
    -- this in a temporary autocmd window, so the cursor set here is that
    -- window's, not the user's.
    local buf = args.buf
    -- This autocmd runs before filetype detection, so match the filetype here
    local ft = vim.bo[buf].filetype
    if ft == "" then
      ft = vim.filetype.match({ buf = buf }) or ""
    end
    if no_restore[ft] then
      return
    end
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(buf) then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})

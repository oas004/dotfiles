local keymap = vim.keymap

keymap.set("i", "jj", "<Esc>", { desc = "Exit insert mode" })
keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })
keymap.set("v", ";;", "<Esc>", { desc = "Exit visual mode" })

keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR><Esc>", { desc = "Clear search highlight" })
keymap.set("n", "<C-s>", "<Cmd>update<CR>", { desc = "Save file" })
-- <Esc> rather than <C-C> so InsertLeave autocmds still fire
keymap.set({ "i", "v" }, "<C-s>", "<Esc><Cmd>update<CR>", { desc = "Save file" })

-- Diagnostics (LSP keymaps are buffer-local, see plugins/language-server.lua)
keymap.set('n', 'gl', function()
  vim.diagnostic.open_float(nil, { scope = 'line', focus = false, border = 'rounded' })
end, { desc = 'Line diagnostics' })

keymap.set('n', '<leader>e', function() vim.diagnostic.jump({ count = 1, float = true }) end, { desc = 'Next diagnostic' })
keymap.set('n', '<leader>E', function() vim.diagnostic.jump({ count = -1, float = true }) end, { desc = 'Prev diagnostic' })

-- Create new file in current file's directory
keymap.set('n', '<Leader>ne', function()
  local dir = vim.fn.expand('%:h')
  if dir == '' then dir = '.' end
  local filename = vim.fn.input('New file in ' .. dir .. '/: ')
  if filename ~= '' then
    vim.cmd('edit ' .. dir .. '/' .. filename)
  end
end, { desc = 'New file (same directory)' })

-- AI agent helpers: copy a code reference (path:LINE or path:START-END)
-- for pasting into an AI prompt such as Claude Code.
local function code_reference_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == '' then return nil end
  local file = vim.uv.fs_realpath(name) or vim.fs.normalize(vim.fn.fnamemodify(name, ':p'))
  local cwd = vim.uv.fs_realpath(vim.fn.getcwd()) or vim.fn.getcwd()
  local rel = vim.fs.relpath(cwd, file)
  if not rel then
    local root = vim.fs.root(file, '.git')
    root = root and (vim.uv.fs_realpath(root) or root)
    rel = root and vim.fs.relpath(root, file)
  end
  return rel or vim.fn.fnamemodify(file, ':~')
end

local function copy_code_reference()
  local path = code_reference_path(0)
  if not path then
    vim.notify('Buffer has no file name', vim.log.levels.WARN)
    return
  end
  local mode = vim.fn.mode()
  local ref
  if mode == 'v' or mode == 'V' or mode == '\22' then
    local s, e = vim.fn.line('v'), vim.fn.line('.')
    if s > e then s, e = e, s end
    ref = s == e and string.format('%s:%d', path, s) or string.format('%s:%d-%d', path, s, e)
    vim.cmd('normal! \27') -- leave visual mode
  else
    ref = string.format('%s:%d', path, vim.fn.line('.'))
  end
  local reg = vim.fn.has('clipboard') == 1 and '+' or '"'
  vim.fn.setreg(reg, ref)
  vim.notify('Copied ' .. ref, vim.log.levels.INFO)
end

keymap.set({ 'n', 'x' }, '<leader>yr', copy_code_reference, { desc = 'Copy code reference (path:line) for AI prompt' })

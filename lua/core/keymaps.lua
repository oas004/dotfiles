local keymap = vim.keymap
local silent = { silent = true }

-- Helper to safely set keymaps with error handling
local function safe_set(mode, lhs, rhs, opts)
  opts = opts or {}
  local ok, err = pcall(keymap.set, mode, lhs, rhs, opts)
  if not ok then
    vim.notify(string.format("Failed to map '%s': %s", lhs, err), vim.log.levels.WARN)
  end
end

safe_set("n", "Y", "y$")
safe_set("i", "jj", "<Esc>")
safe_set("i", "jk", "<Esc>")
safe_set("v", ";;", "<Esc>")

safe_set("n", "j", "gj")
safe_set("n", "k", "gk")

safe_set("n", "<Esc>", ":nohl<CR><Esc>", silent)
safe_set({ "n", "i", "v" }, "<C-s>", "<C-C>:update<CR>", silent)

-- Android Studio-like keybindings (Mac)
-- Navigation
safe_set('n', '<D-b>', vim.lsp.buf.definition, { desc = 'Go to definition (Cmd+B)' })
safe_set('n', '<D-A-b>', vim.lsp.buf.implementation, { desc = 'Go to implementation (Cmd+Opt+B)' })
safe_set('n', '<A-F7>', vim.lsp.buf.references, { desc = 'Find usages (Opt+F7)' })

-- Refactoring
safe_set('n', '<S-F6>', vim.lsp.buf.rename, { desc = 'Rename (Shift+F6)' })
safe_set('n', '<A-CR>', vim.lsp.buf.code_action, { desc = 'Code actions (Opt+Enter)' })

-- Diagnostics
safe_set('n', 'gl', function()
  vim.diagnostic.open_float(nil, { scope = 'line', focus = false, border = 'rounded' })
end, { desc = 'Line diagnostics' })

safe_set('n', '<leader>e', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
safe_set('n', '<leader>E', vim.diagnostic.goto_prev, { desc = 'Prev diagnostic' })

-- LSP navigation (fallback if Cmd keys don't work in terminal)
safe_set('n', 'gr', function()
  vim.lsp.buf.references({ includeDeclaration = false })
end, { desc = 'LSP: References (usages)' })

safe_set('n', 'gd', vim.lsp.buf.definition,      { desc = 'LSP: Go to definition' })
safe_set('n', 'gD', vim.lsp.buf.declaration,     { desc = 'LSP: Go to declaration' })
safe_set('n', 'gI', vim.lsp.buf.implementation,  { desc = 'LSP: Go to implementation' })
safe_set('n', 'gy', vim.lsp.buf.type_definition, { desc = 'LSP: Go to type' })

-- Format current buffer
safe_set('n', '<leader>fm', function()
  vim.lsp.buf.format({ async = false, timeout_ms = 5000 })
end, { desc = 'Format buffer' })

-- Create new file in current file's directory
safe_set('n', '<Leader>ne', function()
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

safe_set({ 'n', 'x' }, '<leader>yr', copy_code_reference, { desc = 'Copy code reference (path:line) for AI prompt' })

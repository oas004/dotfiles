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

safe_set('n', 'gl', function()
  vim.diagnostic.open_float(nil, { scope = 'line', focus = false, border = 'rounded' })
end, { desc = 'Line diagnostics' })

safe_set('n', '<leader>e', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
safe_set('n', '<leader>E', vim.diagnostic.goto_prev, { desc = 'Prev diagnostic' })

safe_set('n', 'gr', function()
  vim.lsp.buf.references({ includeDeclaration = false })
end, { desc = 'LSP: References (usages)' })

safe_set('n', 'gd', vim.lsp.buf.definition,      { desc = 'LSP: Go to definition' })
safe_set('n', 'gD', vim.lsp.buf.declaration,     { desc = 'LSP: Go to declaration' })
safe_set('n', 'gI', vim.lsp.buf.implementation,  { desc = 'LSP: Go to implementation' })
safe_set('n', 'gy', vim.lsp.buf.type_definition, { desc = 'LSP: Go to type' })

-- Create new file in current file's directory
safe_set('n', '<Leader>ne', function()
  local dir = vim.fn.expand('%:h')
  if dir == '' then dir = '.' end
  local filename = vim.fn.input('New file in ' .. dir .. '/: ')
  if filename ~= '' then
    vim.cmd('edit ' .. dir .. '/' .. filename)
  end
end, { desc = 'New file (same directory)' })

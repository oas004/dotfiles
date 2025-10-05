local keymap = vim.keymap
local silent = { silent = true }

keymap.set("n", "Y", "y$")
keymap.set("i", "jj", "<Esc>")
keymap.set("i", "jk", "<Esc>")
keymap.set("v", ";;", "<Esc>")

keymap.set("n", "j", "gj")
keymap.set("n", "k", "gk")

keymap.set("n", "<Esc>", ":nohl<CR><Esc>", silent)
keymap.set({ "n", "i", "v" }, "<C-s>", "<C-C>:update<CR>", silent)

keymap.set('n', 'gl', function()
  vim.diagnostic.open_float(nil, { scope = 'line', focus = false, border = 'rounded' })
end, { desc = 'Line diagnostics' })

keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Next diagnostic' })
keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Prev diagnostic' })

vim.keymap.set('n', 'gr', function()
  vim.lsp.buf.references({ includeDeclaration = false })
end, { desc = 'LSP: References (usages)' })

vim.keymap.set('n', 'gd', vim.lsp.buf.definition,      { desc = 'LSP: Go to definition' })
vim.keymap.set('n', 'gD', vim.lsp.buf.declaration,     { desc = 'LSP: Go to declaration' })
vim.keymap.set('n', 'gI', vim.lsp.buf.implementation,  { desc = 'LSP: Go to implementation' })
vim.keymap.set('n', 'gy', vim.lsp.buf.type_definition, { desc = 'LSP: Go to type' })

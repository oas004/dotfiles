-- Diagnostic display. Neovim 0.11 turned virtual text off by default, so
-- without this, diagnostics only show up as signs.
vim.diagnostic.config({
  -- Inline message at the end of the line. Full text is one keypress away
  -- with gl, <leader>e and <leader>E (see core/keymaps.lua).
  virtual_text = {
    prefix = "●",
    spacing = 2,
    source = "if_many",
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "E",
      [vim.diagnostic.severity.WARN] = "W",
      [vim.diagnostic.severity.INFO] = "I",
      [vim.diagnostic.severity.HINT] = "H",
    },
  },
  underline = true,
  update_in_insert = false,
  -- Errors win over warnings when several diagnostics share a line.
  severity_sort = true,
  float = {
    border = "rounded",
    source = true,
  },
})

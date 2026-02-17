return {
  'lewis6991/gitsigns.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    local utils = require('core.utils')
    local gitsigns = utils.safe_require('gitsigns', 'Failed to load gitsigns')
    if not gitsigns then return end

    gitsigns.setup({
      signs = {
        add = { text = '┃' },
        change = { text = '┃' },
        delete = { text = '_' },
        topdelete = { text = '‾' },
        changedelete = { text = '~' },
      },
      signcolumn = true,
      numhl = false,
      linehl = false,
      watch_gitdir = {
        follow_files = true,
      },
      auto_attach = true,
      current_line_blame = false,
      current_line_blame_opts = {
        virt_text = true,
        virt_text_pos = 'eol',
        delay = 1000,
        ignore_whitespace = false,
      },
      preview_config = {
        border = 'rounded',
        style = 'minimal',
        relative = 'cursor',
        row = 0,
        col = 1,
      },
    })

    local keymap = vim.keymap
    local silent = { silent = true }

    -- Toggle blame on current line
    keymap.set('n', '<Leader>gb', gitsigns.toggle_current_line_blame, vim.tbl_extend('force', silent, { desc = 'Toggle git blame on line' }))

    -- Show blame for current line in popup
    keymap.set('n', '<Leader>gB', gitsigns.blame_line, vim.tbl_extend('force', silent, { desc = 'Git blame line (popup)' }))

    -- Show full buffer blame
    keymap.set('n', '<Leader>g?', ':Gitsigns blame<CR>', vim.tbl_extend('force', silent, { desc = 'Git blame (full buffer)' }))
  end,
}

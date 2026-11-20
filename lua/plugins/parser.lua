-- Parsers installed by nvim-treesitter. Languages without an entry here
-- can still be installed manually with :TSInstall <lang>.
local parsers = {
  "c",
  "lua",
  "vim",
  "vimdoc",
  "query",
  "javascript",
  "json",
  "kotlin",
  "typescript",
  "yaml",
  -- Rust / WebAssembly
  "rust",
  "toml",
  "wit",
  -- Languages with configured LSPs
  "java",
  "python",
  "haskell",
  "cpp",
  "bash",
  "markdown",
  "markdown_inline",
  -- Android and Gradle: AndroidManifest.xml and res/ files, build.gradle
  -- and settings.gradle (the .kts files use kotlin). xml also installs dtd.
  "xml",
  "groovy",
  -- Git: commit messages, interactive rebase todo lists, patches
  "gitcommit",
  "git_rebase",
  "diff",
  -- Injected into other languages: regex literals, HTML in markdown
  "regex",
  "html",
}
-- Exposed so bootstrap.sh can install the same list synchronously.
vim.g.treesitter_parsers = parsers

-- Filetypes indented with nvim-treesitter's indentexpr instead of the
-- runtime indent script. nvim-treesitter calls its indentation
-- experimental, so it is only used where it did better than the runtime
-- script (reindenting rustfmt and clang-format output, and typing new
-- lines). Kotlin and Haskell have no indent queries; Java, C, Lua and
-- Python did as well or better with the runtime script.
local treesitter_indent = {
  rust = true,
  cpp = true,
}

-- nvim-treesitter's main branch dropped Neovim 0.11 support in c82bf96f.
-- On 0.11, pin the last main commit that still supports it. Once Neovim is
-- 0.12 or newer the pin goes away and the plugin follows main. lazy-lock.json
-- still records this commit, so after upgrading Neovim run
-- :Lazy update nvim-treesitter to move off it.
local nvim_011_commit = "90cd6580e720caedacb91fdd587b747a6e77d61f"

--- Set up a buffer that snacks.bigfile gave the "bigfile" filetype. The
--- filetype alone already keeps language servers, treesitter (FileType
--- autocmd below), ftplugins and syntax files away.
---@param ctx { buf: integer, ft: string }
local function bigfile_setup(ctx)
  -- Cheap matchparen in this buffer only. snacks' default runs
  -- :NoMatchParen, which turns it off in every buffer for the session.
  vim.b[ctx.buf].matchparen_timeout = 1
  vim.b[ctx.buf].matchparen_insert_timeout = 1
  vim.wo[0][0].foldmethod = "manual"
  vim.wo[0][0].conceallevel = 0
  vim.b[ctx.buf].completion = false
  local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(ctx.buf), ":~:.")
  vim.notify(
    ("Big file %s: LSP, treesitter, syntax highlighting and folding are off (detected as %s)"):format(
      name,
      ctx.ft ~= "" and ctx.ft or "no filetype"
    ),
    vim.log.levels.WARN
  )
end

return {
  -- https://github.com/folke/snacks.nvim/blob/main/docs/bigfile.md
  -- Files over 1.5 MB, or with an average line over 1000 characters
  -- (minified JS/JSON), get the "bigfile" filetype instead of their own.
  -- This has to be set up before the first file is read, so snacks.nvim
  -- loads at startup (claudecode would otherwise load it on VeryLazy).
  {
    "folke/snacks.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      bigfile = {
        enabled = true,
        notify = false, -- bigfile_setup says what was turned off
        setup = bigfile_setup,
      },
    },
  },

  -- https://github.com/nvim-treesitter/nvim-treesitter/tree/main
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    commit = vim.fn.has("nvim-0.12") == 0 and nvim_011_commit or nil,
    lazy = false, -- main does not support lazy-loading
    build = ":TSUpdate",
    config = function()
      local ts = require("nvim-treesitter")
      if not ts.install then
        -- Still on the old master checkout until lazy switches branches
        vim.notify("nvim-treesitter is not on the main branch yet, run :Lazy sync", vim.log.levels.WARN)
        return
      end

      -- Install missing parsers in the background. Compiling a parser
      -- needs the tree-sitter CLI and a C compiler.
      local installed = ts.get_installed("parsers")
      local missing = vim.tbl_filter(function(lang)
        return not vim.list_contains(installed, lang)
      end, parsers)
      if #missing > 0 then
        if vim.fn.executable("tree-sitter") == 1 then
          ts.install(missing)
        else
          vim.notify(
            "nvim-treesitter: tree-sitter CLI not found, cannot install parsers: " .. table.concat(missing, ", "),
            vim.log.levels.WARN
          )
        end
      end

      -- Files open with every fold open. Global, so reloading a file (which
      -- fires FileType again) doesn't undo zM or zc.
      vim.o.foldlevel = 99

      -- Fold options are window-local. vim.wo[0][0] is :setlocal, so the
      -- values belong to the current buffer in the current window and stay
      -- with the buffer when it is shown in other windows; other buffers in
      -- the window keep their own fold settings.
      local function set_folds()
        vim.wo[0][0].foldmethod = "expr"
        vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
        vim.wo[0][0].foldtext = "" -- fold lines keep their highlighting
      end

      -- Highlighting, folding and indentation are no longer plugin modules
      -- on main; enable them per buffer instead. pcall because not every
      -- filetype has a parser.
      local group = vim.api.nvim_create_augroup("treesitter_buffer", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        callback = function(args)
          local buf = args.buf
          -- Big files get the "bigfile" filetype (snacks.bigfile below),
          -- which has no parser, so they skip all of this.
          if not pcall(vim.treesitter.start, buf) then
            return
          end
          vim.b[buf].treesitter_folds = true
          set_folds()
          if treesitter_indent[vim.bo[buf].filetype] then
            vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })

      -- A file loaded in the background (bufload(), as LSP rename does) gets
      -- FileType in a temporary autocmd window, so the fold options above
      -- never reach a real window. Set them when the buffer is first shown,
      -- unless the window already has fold settings for it.
      vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        callback = function(args)
          if vim.b[args.buf].treesitter_folds and vim.wo.foldmethod == "manual" and vim.wo.foldexpr == "0" then
            set_folds()
          end
        end,
      })
    end,
  },

  -- Treesitter text objects (af, if, etc)
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    branch = "main",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = {
          lookahead = true,
        },
      })

      -- Text object keymaps: af = around function, if = inside function
      vim.keymap.set({ "x", "o" }, "af", function()
        require("nvim-treesitter-textobjects.select").select_textobject("@function.outer", "textobjects")
      end, { desc = "Select around function" })

      vim.keymap.set({ "x", "o" }, "if", function()
        require("nvim-treesitter-textobjects.select").select_textobject("@function.inner", "textobjects")
      end, { desc = "Select inside function" })

      vim.keymap.set({ "x", "o" }, "ac", function()
        require("nvim-treesitter-textobjects.select").select_textobject("@class.outer", "textobjects")
      end, { desc = "Select around class" })

      vim.keymap.set({ "x", "o" }, "ic", function()
        require("nvim-treesitter-textobjects.select").select_textobject("@class.inner", "textobjects")
      end, { desc = "Select inside class" })

      -- Move keymaps: ]m = next function, [m = previous function
      vim.keymap.set({ "n", "x", "o" }, "]m", function()
        require("nvim-treesitter-textobjects.move").goto_next_start("@function.outer", "textobjects")
      end, { desc = "Next function start" })

      vim.keymap.set({ "n", "x", "o" }, "[m", function()
        require("nvim-treesitter-textobjects.move").goto_previous_start("@function.outer", "textobjects")
      end, { desc = "Previous function start" })

      vim.keymap.set({ "n", "x", "o" }, "]M", function()
        require("nvim-treesitter-textobjects.move").goto_next_end("@function.outer", "textobjects")
      end, { desc = "Next function end" })

      vim.keymap.set({ "n", "x", "o" }, "[M", function()
        require("nvim-treesitter-textobjects.move").goto_previous_end("@function.outer", "textobjects")
      end, { desc = "Previous function end" })
    end,
  },
}

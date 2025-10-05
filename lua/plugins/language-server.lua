return {
  -- nvim-cmp (completion)
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      { "L3MON4D3/LuaSnip" },
      { "VonHeikemen/lsp-zero.nvim", branch = "v3.x" },
    },
    config = function()
      local lsp_zero = require("lsp-zero")
      lsp_zero.extend_cmp()

      local cmp = require("cmp")
      local select = { behavior = cmp.SelectBehavior.Select }

      cmp.setup({
        formatting = lsp_zero.cmp_format(),
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<Tab>"]     = cmp.mapping.select_next_item(select),
          ["<S-Tab>"]   = cmp.mapping.select_prev_item(select),
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<C-u>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-d>"]     = cmp.mapping.scroll_docs(4),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "buffer" },
        }),
      })
    end,
  },

  -- LSP + mason + lsp-zero
  {
    "neovim/nvim-lspconfig",
    cmd = { "LspInfo", "LspInstall", "LspStart" },
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      { "hrsh7th/cmp-nvim-lsp" },
      { "williamboman/mason.nvim" },
      { "williamboman/mason-lspconfig.nvim" },
      { "VonHeikemen/lsp-zero.nvim", branch = "v3.x" },
    },
    config = function()
      local lsp_zero = require("lsp-zero")
      lsp_zero.extend_lspconfig()

      -- Format on save (adjust to taste)
      lsp_zero.format_on_save({
        format_opts = { async = false, timeout_ms = 10000 },
        servers = {
          ["gopls"] = { "go" },
          ["hls"]   = { "haskell", "lhaskell" },
          ["clangd"]= { "c", "cpp", "objc", "objcpp" },
        },
      })

      lsp_zero.on_attach(function(client, bufnr)
        lsp_zero.default_keymaps({ buffer = bufnr })

        -- gopls semantic tokens workaround
        if client.name == "gopls" and not client.server_capabilities.semanticTokensProvider then
          local semantic = client.config.capabilities.textDocument.semanticTokens
          client.server_capabilities.semanticTokensProvider = {
            full = true,
            legend = { tokenModifiers = semantic.tokenModifiers, tokenTypes = semantic.tokenTypes },
            range = true,
          }
        end
      end)

      -- Capabilities (safe even if cmp isn't ready yet)
      local caps = vim.lsp.protocol.make_client_capabilities()
      local ok_cmp, cmp_lsp = pcall(require, "cmp_nvim_lsp")
      if ok_cmp then caps = cmp_lsp.default_capabilities(caps) end

      local servers = {
        "gradle_ls",
        "jedi_language_server",
        "kotlin_language_server",
        "lua_ls",
        "hls",
        "clangd",
      }

      require("mason").setup({})
      require("mason-lspconfig").setup({
        ensure_installed = servers,
        handlers = {
          -- default handler
          function(server_name)
            require("lspconfig")[server_name].setup({ capabilities = caps })
          end,
        ["kotlin_language_server"] = function()
          local lspconfig = require("lspconfig")
          local util = lspconfig.util
          local root = util.root_pattern(
            "settings.gradle", "settings.gradle.kts",
            "build.gradle", "build.gradle.kts",
            "pom.xml", ".git"
          )(vim.fn.expand("%:p")) or vim.loop.cwd()
          local proj = vim.fn.fnamemodify(root, ":t")
          local store = vim.fn.stdpath("cache") .. "/kotlin-lsp/" .. proj
          require("lspconfig").kotlin_language_server.setup({
            capabilities = require("cmp_nvim_lsp").default_capabilities(),
            root_dir = function() return root end,
            init_options = {
              storagePath = store,  -- per-project H2 DB to avoid locks
            },
            cmd_env = {
                  GRADLE_OPTS = (vim.env.GRADLE_OPTS or "") .. " --no-configuration-cache",
                  JAVA_HOME   = vim.env.JAVA_HOME, -- keep your JDK
            },
          })
          end,

          ["lua_ls"] = function()
            require("lspconfig").lua_ls.setup({
              capabilities = caps,
              settings = {
                Lua = { diagnostics = { globals = { "vim" } } },
              },
            })
          end,

          ["clangd"] = function()
            require("lspconfig").clangd.setup({
              capabilities = caps,
              cmd = { "clangd", "--fallback-style=Google" },
            })
          end,

          ["hls"] = function()
            require("lspconfig").hls.setup({
              capabilities = caps,
              settings = { haskell = { formattingProvider = "ormolu" } },
            })
          end,
        },
      })
    end,
  },
}


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
      local ok_lsp, lsp_zero = pcall(require, "lsp-zero")
      if not ok_lsp then
        vim.notify("lsp-zero failed to load", vim.log.levels.ERROR)
        return
      end

      lsp_zero.extend_cmp()

      local ok_cmp, cmp = pcall(require, "cmp")
      if not ok_cmp then
        vim.notify("nvim-cmp failed to load", vim.log.levels.ERROR)
        return
      end

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
      local ok_lsp, lsp_zero = pcall(require, "lsp-zero")
      if not ok_lsp then
        vim.notify("lsp-zero failed to load", vim.log.levels.ERROR)
        return
      end

      lsp_zero.extend_lspconfig()

      -- Format on save (adjust to taste)
      local ok_format = pcall(function()
        lsp_zero.format_on_save({
          format_opts = { async = false, timeout_ms = 10000 },
          servers = {
            ["gopls"] = { "go" },
            ["hls"]   = { "haskell", "lhaskell" },
            ["clangd"]= { "c", "cpp", "objc", "objcpp" },
          },
        })
      end)

      if not ok_format then
        vim.notify("Failed to setup format on save", vim.log.levels.WARN)
      end

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

      local ok_mason, mason = pcall(require, "mason")
      if not ok_mason then
        vim.notify("mason failed to load", vim.log.levels.ERROR)
        return
      end

      mason.setup({})

      local ok_mason_lsp, mason_lsp = pcall(require, "mason-lspconfig")
      if not ok_mason_lsp then
        vim.notify("mason-lspconfig failed to load", vim.log.levels.ERROR)
        return
      end

      mason_lsp.setup({
        ensure_installed = servers,
        handlers = {
          -- default handler
          function(server_name)
            local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
            if ok_lspconfig then
              lspconfig[server_name].setup({ capabilities = caps })
            else
              vim.notify(string.format("Failed to setup %s", server_name), vim.log.levels.WARN)
            end
          end,
        ["kotlin_language_server"] = function()
          local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
          if not ok_lspconfig then
            vim.notify("Failed to setup kotlin_language_server", vim.log.levels.ERROR)
            return
          end

          local util = lspconfig.util
          local root = util.root_pattern(
            "settings.gradle", "settings.gradle.kts",
            "build.gradle", "build.gradle.kts",
            "pom.xml", ".git"
          )(vim.fn.expand("%:p")) or vim.loop.cwd()
          local proj = vim.fn.fnamemodify(root, ":t")
          local store = vim.fn.stdpath("cache") .. "/kotlin-lsp/" .. proj
          lspconfig.kotlin_language_server.setup({
            capabilities = cmp_lsp.default_capabilities(),
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
            local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
            if ok_lspconfig then
              lspconfig.lua_ls.setup({
                capabilities = caps,
                settings = {
                  Lua = { diagnostics = { globals = { "vim" } } },
                },
              })
            end
          end,

          ["clangd"] = function()
            local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
            if ok_lspconfig then
              lspconfig.clangd.setup({
                capabilities = caps,
                cmd = { "clangd", "--fallback-style=Google" },
              })
            end
          end,

          ["hls"] = function()
            local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
            if ok_lspconfig then
              lspconfig.hls.setup({
                capabilities = caps,
                settings = { haskell = { formattingProvider = "ormolu" } },
              })
            end
          end,
        },
      })
    end,
  },
}



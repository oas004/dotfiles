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

      -- Detect platform
      local is_mac = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1

      -- Adjust memory settings for platform
      local jvm_mem = is_mac and "2g" or "4g"
      local metaspace = is_mac and "512m" or "1g"

      -- Load Kotlin config switcher
      local ok_kotlin, kotlin_config = pcall(require, "config.kotlin-config")
      if not ok_kotlin then
        vim.notify("Failed to load kotlin-config", vim.log.levels.WARN)
      else
        kotlin_config.setup_commands()
      end

      -- Load Java config switcher
      local ok_java, java_config = pcall(require, "config.java-config")
      if not ok_java then
        vim.notify("Failed to load java-config", vim.log.levels.WARN)
      else
        java_config.setup_commands()
      end

      -- Format on save (adjust to taste)
      local ok_format = pcall(function()
        lsp_zero.format_on_save({
          format_opts = { async = false, timeout_ms = 10000 },
          servers = {
            ["gopls"] = { "go" },
            ["hls"]   = { "haskell", "lhaskell" },
            ["clangd"]= { "c", "cpp", "objc", "objcpp" },
            -- Exclude Kotlin LSP - let conform.nvim handle it with ktfmt
          },
        })
      end)

      if not ok_format then
        vim.notify("Failed to setup format on save", vim.log.levels.WARN)
      end

      lsp_zero.on_attach(function(client, bufnr)
        lsp_zero.default_keymaps({ buffer = bufnr })

        -- Code actions keybinding
        vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { buffer = bufnr, noremap = true, silent = true })

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

      -- Determine which Kotlin LSP to use
      local kotlin_lsp = "kotlin_language_server"
      if ok_kotlin then
        kotlin_lsp = kotlin_config.get_lsp_server()
      end

      local servers = {
        "gradle_ls",
        "jedi_language_server",
        "lua_ls",
        "hls",
        "clangd",
        "jdtls",
      }

      -- Add active Kotlin LSP server if it's the community one
      if kotlin_lsp == "kotlin_language_server" then
        table.insert(servers, "kotlin_language_server")
      end

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
                  -- Enable configuration cache and set reasonable memory limits
                  GRADLE_OPTS = (vim.env.GRADLE_OPTS or "") .. " -Xmx" .. jvm_mem .. " -XX:MaxMetaspaceSize=" .. metaspace,
                  JAVA_HOME   = vim.env.JAVA_HOME, -- keep your JDK
            },
            flags = {
              debounce_text_changes = is_mac and 800 or 500, -- Higher debounce on macOS
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
                -- Respects project-level .clang-format config before falling back to LLVM style
                cmd = { "clangd", "--fallback-style=LLVM" },
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

          ["jdtls"] = function()
            local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
            if not ok_lspconfig then
              vim.notify("Failed to setup jdtls", vim.log.levels.ERROR)
              return
            end

            local util = lspconfig.util
            local root = util.root_pattern(
              "pom.xml",
              "build.gradle", "build.gradle.kts",
              "settings.gradle", "settings.gradle.kts",
              ".git"
            )(vim.fn.expand("%:p")) or vim.loop.cwd()
            local proj = vim.fn.fnamemodify(root, ":t")
            local workspace_dir = vim.fn.stdpath("data") .. "/jdtls/" .. proj
            local os_type = vim.loop.os_uname().sysname

            lspconfig.jdtls.setup({
              capabilities = caps,
              root_dir = function() return root end,
              cmd = {
                "jdtls",
                "-data", workspace_dir,
                "--jvm-arg=-Xmx" .. jvm_mem,
                "--jvm-arg=-XX:MaxMetaspaceSize=" .. metaspace,
              },
              flags = {
                debounce_text_changes = is_mac and 800 or 500, -- Higher debounce on macOS
              },
              settings = {
                java = {
                  home = vim.env.JAVA_HOME or "",
                  eclipse = { downloadSources = true },
                  configuration = {
                    runtimes = {
                      {
                        name = "JavaSE-17",
                        path = vim.env.JAVA_HOME or "",
                      },
                    },
                  },
                  maven = { downloadSources = true },
                  implementationsCodeLens = { enabled = true },
                  referencesCodeLens = { enabled = true },
                },
              },
            })
          end,
        },
      })

      -- Manual setup for kotlin-lsp (not in Mason)
      if kotlin_lsp == "kotlin-lsp" then
        local ok_lspconfig, lspconfig = pcall(require, "lspconfig")
        if ok_lspconfig then
          local kotlin_lsp_path = os.getenv("HOME") .. "/.local/opt/kotlin-lsp/kotlin-lsp.sh"

          -- Check if kotlin-lsp exists at the expected path
          local f = io.open(kotlin_lsp_path, "r")
          if f then
            io.close(f)

            local util = lspconfig.util

            -- Define a custom LSP config
            local configs = require("lspconfig.configs")
            if not configs.kotlin_lsp then
              configs.kotlin_lsp = {
                default_config = {
                  cmd = { kotlin_lsp_path, "--stdio" },  -- IMPORTANT: Use stdio mode for LSP communication
                  filetypes = { "kotlin" },
                  root_dir = util.root_pattern(
                    "settings.gradle", "settings.gradle.kts",
                    "build.gradle", "build.gradle.kts",
                    "pom.xml", ".git"
                  ),
                  single_file_support = true,
                },
              }
            end

            -- Now setup kotlin-lsp using standard lspconfig
            lspconfig.kotlin_lsp.setup({
              capabilities = caps,
            })
            vim.notify("kotlin-lsp configured", vim.log.levels.INFO, { title = "Kotlin LSP" })
          else
            vim.notify(
              "kotlin-lsp not found at " .. kotlin_lsp_path .. "\nInstall from: https://github.com/Kotlin/kotlin-lsp/releases",
              vim.log.levels.ERROR,
              { title = "Kotlin LSP" }
            )
          end
        else
          vim.notify("lspconfig failed to load", vim.log.levels.ERROR)
        end
      end
    end,
  },
}



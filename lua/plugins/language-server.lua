return {
  -- nvim-cmp (completion)
  {
    "hrsh7th/nvim-cmp",
    lazy = false,  -- Load immediately
    priority = 30, -- Load after conform
    dependencies = {
      { "L3MON4D3/LuaSnip" },
      { "VonHeikemen/lsp-zero.nvim", branch = "v3.x" },
    },
    config = function()
      local utils = require('core.utils')

      local lsp_zero = utils.safe_require("lsp-zero", "lsp-zero failed to load")
      if not lsp_zero then return end

      lsp_zero.extend_cmp()

      local cmp = utils.safe_require("cmp", "nvim-cmp failed to load")
      if not cmp then return end

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
    lazy = false,  -- Load immediately to avoid race conditions
    priority = 50, -- Load after treesitter but before other plugins
    dependencies = {
      { "hrsh7th/cmp-nvim-lsp" },
      { "williamboman/mason.nvim" },
      { "williamboman/mason-lspconfig.nvim" },
      { "VonHeikemen/lsp-zero.nvim", branch = "v3.x" },
    },
    config = function()
      local utils = require('core.utils')

      local lsp_zero = utils.safe_require("lsp-zero", "lsp-zero failed to load")
      if not lsp_zero then return end

      lsp_zero.extend_lspconfig()

      -- Detect platform
      local is_mac = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1

      -- Adjust memory settings for platform
      local jvm_mem = is_mac and "2g" or "4g"
      local metaspace = is_mac and "512m" or "1g"

      -- Load Kotlin config switcher
      local kotlin_config = utils.safe_require("core.kotlin-config", "Failed to load kotlin-config")
      if kotlin_config then
        kotlin_config.setup_commands()
      end

      -- Load Java config switcher
      local java_config = utils.safe_require("core.java-config", "Failed to load java-config")
      if java_config then
        java_config.setup_commands()
      end

      -- Format on save (adjust to taste)
      local ok_format, _ = utils.safe_call(function()
        lsp_zero.format_on_save({
          format_opts = { async = false, timeout_ms = 10000 },
          servers = {
            ["hls"]   = { "haskell", "lhaskell" },
            ["clangd"]= { "c", "cpp", "objc", "objcpp" },
            -- Exclude Kotlin LSP - let conform.nvim handle it with ktfmt
          },
        })
      end, "Failed to setup format on save")

      lsp_zero.on_attach(function(client, bufnr)
        lsp_zero.default_keymaps({ buffer = bufnr })

        -- Code actions keybinding
        vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { buffer = bufnr, noremap = true, silent = true })
      end)

      -- Capabilities (safe even if cmp isn't ready yet)
      local caps = vim.lsp.protocol.make_client_capabilities()
      local cmp_lsp = utils.safe_require("cmp_nvim_lsp")
      if cmp_lsp then
        caps = cmp_lsp.default_capabilities(caps)
      end

      -- Determine which Kotlin LSP to use (always kotlin-lsp now)
      local kotlin_lsp = "kotlin-lsp"

      local servers = {
        "gradle_ls",
        "jedi_language_server",
        "lua_ls",
        "hls",
        "clangd",
        "jdtls",
      }

      -- kotlin-lsp is NOT in Mason, so we don't add it here

      local mason = utils.safe_require("mason", "mason failed to load")
      if not mason then return end

      mason.setup({})

      local mason_lsp = utils.safe_require("mason-lspconfig", "mason-lspconfig failed to load")
      if not mason_lsp then return end

      mason_lsp.setup({
        ensure_installed = servers,
        handlers = {
          -- default handler
          function(server_name)
            local lspconfig = utils.safe_require("lspconfig")
            if lspconfig then
              lspconfig[server_name].setup({ capabilities = caps })
            end
          end,

        ["lua_ls"] = function()
          local lspconfig = utils.safe_require("lspconfig")
          if lspconfig then
            lspconfig.lua_ls.setup({
              capabilities = caps,
              settings = {
                Lua = { diagnostics = { globals = { "vim" } } },
              },
            })
          end
        end,

        ["clangd"] = function()
          local lspconfig = utils.safe_require("lspconfig")
          if lspconfig then
            lspconfig.clangd.setup({
              capabilities = caps,
              -- Respects project-level .clang-format config before falling back to LLVM style
              cmd = { "clangd", "--fallback-style=LLVM" },
            })
          end
        end,

        ["hls"] = function()
          local lspconfig = utils.safe_require("lspconfig")
          if lspconfig then
            lspconfig.hls.setup({
              capabilities = caps,
              settings = { haskell = { formattingProvider = "ormolu" } },
            })
          end
        end,

        ["jdtls"] = function()
          local lspconfig = utils.safe_require("lspconfig", "Failed to setup jdtls")
          if not lspconfig then return end

          local paths = require('core.paths')
          local util = lspconfig.util
          local root = util.root_pattern(
            "pom.xml",
            "build.gradle", "build.gradle.kts",
            "settings.gradle", "settings.gradle.kts",
            ".git"
          )(vim.fn.expand("%:p")) or vim.loop.cwd()
          local proj = vim.fn.fnamemodify(root, ":t")
          local workspace_dir = paths.lsp_cache.jdtls .. "/" .. proj

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

      -- Setup kotlin-lsp (JetBrains official, not in Mason)
      local lspconfig = utils.safe_require("lspconfig")
      if lspconfig then
        local paths = require('core.paths')
        local kotlin_lsp_path = paths.external.kotlin_lsp

        -- Check if kotlin-lsp exists at the expected path
        if paths.file_exists(kotlin_lsp_path) then
          local util = lspconfig.util

          -- Define a custom LSP config
          local configs = require("lspconfig.configs")
          if not configs.kotlin_lsp then
            configs.kotlin_lsp = {
              default_config = {
                cmd = { kotlin_lsp_path, "--stdio" },
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
            on_new_config = function(config, root_dir)
              -- Generate per-project cache path based on root_dir
              local project_name = vim.fn.fnamemodify(root_dir, ":t")
              local cache_path = paths.lsp_cache.kotlin_lsp .. "/" .. project_name

              -- Ensure cache directory exists
              vim.fn.mkdir(cache_path, "p")

              -- Update cmd with project-specific cache
              config.cmd = { kotlin_lsp_path, "--stdio", "--system-path", cache_path }
            end,
          })
          vim.notify("kotlin-lsp configured (JetBrains)", vim.log.levels.INFO, { title = "Kotlin LSP" })
        else
          vim.notify(
            "kotlin-lsp not found at " .. kotlin_lsp_path .. "\nInstall from: https://github.com/Kotlin/kotlin-lsp/releases",
            vim.log.levels.ERROR,
            { title = "Kotlin LSP" }
          )
        end
      end
    end,
  },
}



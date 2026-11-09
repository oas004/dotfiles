return {
  -- nvim-cmp (completion)
  {
    "hrsh7th/nvim-cmp",
    lazy = false,  -- Load immediately
    priority = 30, -- Load after conform
    dependencies = {
      { "L3MON4D3/LuaSnip" },
      { "saadparwaiz1/cmp_luasnip" },
      { "hrsh7th/cmp-buffer" },
    },
    config = function()
      local utils = require('core.utils')

      local cmp = utils.safe_require("cmp", "nvim-cmp failed to load")
      if not cmp then return end

      local luasnip = utils.safe_require("luasnip", "LuaSnip failed to load")

      local select = { behavior = cmp.SelectBehavior.Select }

      -- Move through the menu if it is open, otherwise open it
      local function select_or_complete(direction)
        return cmp.mapping(function()
          if cmp.visible() then
            if direction == "next" then
              cmp.select_next_item({ behavior = cmp.SelectBehavior.Insert })
            else
              cmp.select_prev_item({ behavior = cmp.SelectBehavior.Insert })
            end
          else
            cmp.complete()
          end
        end)
      end

      cmp.setup({
        snippet = {
          expand = function(args)
            if luasnip then
              luasnip.lsp_expand(args.body)
            else
              vim.snippet.expand(args.body)
            end
          end,
        },
        -- Show the source next to each item, e.g. [LSP], [buffer], [luasnip]
        formatting = {
          fields = { "abbr", "menu", "kind" },
          format = function(entry, item)
            local name = entry.source.name
            item.menu = name == "nvim_lsp" and "[LSP]" or string.format("[%s]", name)
            return item
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<Tab>"]     = cmp.mapping.select_next_item(select),
          ["<S-Tab>"]   = cmp.mapping.select_prev_item(select),
          ["<CR>"]      = cmp.mapping.confirm({ select = true }),
          ["<C-u>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-d>"]     = cmp.mapping.scroll_docs(4),
          -- Previously added by lsp-zero's extend_cmp()
          ["<C-y>"]     = cmp.mapping.confirm({ select = false }),
          ["<C-e>"]     = cmp.mapping.abort(),
          ["<Up>"]      = cmp.mapping.select_prev_item(select),
          ["<Down>"]    = cmp.mapping.select_next_item(select),
          ["<C-p>"]     = select_or_complete("prev"),
          ["<C-n>"]     = select_or_complete("next"),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
        }),
      })
    end,
  },

  -- LSP: native vim.lsp.config, servers installed by mason and enabled by mason-lspconfig
  {
    "neovim/nvim-lspconfig",
    lazy = false,  -- Load immediately to avoid race conditions
    priority = 50, -- Load after treesitter but before other plugins
    dependencies = {
      { "hrsh7th/cmp-nvim-lsp" },
      { "williamboman/mason.nvim" },
      { "williamboman/mason-lspconfig.nvim" },
    },
    config = function()
      local utils = require('core.utils')
      local paths = require('core.paths')

      -- Detect platform
      local is_mac = vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1

      -- Adjust memory settings for platform
      local jvm_mem = is_mac and "2g" or "4g"
      local metaspace = is_mac and "512m" or "1g"

      -- Per-project cache directory: folder name plus a short hash of the full
      -- root path, so two projects with the same folder name don't share one
      local function project_dir(base, root_dir)
        local name = "default"
        if root_dir then
          local root = vim.fs.normalize(root_dir)
          name = vim.fs.basename(root) .. "-" .. vim.fn.sha256(root):sub(1, 8)
        end
        local dir = base .. "/" .. name
        vim.fn.mkdir(dir, "p")
        return dir
      end

      -- Start a server whose command line depends on the resolved root_dir
      local function start_rpc(cmd, dispatchers, config)
        return vim.lsp.rpc.start(cmd, dispatchers, {
          cwd = config.cmd_cwd,
          env = config.cmd_env,
          detached = config.detached,
        })
      end

      -- Capabilities from cmp, applied to every server
      local caps = vim.lsp.protocol.make_client_capabilities()
      local cmp_lsp = utils.safe_require("cmp_nvim_lsp")
      if cmp_lsp then
        caps = cmp_lsp.default_capabilities(caps)
      end
      vim.lsp.config("*", { capabilities = caps })

      -- Server overrides. These are merged on top of nvim-lspconfig's lsp/<name>.lua
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = { diagnostics = { globals = { "vim" } } },
        },
      })

      vim.lsp.config("clangd", {
        -- Respects project-level .clang-format config before falling back to LLVM style
        cmd = { "clangd", "--fallback-style=LLVM" },
      })

      vim.lsp.config("hls", {
        settings = { haskell = { formattingProvider = "ormolu" } },
      })

      vim.lsp.config("jdtls", {
        -- Evaluated per client, so every project root gets its own -data workspace
        cmd = function(dispatchers, config)
          return start_rpc({
            "jdtls",
            "-data", project_dir(paths.lsp_cache.jdtls, config.root_dir),
            "--jvm-arg=-Xmx" .. jvm_mem,
            "--jvm-arg=-XX:MaxMetaspaceSize=" .. metaspace,
          }, dispatchers, config)
        end,
        flags = {
          debounce_text_changes = is_mac and 800 or 500, -- Higher debounce on macOS
        },
        settings = {
          java = {
            home = vim.env.JAVA_HOME or "",
            eclipse = { downloadSources = true },
            maven = { downloadSources = true },
            implementationsCodeLens = { enabled = true },
            referencesCodeLens = { enabled = true },
          },
        },
      })

      -- kotlin-lsp (JetBrains official, installed outside Mason).
      -- Filetypes and root markers come from nvim-lspconfig's lsp/kotlin_lsp.lua.
      local kotlin_lsp_path = paths.external.kotlin_lsp
      vim.lsp.config("kotlin_lsp", {
        cmd = function(dispatchers, config)
          return start_rpc({
            kotlin_lsp_path,
            "--stdio",
            "--system-path", project_dir(paths.lsp_cache.kotlin_lsp, config.root_dir),
          }, dispatchers, config)
        end,
      })

      if paths.file_exists(kotlin_lsp_path) then
        vim.lsp.enable("kotlin_lsp")
      else
        -- Kotlin is optional, so only mention it once a Kotlin buffer is opened
        vim.api.nvim_create_autocmd("FileType", {
          pattern = "kotlin",
          once = true,
          callback = function()
            vim.notify(
              "kotlin-lsp not found at " .. kotlin_lsp_path .. "\nInstall from: https://github.com/Kotlin/kotlin-lsp/releases",
              vim.log.levels.WARN,
              { title = "Kotlin LSP" }
            )
          end,
        })
      end

      -- Buffer-local keymaps (what lsp-zero's default_keymaps used to set).
      -- Global maps from core/keymaps.lua (gd, gD, gr, gl, gI, gy, ...) win over
      -- these, and K comes from Neovim's built-in LSP defaults. lsp-zero's gi/go
      -- are left out since they shadow builtins and gI/gy already cover them;
      -- <F3> is left out so formatting goes through <leader>fm.
      local buffer_maps = {
        { "n", "gs", vim.lsp.buf.signature_help, "Show function signature" },
        { "n", "<F2>", vim.lsp.buf.rename, "Rename symbol" },
        { { "n", "x" }, "<F4>", vim.lsp.buf.code_action, "Execute code action" },
      }

      local function has_global_map(mode, lhs)
        local want = vim.api.nvim_replace_termcodes(lhs, true, true, true)
        for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
          if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == want then
            return true
          end
        end
        return false
      end

      -- Format on save, only for these servers and filetypes, using only that server
      local format_on_save = {
        hls    = { "haskell", "lhaskell" },
        clangd = { "c", "cpp", "objc", "objcpp" },
      }

      local attach_group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true })

      vim.api.nvim_create_autocmd("LspAttach", {
        group = attach_group,
        callback = function(args)
          local bufnr = args.buf
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if not client then return end

          for _, m in ipairs(buffer_maps) do
            local modes = type(m[1]) == "table" and m[1] or { m[1] }
            for _, mode in ipairs(modes) do
              if not has_global_map(mode, m[2]) then
                vim.keymap.set(mode, m[2], m[3], { buffer = bufnr, desc = m[4] })
              end
            end
          end

          vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action,
            { buffer = bufnr, noremap = true, silent = true, desc = "Code actions" })

          local fts = format_on_save[client.name]
          if fts and vim.tbl_contains(fts, vim.bo[bufnr].filetype) then
            local group = vim.api.nvim_create_augroup("user_lsp_format_" .. bufnr, { clear = true })
            vim.api.nvim_create_autocmd("BufWritePre", {
              group = group,
              buffer = bufnr,
              callback = function()
                vim.lsp.buf.format({
                  bufnr = bufnr,
                  id = client.id,
                  async = false,
                  timeout_ms = 10000,
                })
              end,
            })
          end
        end,
      })

      vim.api.nvim_create_autocmd("LspDetach", {
        group = attach_group,
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and format_on_save[client.name] then
            pcall(vim.api.nvim_del_augroup_by_name, "user_lsp_format_" .. args.buf)
          end
        end,
      })

      local servers = {
        "gradle_ls",
        "jedi_language_server",
        "lua_ls",
        "hls",
        "clangd",
        "jdtls",
        "rust_analyzer",
      }

      -- kotlin-lsp is NOT in Mason, so we don't add it here

      local mason = utils.safe_require("mason", "mason failed to load")
      if not mason then return end

      mason.setup({})

      local mason_lsp = utils.safe_require("mason-lspconfig", "mason-lspconfig failed to load")
      if not mason_lsp then return end

      -- mason-lspconfig v2 calls vim.lsp.enable() for each installed server,
      -- which picks up the vim.lsp.config() overrides above
      mason_lsp.setup({
        ensure_installed = servers,
      })
    end,
  },
}

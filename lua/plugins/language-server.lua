return {
  -- LSP: native vim.lsp.config, servers installed by mason, enabled explicitly below
  {
    "neovim/nvim-lspconfig",
    -- Not lazy-loaded. Loading on BufReadPre/BufNewFile would still attach
    -- servers to the buffer being opened, but config also runs mason.setup(),
    -- which defines :Mason and puts Mason's bin directory on PATH for the
    -- servers and for the formatters conform runs (vim.g.mason_tools below),
    -- and Mason's README advises against deferring that. :LspInfo and
    -- :LspRestart also come from this plugin.
    lazy = false,
    dependencies = {
      { "saghen/blink.cmp" },
      { "williamboman/mason.nvim" },
      { "williamboman/mason-lspconfig.nvim" },
    },
    config = function()
      local utils = require("core.utils")
      local paths = require("core.paths")

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

      -- Neovim's capabilities plus blink.cmp's completion capabilities
      -- (plugins/completion.lua), applied to every server. The first
      -- argument of get_lsp_capabilities overrides blink's, so pass nil and
      -- let it add Neovim's own (true).
      local caps = vim.lsp.protocol.make_client_capabilities()
      local blink = utils.safe_require("blink.cmp")
      if blink then
        caps = blink.get_lsp_capabilities(nil, true)
      end
      vim.lsp.config("*", { capabilities = caps })

      -- How long Neovim waits for a server to exit after shutdown/exit before
      -- killing it. Without it (the default, false) a server that ignores
      -- "exit" keeps running: on 0.11 Neovim quits without waiting, and on
      -- 0.12 :lsp restart waits for it forever. 0.12 reads exit_timeout, for
      -- every stop (quitting, :lsp restart, vim.lsp.enable(false)). 0.11 reads
      -- flags.exit_timeout, and only when Neovim quits. Set both.
      local jvm_exit_timeout = 5000
      local function exit_timeout(ms)
        return { exit_timeout = ms, flags = { exit_timeout = ms } }
      end

      -- 0.11's own exit handler sends shutdown on quit but never force-stops:
      -- its wait loop only counts the timeout down and then reports success,
      -- and its client:stop(true) is a no-op for a client already stopping.
      -- jdtls quit during a Maven import kept running for 39 s after Neovim
      -- exited. So on 0.11, after that handler, wait up to each server's
      -- flags.exit_timeout and then stop the ones still running.
      if vim.fn.has("nvim-0.12") == 0 then
        vim.api.nvim_create_autocmd("VimLeavePre", {
          group = vim.api.nvim_create_augroup("user_lsp_exit_timeout", { clear = true }),
          desc = "Force-stop language servers that ignore exit (0.11)",
          callback = function()
            local start = vim.uv.now()
            local waiting = vim.tbl_filter(function(c)
              return type(c.flags.exit_timeout) == "number"
            end, vim.lsp.get_clients())
            local function running(c)
              return not c.rpc.is_closing()
            end
            local max = 0
            for _, c in ipairs(waiting) do
              max = math.max(max, c.flags.exit_timeout)
            end
            vim.wait(max, function()
              return not vim.iter(waiting):any(function(c)
                return running(c) and vim.uv.now() - start < c.flags.exit_timeout
              end)
            end, 50)
            -- Not client:stop(true): on 0.11 that returns early for a client
            -- that is already stopping, as these are after the shutdown.
            for _, c in ipairs(waiting) do
              if running(c) then
                c.rpc.terminate()
              end
            end
          end,
        })
      end

      -- Server overrides. These are merged on top of nvim-lspconfig's lsp/<name>.lua
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
            -- Inlay hints are off by default in lua-language-server
            hint = { enable = true },
          },
        },
      })
      -- lua-language-server sometimes never exits after the "exit"
      -- notification, so force-stop it after 2 s.
      vim.lsp.config("lua_ls", exit_timeout(2000))

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
            "-data",
            project_dir(paths.lsp_cache.jdtls, config.root_dir),
            "--jvm-arg=-Xmx" .. jvm_mem,
            "--jvm-arg=-XX:MaxMetaspaceSize=" .. metaspace,
          }, dispatchers, config)
        end,
        flags = {
          debounce_text_changes = is_mac and 800 or 500, -- Higher debounce on macOS
        },
        settings = {
          java = {
            -- Default JDK for projects that don't name one. java.home is the
            -- key jdtls reads; vscode-java's java.jdt.ls.java.home, which
            -- replaced java.home there, only picks the JDK VS Code launches
            -- jdtls with and is ignored by the server. Left unset without
            -- JAVA_HOME, so jdtls picks a JDK itself.
            home = vim.env.JAVA_HOME ~= "" and vim.env.JAVA_HOME or nil,
            eclipse = { downloadSources = true },
            maven = { downloadSources = true },
            implementationsCodeLens = { enabled = true },
            referencesCodeLens = { enabled = true },
          },
        },
      })
      -- JVM servers. Both normally exit within a couple of seconds, but take
      -- longer while importing a Gradle/Maven project on a slow machine (CI
      -- saw kotlin-lsp still running 10 s after exit, see #37 and #40).
      vim.lsp.config("jdtls", exit_timeout(jvm_exit_timeout))

      -- kotlin-lsp (JetBrains official). Mason's kotlin-lsp package links its
      -- launcher into mason/bin as intellij-server, the same command
      -- nvim-lspconfig's lsp/kotlin_lsp.lua uses; filetypes and root markers
      -- come from there too. Only the per-project --system-path is added.
      vim.lsp.config("kotlin_lsp", {
        cmd = function(dispatchers, config)
          return start_rpc({
            "intellij-server",
            "--stdio",
            "--system-path",
            project_dir(paths.lsp_cache.kotlin_lsp, config.root_dir),
          }, dispatchers, config)
        end,
      })
      vim.lsp.config("kotlin_lsp", exit_timeout(jvm_exit_timeout))

      -- Buffer-local keymaps, set only where a server is attached so builtins
      -- like gd keep working in other buffers. References, rename, code action,
      -- implementation and document symbols come from Neovim's built-in
      -- defaults (grr, grn, gra, gri, gO), and so does K. lsp-zero's gi/go are
      -- left out since they shadow builtins and gI/gy already cover them;
      -- <F3> is left out so formatting goes through conform.
      local buffer_maps = {
        { "n", "gd", vim.lsp.buf.definition, "LSP: Go to definition" },
        { "n", "gD", vim.lsp.buf.declaration, "LSP: Go to declaration" },
        { "n", "gI", vim.lsp.buf.implementation, "LSP: Go to implementation" },
        { "n", "gy", vim.lsp.buf.type_definition, "LSP: Go to type definition" },
        { "n", "gs", vim.lsp.buf.signature_help, "LSP: Show function signature" },
        -- Neovim's own insert <C-s> for this is taken by save (core/keymaps.lua).
        -- Shadows digraph entry (<C-k>{char1}{char2}) in LSP buffers only.
        { "i", "<C-k>", vim.lsp.buf.signature_help, "LSP: Show function signature" },
        { "n", "<F2>", vim.lsp.buf.rename, "LSP: Rename symbol" },
        { { "n", "x" }, "<F4>", vim.lsp.buf.code_action, "LSP: Code actions" },
        { "n", "<leader>ca", vim.lsp.buf.code_action, "LSP: Code actions" },
        { "n", "<leader>cr", vim.lsp.buf.rename, "LSP: Rename symbol" },
        { "n", "<leader>cl", vim.lsp.codelens.run, "LSP: Run code lens" },
        -- Android Studio-like keybindings (Mac)
        { "n", "<D-b>", vim.lsp.buf.definition, "LSP: Go to definition (Cmd+B)" },
        { "n", "<D-A-b>", vim.lsp.buf.implementation, "LSP: Go to implementation (Cmd+Opt+B)" },
        { "n", "<A-F7>", vim.lsp.buf.references, "LSP: Find usages (Opt+F7)" },
        { "n", "<S-F6>", vim.lsp.buf.rename, "LSP: Rename (Shift+F6)" },
        { "n", "<A-CR>", vim.lsp.buf.code_action, "LSP: Code actions (Opt+Enter)" },
      }

      -- Code lenses (jdtls reference/implementation counts, rust-analyzer's
      -- run/references lenses). 0.12 refreshes them itself once enabled, and
      -- maps grx to vim.lsp.codelens.run. 0.11 only shows lenses after
      -- vim.lsp.codelens.refresh(), which 0.12 deprecates, so on 0.11 the
      -- LspAttach handler below refreshes them and maps grx.
      local native_codelens = vim.lsp.codelens.enable ~= nil
      if native_codelens then
        vim.lsp.codelens.enable(true)
      else
        table.insert(buffer_maps, { "n", "grx", vim.lsp.codelens.run, "LSP: Run code lens" })
      end

      --- 0.11: refresh code lenses now and whenever the buffer is entered or
      --- changed, once per buffer. Only called on 0.11, where refresh() isn't
      --- deprecated; the disable comments are for linting against 0.12.
      local function refresh_codelens(bufnr)
        if vim.b[bufnr].user_codelens_refresh then
          return
        end
        vim.b[bufnr].user_codelens_refresh = true
        ---@diagnostic disable-next-line: deprecated
        vim.lsp.codelens.refresh({ bufnr = bufnr })
        vim.api.nvim_create_autocmd({ "BufEnter", "InsertLeave", "BufWritePost" }, {
          group = vim.api.nvim_create_augroup("user_codelens_" .. bufnr, { clear = true }),
          buffer = bufnr,
          desc = "Refresh code lenses",
          callback = function()
            ---@diagnostic disable-next-line: deprecated
            vim.lsp.codelens.refresh({ bufnr = bufnr })
          end,
        })
      end

      -- Inlay hints (inferred types, parameter names) in every buffer whose
      -- server provides them. <leader>uh turns them off and on everywhere.
      vim.lsp.inlay_hint.enable(true)
      vim.keymap.set("n", "<leader>uh", function()
        local enable = not vim.lsp.inlay_hint.is_enabled()
        vim.lsp.inlay_hint.enable(enable)
        vim.notify("Inlay hints " .. (enable and "on" or "off"), vim.log.levels.INFO)
      end, { desc = "Toggle inlay hints" })

      -- Format on save, hls and clangd included, is done by conform (formatting.lua).
      local attach_group = vim.api.nvim_create_augroup("user_lsp_attach", { clear = true })

      vim.api.nvim_create_autocmd("LspAttach", {
        group = attach_group,
        callback = function(args)
          for _, m in ipairs(buffer_maps) do
            vim.keymap.set(m[1], m[2], m[3], { buffer = args.buf, desc = m[4] })
          end
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if not native_codelens and client and client:supports_method("textDocument/codeLens", args.buf) then
            refresh_codelens(args.buf)
          end
        end,
      })

      -- Remove the maps again once the last client leaves the buffer, so gd
      -- and the others go back to their builtins. The detaching client is
      -- still listed while LspDetach runs, so it is skipped here.
      vim.api.nvim_create_autocmd("LspDetach", {
        group = attach_group,
        callback = function(args)
          local bufnr = args.buf
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
            if client.id ~= args.data.client_id then
              return
            end
          end
          for _, m in ipairs(buffer_maps) do
            pcall(vim.keymap.del, m[1], m[2], { buffer = bufnr })
          end
          if vim.b[bufnr].user_codelens_refresh then
            vim.b[bufnr].user_codelens_refresh = nil
            pcall(vim.api.nvim_del_augroup_by_name, "user_codelens_" .. bufnr)
          end
        end,
      })

      -- Installed by Mason
      local mason_servers = {
        "gradle_ls",
        "jedi_language_server",
        "lua_ls",
        "hls",
        "clangd",
        "jdtls",
        "kotlin_lsp",
      }

      -- Formatters for conform (lua/plugins/formatting.lua), installed by
      -- Mason below. Mason package names, read by .github/scripts/ci_warmup.lua.
      vim.g.mason_tools = { "ktfmt", "google-java-format", "stylua" }
      -- Versions for tools that must not follow Mason's latest. Mason installs
      -- this version, and reinstalls it if a different one is installed (e.g.
      -- after updating it in :Mason). stylua must match STYLUA_VERSION in
      -- .github/workflows/test.yml, since another release can format the
      -- same code differently than make lint and CI expect.
      vim.g.mason_tool_versions = { stylua = "v2.6.0" }

      -- Only these servers are enabled, whatever else Mason has installed.
      -- rust-analyzer comes from rustup (bootstrap.sh) so it matches the toolchain.
      local servers = vim.list_extend({ "rust_analyzer" }, mason_servers)
      vim.lsp.enable(servers)

      local mason = utils.safe_require("mason", "mason failed to load")
      if not mason then
        return
      end

      mason.setup({})

      local mason_lsp = utils.safe_require("mason-lspconfig", "mason-lspconfig failed to load")
      if not mason_lsp then
        return
      end

      -- automatic_enable defaults to true in mason-lspconfig v2, which would
      -- vim.lsp.enable() every Mason-installed server, not just the list above
      mason_lsp.setup({
        ensure_installed = mason_servers,
        automatic_enable = false,
      })

      -- ensure_installed for vim.g.mason_tools, done the way mason-lspconfig
      -- does it for servers: after a registry refresh, and not in headless
      -- mode, where nvim may quit before an install finishes. mason.setup()
      -- puts mason/bin first on PATH, so conform finds the tools there.
      if #vim.api.nvim_list_uis() > 0 then
        local registry = require("mason-registry")
        registry.refresh(vim.schedule_wrap(function()
          for _, name in ipairs(vim.g.mason_tools) do
            local ok, pkg = pcall(registry.get_package, name)
            local version = vim.g.mason_tool_versions[name]
            local wrong_version = ok and version and pkg:is_installed() and pkg:get_installed_version() ~= version
            if ok and (not pkg:is_installed() or wrong_version) and not pkg:is_installing() then
              pkg:install(
                { version = version },
                vim.schedule_wrap(function(success)
                  if not success then
                    vim.notify("Mason failed to install " .. name .. ", see :Mason and :MasonLog", vim.log.levels.ERROR)
                  end
                end)
              )
            end
          end
        end))
      end
    end,
  },

  -- https://github.com/j-hui/fidget.nvim
  -- Shows LSP $/progress (jdtls and kotlin-lsp importing a Gradle project,
  -- rust-analyzer indexing) in the bottom-right corner. Only progress:
  -- vim.notify is left alone (notification.override_vim_notify stays false).
  {
    "j-hui/fidget.nvim",
    version = "^1",
    event = "LspAttach",
    opts = {},
  },
}

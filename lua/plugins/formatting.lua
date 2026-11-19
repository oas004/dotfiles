-- Formatting via conform.nvim
--
--   kotlin     -> ktfmt (kotlinlang style), manual only (:KotlinFormat or <leader>cf)
--   java       -> google-java-format, on save
--   rust       -> rustfmt, on save
--   haskell    -> hls (ormolu, see language-server.lua), on save
--   c/cpp/objc -> clangd (.clang-format, else LLVM style), on save
--   json       -> jq / prettierd / prettier, manual only
--   lua        -> stylua, on save, only in projects with a stylua.toml or
--                 .stylua.toml (this repo has one); otherwise not on save

-- Filetypes formatted by their language server. They list no CLI formatter,
-- so lsp_format = "fallback" sends them straight to the server, and `name`
-- keeps any other client attached to the buffer from formatting as well.
local lsp_formatters = {
  haskell = "hls",
  lhaskell = "hls",
  c = "clangd",
  cpp = "clangd",
  objc = "clangd",
  objcpp = "clangd",
}

local formatters_by_ft = {
  kotlin = { "ktfmt" },
  java = { "google-java-format" },
  rust = { "rustfmt" },
  lua = { "stylua" },
  json = { "jq", "prettierd", "prettier", stop_after_first = true },
}
for ft, server in pairs(lsp_formatters) do
  formatters_by_ft[ft] = { lsp_format = "fallback", name = server }
end

-- Filetypes conform formats on save. Everything else is left alone.
local format_on_save_filetypes = {
  java = true,
  rust = true,
  lua = true,
}

-- Filetypes formatted on save only when this formatter can run. stylua needs
-- a stylua.toml or .stylua.toml (require_cwd below). Without one, saving would
-- warn "Formatters unavailable" every time, or with lsp_format = "fallback"
-- reformat the file in lua_ls's own style.
local on_save_only_with = {
  lua = "stylua",
}
for ft in pairs(lsp_formatters) do
  format_on_save_filetypes[ft] = true
end

-- How long formatting may block. CLI formatters get 5 s. hls and clangd get
-- 10 s, as with the LspAttach autocmd this replaced: before running ormolu,
-- hls waits for the project's GHC session, which can take several seconds
-- after the server starts. If the timeout is hit the file is saved
-- unformatted and conform shows a warning.
local function timeout_ms(bufnr)
  return lsp_formatters[vim.bo[bufnr].filetype] and 10000 or 5000
end

local function format_on_save(bufnr)
  if not format_on_save_filetypes[vim.bo[bufnr].filetype] then
    return nil
  end
  local required = on_save_only_with[vim.bo[bufnr].filetype]
  if required and not require("conform").get_formatter_info(required, bufnr).available then
    return nil
  end
  -- java and rust fall back to their language server (jdtls / rust-analyzer)
  -- if the CLI tool is missing.
  return { timeout_ms = timeout_ms(bufnr), lsp_format = "fallback" }
end

--- Format the current buffer with its conform formatters only (no LSP) and report the result.
local function format_buffer_strict(filetype, label)
  if vim.bo.filetype ~= filetype then
    vim.notify(label .. "Format can only be used on " .. label .. " files", vim.log.levels.ERROR)
    return
  end

  -- quiet = true: this callback reports the result, so conform doesn't notify as well.
  require("conform").format(
    { async = false, lsp_format = "never", timeout_ms = 5000, quiet = true },
    function(err, did_edit)
      if err then
        vim.notify(
          "Failed to format " .. label .. " file (see :ConformInfo): " .. vim.trim(tostring(err)),
          vim.log.levels.ERROR
        )
      elseif did_edit then
        vim.notify("Formatted " .. label .. " file", vim.log.levels.INFO)
      else
        vim.notify(label .. " file already formatted", vim.log.levels.INFO)
      end
    end
  )
end

return {
  {
    "stevearc/conform.nvim",
    -- Loaded on the first save, <leader>cf, :ConformInfo, or when
    -- :KotlinFormat / :JavaFormat require it. conform.setup() creates its
    -- BufWritePre autocmd while lazy.nvim handles the first BufWritePre, and
    -- lazy.nvim then runs it for that write too.
    event = "BufWritePre",
    cmd = "ConformInfo",
    keys = {
      {
        "<leader>cf",
        function()
          require("conform").format({ async = false, timeout_ms = timeout_ms(0), lsp_format = "fallback" })
        end,
        mode = "n",
        desc = "Format buffer",
      },
    },
    opts = {
      formatters_by_ft = formatters_by_ft,
      formatters = {
        ktfmt = {
          prepend_args = { "--kotlinlang-style" },
        },
        -- conform's stylua runs in the directory of the nearest stylua.toml
        -- or .stylua.toml; require_cwd makes it unavailable when there is
        -- none, so Lua files elsewhere are left as they are.
        stylua = {
          require_cwd = true,
        },
      },
      format_on_save = format_on_save,
    },
    -- The commands are created at startup rather than in config, so they
    -- exist before conform is loaded. require("conform") loads it.
    init = function()
      vim.api.nvim_create_user_command("KotlinFormat", function()
        format_buffer_strict("kotlin", "Kotlin")
      end, { desc = "Format Kotlin buffer with ktfmt" })

      vim.api.nvim_create_user_command("JavaFormat", function()
        format_buffer_strict("java", "Java")
      end, { desc = "Format Java buffer with google-java-format" })
    end,
  },
}

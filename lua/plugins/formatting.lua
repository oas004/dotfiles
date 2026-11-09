-- Formatting via conform.nvim
--
--   kotlin -> ktfmt (kotlinlang style), manual only (:KotlinFormat or <leader>fm)
--   java   -> google-java-format, on save
--   rust   -> rustfmt, on save
--   json   -> jq / prettierd / prettier, manual only
--
-- Format on save for haskell and c/cpp goes through their language servers
-- (see language-server.lua), so format_on_save below returns nil for those.

-- Filetypes conform formats on save. Everything else is left alone.
local format_on_save_filetypes = {
  java = true,
  rust = true,
}

local function format_on_save(bufnr)
  if not format_on_save_filetypes[vim.bo[bufnr].filetype] then
    return nil
  end
  -- Fall back to the LSP formatter (jdtls / rust-analyzer) if the CLI tool is missing.
  return { timeout_ms = 5000, lsp_format = "fallback" }
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
        vim.notify("Failed to format " .. label .. " file (see :ConformInfo): "
          .. vim.trim(tostring(err)), vim.log.levels.ERROR)
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
    lazy = false,  -- Load immediately so format_on_save and commands are always available
    priority = 40, -- Load after LSP
    keys = {
      {
        "<leader>fm",
        function()
          require("conform").format({ async = false, timeout_ms = 5000, lsp_format = "fallback" })
        end,
        mode = "n",
        desc = "Format buffer",
      },
    },
    opts = {
      formatters_by_ft = {
        kotlin = { "ktfmt" },
        java = { "google-java-format" },
        rust = { "rustfmt" },
        json = { "jq", "prettierd", "prettier", stop_after_first = true },
      },
      formatters = {
        ktfmt = {
          prepend_args = { "--kotlinlang-style" },
        },
      },
      format_on_save = format_on_save,
    },
    config = function(_, opts)
      require("conform").setup(opts)

      vim.api.nvim_create_user_command("KotlinFormat", function()
        format_buffer_strict("kotlin", "Kotlin")
      end, { desc = "Format Kotlin buffer with ktfmt" })

      vim.api.nvim_create_user_command("JavaFormat", function()
        format_buffer_strict("java", "Java")
      end, { desc = "Format Java buffer with google-java-format" })
    end,
  },
}

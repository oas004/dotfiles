-- https://github.com/mfussenegger/nvim-lint
-- Linters for what the language servers don't check:
--
--   kotlin   -> detekt (code smells; kotlin-lsp runs no linter), on open and save
--   sh, bash -> shellcheck, on open and save
--   lua      -> selene, on open, save and leaving insert mode, only in
--               projects with a selene.toml
--
-- Python is left to the ruff language server. All three linters are
-- installed by Mason (vim.g.mason_tools in language-server.lua). A linter
-- that isn't installed is skipped without a message, and nvim-lint itself
-- only loads once a buffer has a linter to run.

-- detekt and shellcheck read the file from disk, so linting them on
-- InsertLeave would check the last saved version. selene reads the buffer.
local linters_by_ft = {
  kotlin = { "detekt" },
  sh = { "shellcheck" },
  bash = { "shellcheck" },
  lua = { "selene" },
}
local on_insert_leave = { selene = true }

-- Project-level detekt files, relative to the project root. The first match
-- of each list is used. config/detekt/detekt.yml is where detekt's Gradle
-- plugin looks by default.
local detekt_configs = { "config/detekt/detekt.yml", "detekt.yml", ".detekt.yml" }
local detekt_baselines = { "config/detekt/baseline.xml", "detekt-baseline.xml" }

--- The Gradle project root of path (settings.gradle[.kts]), else its git
--- root, else its directory.
---@param path string
---@return string
local function project_root(path)
  return vim.fs.root(path, { "settings.gradle.kts", "settings.gradle" })
    or vim.fs.root(path, ".git")
    or vim.fs.dirname(path)
end

---@param root string
---@param candidates string[]
---@return string?
local function first_file(root, candidates)
  for _, rel in ipairs(candidates) do
    local path = root .. "/" .. rel
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

--- detekt for the current buffer's file. nvim-lint's own detekt definition
--- passes the file as --base-path with no --input, so detekt would analyse
--- the whole working directory.
local function detekt()
  local file = vim.api.nvim_buf_get_name(0)
  local root = project_root(file)
  local args = { "--input", file }
  local config = first_file(root, detekt_configs)
  if config then
    -- Like the Gradle plugin's buildUponDefaultConfig: the project file
    -- only has to list what it changes
    vim.list_extend(args, { "--config", config, "--build-upon-default-config" })
  end
  local baseline = first_file(root, detekt_baselines)
  if baseline then
    vim.list_extend(args, { "--baseline", baseline })
  end
  return {
    name = "detekt",
    cmd = "detekt",
    args = args,
    stdin = false,
    append_fname = false,
    cwd = root,
    stream = "stdout",
    -- detekt exits 2 when it finds issues
    ignore_exitcode = true,
    -- /path/File.kt:5:22: This expression contains a magic number. [MagicNumber]
    -- Only the buffer's file is analysed, so the path isn't checked.
    parser = require("lint.parser").from_pattern(
      "^(.-):(%d+):(%d+): (.+) %[([%w]+)%]$",
      { "path", "lnum", "col", "message", "code" },
      nil,
      { source = "detekt", severity = vim.diagnostic.severity.WARN }
    ),
  }
end

--- Working directory for linter in buffer, or nil if it shouldn't run there.
---@param linter string
---@param bufnr integer
---@return string?
local function linter_cwd(linter, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or vim.fn.executable(linter) == 0 then
    return nil
  end
  if linter == "selene" then
    -- selene reads selene.toml (and the std it names) from its cwd
    return vim.fs.root(path, "selene.toml")
  end
  return vim.fs.dirname(path)
end

---@param bufnr integer
---@param event string
local function lint_buffer(bufnr, event)
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return
  end
  for _, linter in ipairs(linters_by_ft[vim.bo[bufnr].filetype] or {}) do
    local cwd = (event ~= "InsertLeave" or on_insert_leave[linter]) and linter_cwd(linter, bufnr)
    if cwd then
      vim.api.nvim_buf_call(bufnr, function()
        -- detekt's definition sets its own cwd (the project root)
        require("lint").try_lint(linter, { cwd = linter ~= "detekt" and cwd or nil })
      end)
    end
  end
end

return {
  {
    "mfussenegger/nvim-lint",
    -- Loaded by the require("lint") in lint_buffer
    lazy = true,
    init = function()
      -- FileType covers opening a file, and also lints again when the
      -- filetype is changed (e.g. :set filetype=bash).
      vim.api.nvim_create_autocmd({ "FileType", "BufWritePost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("user_lint", { clear = true }),
        desc = "Run linters (nvim-lint)",
        callback = function(args)
          lint_buffer(args.buf, args.event)
        end,
      })
    end,
    config = function()
      require("lint").linters.detekt = detekt
    end,
  },
}

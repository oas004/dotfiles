-- Editor/UI tests: statusline, colorscheme, diagnostic keymaps, leader map
-- prefixes, file explorer, snacks.picker config and pickers, plugin pins vs
-- lazy-lock.json
-- Run with: nvim --headless -c "luafile tests/ui_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_not_nil, assert_eq = h.test, h.assert_true, h.assert_not_nil, h.assert_eq
local find_keymap = h.find_keymap
local assert_no_leader_prefix_collisions = h.assert_no_leader_prefix_collisions

h.wait_for_lazy()

h.out("\n=== UI Tests ===\n")

test("telescope and plenary are no longer installed", function()
  local plugins = require("lazy.core.config").plugins
  for _, name in ipairs({ "telescope.nvim", "telescope-fzf-native.nvim", "plenary.nvim" }) do
    assert_true(plugins[name] == nil, name .. " still has a spec")
  end
end)

test("no <leader> map is a prefix of another (before lazy-loading)", function()
  assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
end)

-- Colorscheme overrides
test("nordic highlight overrides survive :colorscheme", function()
  local function comment_fg()
    return vim.api.nvim_get_hl(0, { name = "Comment" }).fg
  end
  assert_true(vim.g.colors_name == "nordic", "colorscheme is " .. tostring(vim.g.colors_name))
  assert_true(comment_fg() == 0xb8cde6, "Comment override not applied at startup")
  vim.cmd.colorscheme("default")
  vim.cmd.colorscheme("nordic")
  assert_true(comment_fg() == 0xb8cde6, "Comment override lost after :colorscheme nordic")
  assert_true(vim.api.nvim_get_hl(0, { name = "Search" }).bold == true, "Search override lost")
end)

-- Open a real file so BufReadPre fires and lazy loads event-triggered plugins
vim.cmd("edit README.md")
vim.wait(2000, function()
  return package.loaded["lualine"] ~= nil
end)

-- Lualine
test("lualine is loaded after opening a file", function()
  assert_not_nil(package.loaded["lualine"], "lualine was not required (setup never ran)")
end)

test("statusline is set by lualine", function()
  local sl = vim.o.statusline
  assert_true(sl ~= nil and sl ~= "", "statusline is empty")
  assert_true(sl:find("lualine", 1, true) ~= nil, "statusline not driven by lualine: " .. sl)
end)

test("lualine uses the nordic theme", function()
  local cfg = require("lualine").get_config()
  assert_true(cfg.options.theme == "nordic", "theme is " .. vim.inspect(cfg.options.theme))
end)

-- Diagnostic keymaps
test("<leader>e (next diagnostic) keymap exists", function()
  local m = find_keymap("n", "<leader>e")
  assert_not_nil(m, "<leader>e not mapped")
  ---@cast m -nil
  assert_true(m.desc == "Next diagnostic", "unexpected desc: " .. tostring(m.desc))
end)

test("<leader>E (prev diagnostic) keymap exists", function()
  local m = find_keymap("n", "<leader>E")
  assert_not_nil(m, "<leader>E not mapped")
  ---@cast m -nil
  assert_true(m.desc == "Prev diagnostic", "unexpected desc: " .. tostring(m.desc))
end)

test("diagnostic keymaps jump without errors", function()
  local buf = vim.api.nvim_get_current_buf()
  local ns = vim.api.nvim_create_namespace("ui_test")
  vim.diagnostic.set(ns, buf, {
    { lnum = 2, col = 0, message = "first", severity = vim.diagnostic.severity.WARN },
    { lnum = 5, col = 0, message = "second", severity = vim.diagnostic.severity.WARN },
  })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  find_keymap("n", "<leader>e").callback()
  assert_true(vim.api.nvim_win_get_cursor(0)[1] == 3, "next did not move to line 3")
  find_keymap("n", "<leader>E").callback()
  -- Already on the first diagnostic, so prev wraps to the last one
  assert_true(vim.api.nvim_win_get_cursor(0)[1] == 6, "prev did not wrap to line 6")
  vim.diagnostic.reset(ns, buf)
  -- Close any float opened by jump({ float = true })
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      vim.api.nvim_win_close(win, true)
    end
  end
end)

-- File explorer
test("<leader>l toggles and <leader>L finds the current file in nvim-tree", function()
  local l = find_keymap("n", "<leader>l")
  assert_not_nil(l, "<leader>l not mapped")
  ---@cast l -nil
  assert_true(l.desc == "nvim-tree: Toggle", "unexpected <leader>l desc: " .. tostring(l.desc))
  local L = find_keymap("n", "<leader>L")
  assert_not_nil(L, "<leader>L not mapped")
  ---@cast L -nil
  assert_true(L.desc == "nvim-tree: Find current file", "unexpected <leader>L desc: " .. tostring(L.desc))
  assert_true(find_keymap("n", "<leader>lf") == nil, "<leader>lf still mapped (collides with <leader>l)")
end)

test("<leader>L opens nvim-tree on the current file", function()
  local file = vim.api.nvim_buf_get_name(0)
  require("lazy").load({ plugins = { "nvim-tree.lua" } })
  local L = find_keymap("n", "<leader>L")
  assert_not_nil(L and L.callback, "<leader>L has no callback after nvim-tree loaded")
  ---@cast L -nil
  L.callback()
  vim.wait(500, function()
    return vim.bo.filetype == "NvimTree"
  end)
  assert_true(vim.bo.filetype == "NvimTree", "nvim-tree did not open and focus")
  local node = require("nvim-tree.api").tree.get_node_under_cursor()
  assert_true(
    node and node.absolute_path == file,
    "cursor not on current file: " .. tostring(node and node.absolute_path)
  )
  -- Buffer-local maps in the tree (e.g. lazy ft keys) must not collide either
  assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
  require("nvim-tree.api").tree.close()
end)

-- Pickers (snacks.picker)

-- Record every warning and error from here on, including deprecations
-- raised by plugins. Core deprecations go through vim._truncated_echo_once,
-- which only echoes the first one per session, and plugin deprecations
-- through vim.notify_once, so wrap those to see repeats too.
local warnings = {}
local function record(msg, level)
  if level == nil or level >= vim.log.levels.WARN then
    warnings[tostring(msg)] = true
  end
end
local orig_notify, orig_notify_once, orig_echo_once = vim.notify, vim.notify_once, vim._truncated_echo_once
vim.notify = function(msg, level, opts)
  record(msg, level or vim.log.levels.INFO)
  return orig_notify(msg, level, opts)
end
---@diagnostic disable-next-line: duplicate-set-field
vim.notify_once = function(msg, level, opts)
  record(msg, level or vim.log.levels.INFO)
  return orig_notify_once(msg, level, opts)
end
if orig_echo_once then
  ---@diagnostic disable-next-line: duplicate-set-field
  vim._truncated_echo_once = function(msg)
    record(msg)
    return orig_echo_once(msg)
  end
end

require("lazy").load({ plugins = { "snacks.nvim" } })

test("no <leader> map is a prefix of another (after lazy-loading)", function()
  assert_no_leader_prefix_collisions(vim.api.nvim_get_current_buf())
end)

--- The open pickers, newest last
local function open_pickers()
  return require("snacks").picker.get({ tab = false })
end

--- Wait for a picker to open and its finder to finish, and return it
local function wait_for_picker(count_before)
  local picker
  vim.wait(5000, function()
    local open = open_pickers()
    picker = #open > count_before and open[#open] or nil
    return picker ~= nil and not picker:is_active()
  end, 20)
  return picker
end

local function close_pickers()
  for _, p in ipairs(open_pickers()) do
    p:close()
  end
  vim.wait(500, function()
    return #open_pickers() == 0
  end, 20)
end

local function run(cmd, cwd)
  local res = vim.system(cmd, { cwd = cwd, text = true }):wait()
  assert(res.code == 0, table.concat(cmd, " ") .. ": " .. (res.stderr or ""))
end

-- A small git repository with one commit and one untracked file, so the
-- file, grep and git pickers all have something to show
local repo = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(repo .. "/.github/workflows", "p")
vim.fn.mkdir(repo .. "/node_modules/pkg", "p")
vim.fn.writefile({ "alpha beta", "gamma" }, repo .. "/sample.txt")
vim.fn.writefile({ "ignored.txt" }, repo .. "/.gitignore")
vim.fn.writefile({ "x" }, repo .. "/ignored.txt")
vim.fn.writefile({ "name: x" }, repo .. "/.github/workflows/x.yml")
vim.fn.writefile({ "x" }, repo .. "/node_modules/pkg/index.js")
run({ "git", "init", "-q" }, repo)
run({ "git", "add", "sample.txt", ".gitignore", ".github" }, repo)
run({ "git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "init" }, repo)
vim.fn.writefile({ "new" }, repo .. "/untracked.txt")

--- Files the files picker lists in repo, relative to it
local function listed_files(opts)
  local before = #open_pickers()
  require("snacks").picker.files(vim.tbl_extend("force", { cwd = repo }, opts or {}))
  local picker = wait_for_picker(before)
  assert(picker, "files picker did not open")
  local files = {}
  for _, item in ipairs(picker:items()) do
    files[vim.fs.relpath(repo, vim.fs.joinpath(repo, item.file)) or item.file] = true
  end
  close_pickers()
  return files
end

test("files picker leaves out hidden, git-ignored, .git and node_modules files", function()
  local files = listed_files()
  assert_true(files["sample.txt"] and files["untracked.txt"], "tracked files missing: " .. vim.inspect(files))
  for _, f in ipairs({ ".gitignore", ".github/workflows/x.yml", "ignored.txt", "node_modules/pkg/index.js" }) do
    assert_true(not files[f], f .. " listed: " .. vim.inspect(files))
  end
end)

test("with hidden files on, .github and .gitignore are listed but .git and node_modules are not", function()
  local files = listed_files({ hidden = true })
  assert_true(files[".gitignore"], ".gitignore missing: " .. vim.inspect(files))
  assert_true(files[".github/workflows/x.yml"], ".github/workflows/x.yml missing: " .. vim.inspect(files))
  for f in pairs(files) do
    assert_true(not f:find("^%.git/"), f .. " listed")
    assert_true(not f:find("node_modules", 1, true), f .. " listed")
  end
end)

test("buffers picker deletes the selected buffer with <M-d> and normal-mode <leader>q", function()
  local before = #open_pickers()
  require("snacks").picker.buffers()
  local picker = wait_for_picker(before)
  assert_not_nil(picker, "buffers picker did not open")
  ---@cast picker -nil
  local input = picker.input.win.buf
  -- snacks maps its own <M-d> (inspect) in every picker; this one must delete
  local actions = {}
  for _, m in ipairs({ { "i", "<M-d>" }, { "n", "<M-d>" }, { "n", "<Leader>q" }, { "i", "<Leader>q" } }) do
    local map = find_keymap(m[1], m[2], input)
    actions[m[1] .. " " .. m[2]] = map and map.desc or false
  end
  close_pickers()
  assert_eq(actions, {
    ["i <M-d>"] = "bufdelete",
    ["n <M-d>"] = "bufdelete",
    ["n <Leader>q"] = "bufdelete",
    -- Not in insert mode, where it would fire while typing
    ["i <Leader>q"] = false,
  }, "delete keys in the buffers picker")
end)

-- In-process LSP server that only answers document and workspace symbol
-- requests, so the LSP pickers have something to show without a real server.
local function fake_symbol_server(uri)
  local range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 5 } }
  return h.fake_lsp_server({
    capabilities = { documentSymbolProvider = true, workspaceSymbolProvider = true },
    results = {
      ["textDocument/documentSymbol"] = { { name = "alpha", kind = 12, range = range, selectionRange = range } },
      ["workspace/symbol"] = { { name = "alpha", kind = 12, location = { uri = uri, range = range } } },
    },
  })
end

test("picker maps open the right picker without warnings, errors or deprecations", function()
  local cwd = vim.fn.getcwd()
  vim.cmd.cd(repo)
  local file = repo .. "/sample.txt"
  vim.cmd("edit " .. vim.fn.fnameescape(file))
  local buf = vim.api.nvim_get_current_buf()
  local client_id = vim.lsp.start({
    name = "ui_test_symbols",
    cmd = fake_symbol_server(vim.uri_from_fname(file)),
    root_dir = repo,
  }, { bufnr = buf })
  assert_not_nil(client_id, "fake LSP client did not start")
  ---@cast client_id -nil
  vim.wait(2000, function()
    local client = vim.lsp.get_client_by_id(client_id)
    return client ~= nil and client.initialized == true
  end)
  local ns = vim.api.nvim_create_namespace("ui_test_pickers")
  vim.diagnostic.set(
    ns,
    buf,
    { { lnum = 0, col = 0, message = "test warning", severity = vim.diagnostic.severity.WARN } }
  )

  vim.cmd("messages clear")
  vim.v.errmsg = ""
  local problems = {}
  -- map, mode, expected picker source. Resume reopens the one before it.
  local pickers = {
    { "<leader>ff", "n", "files" },
    { "<leader>fg", "n", "grep" },
    { "<leader>fb", "n", "buffers" },
    { "<leader>fr", "n", "recent" },
    { "<leader>fs", "n", "lsp_symbols" },
    { "<leader>fS", "n", "lsp_workspace_symbols" },
    { "<leader>fd", "n", "diagnostics_buffer" },
    { "<leader>fD", "n", "diagnostics" },
    { "<leader>fh", "n", "help" },
    { "<leader>fw", "n", "grep_word" },
    { "<leader>fw", "x", "grep_word" },
    { "<leader>fk", "n", "keymaps" },
    { "<leader>f.", "n", "keymaps" },
    { "<leader>gs", "n", "git_status" },
    { "<leader>gl", "n", "git_log" },
    { "<leader>gL", "n", "git_log_file" },
    -- The old single-letter aliases
    { "<leader>p", "n", "files" },
    { "<leader>o", "n", "buffers" },
    { "<leader>r", "n", "recent" },
    { "<leader>s", "n", "lsp_symbols" },
    { "<leader>S", "n", "lsp_workspace_symbols" },
    -- Android Studio-style Cmd maps
    { "<D-S-o>", "n", "files" },
    { "<D-o>", "n", "lsp_symbols" },
    { "<D-A-o>", "n", "lsp_workspace_symbols" },
    { "<D-S-f>", "n", "grep" },
    { "<D-e>", "n", "recent" },
  }
  for _, p in ipairs(pickers) do
    local lhs, mode, source = p[1], p[2], p[3]
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    local m = find_keymap(mode, lhs)
    if not (m and m.callback) then
      table.insert(problems, mode .. " " .. lhs .. " has no callback")
    else
      if mode == "x" then
        -- Select "alpha", the word the picker should search for
        vim.cmd("normal! viw")
      end
      local before = #open_pickers()
      m.callback()
      if mode == "x" then
        vim.cmd("normal! \27")
      end
      local picker = wait_for_picker(before)
      if not picker then
        table.insert(problems, ("%s %s (%s) did not open"):format(mode, lhs, source))
      else
        if picker.opts.source ~= source then
          table.insert(problems, ("%s %s opened %q, expected %q"):format(mode, lhs, picker.opts.source, source))
        end
        if source == "grep_word" and picker:count() == 0 then
          table.insert(problems, ("%s %s found nothing for the word under the cursor"):format(mode, lhs))
        end
        close_pickers()
      end
    end
  end

  vim.diagnostic.reset(ns, buf)
  h.stop_client(assert(vim.lsp.get_client_by_id(client_id)))
  vim.cmd.cd(cwd)
  for msg in pairs(warnings) do
    table.insert(problems, "warning: " .. msg)
  end
  for _, line in ipairs(h.message_errors()) do
    table.insert(problems, "message: " .. line)
  end
  if vim.v.errmsg ~= "" then
    table.insert(problems, "v:errmsg: " .. vim.v.errmsg)
  end
  table.sort(problems)
  assert_true(#problems == 0, table.concat(problems, "\n  "))
end)

vim.fn.delete(repo, "rf")

-- lazy installs and restores the commit in lazy-lock.json, not the tag or
-- commit in the spec, so a pin that disagrees with the lockfile is ignored.
test("plugins pinned by tag or commit are locked at that pin", function()
  local Config = require("lazy.core.config")
  local lock = vim.json.decode(table.concat(vim.fn.readfile(Config.options.lockfile), "\n"))
  local problems = {}
  for name, plugin in pairs(Config.plugins) do
    local entry = lock[name]
    if (plugin.tag or plugin.commit) and not plugin._.is_local then
      if not entry then
        table.insert(problems, name .. " has no lazy-lock.json entry")
      elseif plugin.commit then
        if entry.commit:sub(1, #plugin.commit) ~= plugin.commit then
          table.insert(problems, ("%s: spec commit %s, lazy-lock.json %s"):format(name, plugin.commit, entry.commit))
        end
      else
        local res = vim
          .system(
            { "git", "rev-parse", "--verify", "--quiet", "refs/tags/" .. plugin.tag .. "^{commit}" },
            { cwd = plugin.dir, text = true }
          )
          :wait()
        local tag_commit = vim.trim(res.stdout or "")
        if res.code ~= 0 or tag_commit == "" then
          table.insert(problems, ("%s: tag %s not found in %s"):format(name, plugin.tag, plugin.dir))
        elseif tag_commit ~= entry.commit then
          table.insert(
            problems,
            ("%s: tag %s is %s, lazy-lock.json %s"):format(name, plugin.tag, tag_commit, entry.commit)
          )
        end
      end
    end
  end
  table.sort(problems)
  assert_true(#problems == 0, table.concat(problems, "\n  "))
end)

h.finish()

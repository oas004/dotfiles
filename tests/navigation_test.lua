-- Window navigation tests: lua/plugins/navigation.lua (smart-splits.nvim)
-- Run with: nvim --headless -c "luafile tests/navigation_test.lua"

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

h.out("\n=== Navigation Tests ===\n")

local config_dir = vim.fn.resolve(vim.fn.stdpath("config"))

local maps = {
  ["<C-h>"] = "Window: Move left (or tmux pane)",
  ["<C-j>"] = "Window: Move down (or tmux pane)",
  ["<C-k>"] = "Window: Move up (or tmux pane)",
  ["<C-l>"] = "Window: Move right (or tmux pane)",
  ["<A-h>"] = "Window: Resize left",
  ["<A-j>"] = "Window: Resize down",
  ["<A-k>"] = "Window: Resize up",
  ["<A-l>"] = "Window: Resize right",
}

local function feed(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
end

-- Start from a single empty window
local function reset_windows()
  vim.cmd("enew")
  vim.cmd("silent only")
end

test("smart-splits is loaded at startup", function()
  -- The tmux backend only marks the pane as running Neovim once it loads
  assert_true(h.plugin_loaded("smart-splits.nvim"), "smart-splits.nvim not loaded")
end)

test("move and resize maps exist in normal mode with a desc", function()
  for lhs, desc in pairs(maps) do
    local m = h.find_keymap("n", lhs)
    assert_true(m ~= nil, lhs .. " not mapped in normal mode")
    ---@cast m -nil
    assert_eq(m.desc, desc, lhs .. " desc")
  end
end)

test("the keys are not mapped in insert, visual or terminal mode", function()
  -- Terminal mode: the keys go to the program (Claude Code). Insert mode:
  -- <C-k> is LSP signature help, set per buffer by language-server.lua.
  for lhs in pairs(maps) do
    for _, mode in ipairs({ "i", "x", "t" }) do
      assert_eq(h.find_keymap(mode, lhs), nil, lhs .. " mapped in mode " .. mode)
    end
  end
end)

-- Three windows in a row (split_cmd "vsplit") or column ("split"), with the
-- middle one current. Three, because at the edge smart-splits wraps around,
-- so with two windows moving either way ends up in the other one.
local function three_windows(split_cmd)
  reset_windows()
  local first = vim.api.nvim_get_current_win()
  vim.cmd("rightbelow " .. split_cmd)
  local middle = vim.api.nvim_get_current_win()
  vim.cmd("rightbelow " .. split_cmd)
  local last = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(middle)
  return first, middle, last
end

-- From the middle window, `back` must reach first and `forward` last
local function check_moves(split_cmd, back, forward)
  local first, middle, last = three_windows(split_cmd)
  feed(back)
  assert_eq(vim.api.nvim_get_current_win(), first, "window after " .. back)
  vim.api.nvim_set_current_win(middle)
  feed(forward)
  assert_eq(vim.api.nvim_get_current_win(), last, "window after " .. forward)
  reset_windows()
end

test("<C-h> and <C-l> move between vertical splits", function()
  check_moves("vsplit", "<C-h>", "<C-l>")
end)

test("<C-k> and <C-j> move between horizontal splits", function()
  check_moves("split", "<C-k>", "<C-j>")
end)

test("<A-l> and <A-h> resize a vertical split", function()
  reset_windows()
  vim.cmd("rightbelow vsplit")
  vim.cmd("wincmd h")
  local win = vim.api.nvim_get_current_win()
  local before = vim.api.nvim_win_get_width(win)
  feed("<A-l>")
  local wider = vim.api.nvim_win_get_width(win)
  assert_true(wider ~= before, "<A-l> did not change the width (" .. before .. ")")
  feed("<A-h>")
  assert_eq(vim.api.nvim_win_get_width(win), before, "width after <A-l><A-h>")
  reset_windows()
end)

-- The backend is chosen by a function in the spec, so check it with and
-- without a UI. Headless, it must not pick tmux: every test nvim started
-- inside tmux would otherwise set and clear @pane-is-vim on that pane.
test("tmux backend is only used with a UI attached", function()
  local spec = dofile(config_dir .. "/lua/plugins/navigation.lua")[1]
  local backend = spec.opts.mux.backend
  assert_eq(type(backend), "function", "mux.backend")
  assert_eq(backend(), {}, "backend without a UI")
  local orig = vim.api.nvim_list_uis
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_list_uis = function()
    return { {} }
  end
  local ok, with_ui = pcall(backend)
  vim.api.nvim_list_uis = orig
  assert_true(ok, tostring(with_ui))
  assert_eq(with_ui, "smart-splits-backend-tmux", "backend with a UI")
end)

test("the tmux backend module loads", function()
  local ok, mod = pcall(require, "smart-splits-backend-tmux")
  assert_true(ok, tostring(mod))
  assert_eq(type(mod.detect), "function", "detect")
end)

test(":checkhealth smart-splits reports a valid config and no errors or warnings", function()
  vim.cmd("checkhealth smart-splits")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local errors = vim.tbl_filter(function(line)
    return line:find("ERROR", 1, true) ~= nil or line:find("WARNING", 1, true) ~= nil
  end, lines)
  local text = table.concat(lines, "\n")
  assert_true(text:find("config is valid", 1, true) ~= nil, "no 'config is valid' in:\n" .. text)
  assert_eq(errors, {}, "errors or warnings in :checkhealth smart-splits")
  vim.cmd("bwipeout!")
end)

test("no errors in :messages", function()
  h.assert_no_message_errors()
end)

h.finish()

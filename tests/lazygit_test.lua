-- lazygit tests: lua/plugins/lazygit.lua (snacks.lazygit)
-- Run with: nvim --headless -c "luafile tests/lazygit_test.lua"
-- The checks that open lazygit need the lazygit binary on PATH; CI installs
-- it with bootstrap.sh's install_lazygit_release. Without it they are
-- skipped.

---@module "tests.helpers"
local h = dofile(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)) .. "/helpers.lua")
local test, assert_true, assert_eq = h.test, h.assert_true, h.assert_eq

h.wait_for_lazy()

-- A temp lazygit config dir for every lazygit this test starts, so it never
-- writes lazygit state (recent repos, the intro popup) into the user's own.
-- Set before snacks first asks lazygit for its config dir, which it caches.
local lazygit_config_dir = vim.fn.tempname()
vim.env.CONFIG_DIR = lazygit_config_dir

h.out("\n=== lazygit Tests ===\n")

local maps = {
  ["<leader>gg"] = "Git: lazygit",
  ["<leader>gf"] = "Git: lazygit history of the current file",
}

test("<leader>gg and <leader>gf are mapped before snacks loads", function()
  for lhs, desc in pairs(maps) do
    local m = h.find_keymap("n", lhs)
    assert_true(m ~= nil, lhs .. " not mapped")
    ---@cast m -nil
    assert_eq(m.desc, desc, lhs .. " desc")
  end
end)

require("lazy").load({ plugins = { "snacks.nvim" } })

-- The map's callback after snacks loaded (lazy replaces its key stub)
local function callback(lhs)
  local m = h.find_keymap("n", lhs)
  assert_true(m ~= nil and m.callback ~= nil, lhs .. " has no callback")
  ---@cast m -nil
  return m.callback
end

-- Run fn and return the vim.notify calls it made
local function notifications(fn)
  local msgs = {}
  local orig = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg, level)
    table.insert(msgs, { msg = msg, level = level })
  end
  local ok, err = pcall(fn)
  vim.notify = orig
  assert_true(ok, err)
  return msgs
end

local function terminal_bufs()
  return vim.tbl_filter(function(b)
    return vim.bo[b].buftype == "terminal"
  end, vim.api.nvim_list_bufs())
end

local file = vim.fn.tempname() .. ".txt"
vim.fn.writefile({ "hello" }, file)
vim.cmd("silent edit " .. vim.fn.fnameescape(file))

test("without lazygit on PATH, the maps say how to install it", function()
  local path = vim.env.PATH
  vim.env.PATH = vim.fn.tempname()
  local before = #terminal_bufs()
  local ok, msgs = pcall(notifications, function()
    callback("<leader>gg")()
    callback("<leader>gf")()
  end)
  vim.env.PATH = path
  assert_true(ok, msgs)
  assert_eq(#msgs, 2, "notifications: " .. vim.inspect(msgs))
  for _, m in ipairs(msgs) do
    assert_eq(m.level, vim.log.levels.ERROR, "level")
    assert_true(m.msg:find("lazygit is not installed", 1, true) ~= nil, "message: " .. m.msg)
  end
  assert_eq(#terminal_bufs(), before, "terminals opened")
end)

if vim.fn.executable("lazygit") == 0 then
  h.skip("<leader>gf in a buffer without a file only warns", "lazygit not on PATH")
  h.skip("<leader>gg opens lazygit, and e in lazygit opens the file in this Neovim", "lazygit not on PATH")
else
  test("<leader>gf in a buffer without a file only warns", function()
    vim.cmd("enew")
    local before = #terminal_bufs()
    local msgs = notifications(callback("<leader>gf"))
    vim.cmd("buffer #")
    assert_eq(#msgs, 1, "notifications: " .. vim.inspect(msgs))
    assert_eq(msgs[1].level, vim.log.levels.WARN, "level")
    assert_eq(#terminal_bufs(), before, "terminals opened")
  end)

  -- A temp repo with one changed file
  local repo = vim.fn.tempname()
  vim.fn.mkdir(repo, "p")
  local function git(args)
    local res = vim
      .system(
        vim.list_extend(
          { "git", "-c", "user.name=test", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false" },
          args
        ),
        { cwd = repo, text = true, env = { GIT_CONFIG_GLOBAL = "/dev/null" } }
      )
      :wait()
    assert(res.code == 0, res.stderr)
  end
  vim.fn.writefile({ "a" }, repo .. "/changed.txt")
  git({ "init", "-q" })
  git({ "add", "changed.txt" })
  git({ "commit", "-q", "-m", "init" })
  vim.fn.writefile({ "a", "b" }, repo .. "/changed.txt")

  local function screen(buf)
    return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  end

  test("<leader>gg opens lazygit, and e in lazygit opens the file in this Neovim", function()
    local cwd = vim.fn.getcwd()
    vim.cmd.cd(vim.fn.fnameescape(repo))
    local before = terminal_bufs()
    callback("<leader>gg")()
    local buf
    vim.wait(5000, function()
      for _, b in ipairs(terminal_bufs()) do
        if not vim.tbl_contains(before, b) then
          buf = b
          return true
        end
      end
      return false
    end, 20)
    assert_true(buf ~= nil, "no terminal opened")
    ---@cast buf -nil
    local job = vim.b[buf].terminal_job_id
    local ok, err = pcall(function()
      assert_true(vim.api.nvim_buf_get_name(buf):find("lazygit", 1, true) ~= nil, vim.api.nvim_buf_get_name(buf))

      -- snacks writes its config (theme and editPreset) and points lazygit at it
      local theme_path = vim.fs.normalize(vim.fn.stdpath("cache") .. "/lazygit-theme.yml")
      assert_true(
        vim.tbl_contains(vim.split(vim.env.LG_CONFIG_FILE or "", ","), theme_path),
        "LG_CONFIG_FILE is " .. tostring(vim.env.LG_CONFIG_FILE)
      )
      local config = table.concat(vim.fn.readfile(theme_path), "\n")
      assert_true(config:find('editPreset: "nvim-remote"', 1, true) ~= nil, "no nvim-remote editPreset in " .. config)

      -- A fresh config dir gets lazygit's intro popup first; Enter closes it
      local intro = vim.wait(10000, function()
        return screen(buf):find("Thanks for using lazygit", 1, true) ~= nil
      end, 50)
      assert_true(intro, "lazygit did not start:\n" .. screen(buf))
      vim.fn.chansend(job, "\r")
      -- Wait for the files panel's key hints, which lazygit shows once the
      -- popup is gone and the panel has focus; a key sent before that is lost.
      local ready = vim.wait(5000, function()
        local text = screen(buf)
        return text:find("Thanks for using lazygit", 1, true) == nil and text:find("Edit: e", 1, true) ~= nil
      end, 50)
      assert_true(ready, "files panel not focused:\n" .. screen(buf))

      -- e edits the selected file (changed.txt, the only one). The
      -- nvim-remote preset sends it to $NVIM, this Neovim's server address.
      vim.fn.chansend(job, "e")
      -- Compared by real path: the temp dir is under /var, which is a
      -- symlink to /private/var on macOS
      local target = vim.uv.fs_realpath(repo .. "/changed.txt")
      local opened = vim.wait(10000, function()
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          local name = vim.api.nvim_buf_get_name(b)
          if vim.api.nvim_buf_is_loaded(b) and name ~= "" and vim.uv.fs_realpath(name) == target then
            return true
          end
        end
        return false
      end, 50)
      assert_true(opened, "changed.txt not opened in this Neovim; lazygit shows:\n" .. screen(buf))
    end)

    -- Quit lazygit the way a user does. Killing it instead makes snacks'
    -- TermClose handler report the non-zero exit as an error.
    vim.fn.chansend(job, "q")
    local code = vim.fn.jobwait({ job }, 5000)[1]
    if code == -1 then
      vim.fn.jobstop(job)
    end
    vim.cmd.stopinsert()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    vim.cmd.cd(vim.fn.fnameescape(cwd))
    assert_true(ok, err)
    assert_eq(code, 0, "lazygit exit code after q")
  end)

  vim.fn.delete(repo, "rf")
  vim.fn.delete(lazygit_config_dir, "rf")
end

vim.cmd("bwipeout!")
vim.fn.delete(file)

h.finish()

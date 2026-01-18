vim.api.nvim_create_user_command('CustomAdbDevices', function(opts)
  require('custom.adb').devices({ long = opts.bang })
end, { bang = true })

pcall(function() require('telescope').load_extension('adb') end)

vim.keymap.set('n', '<Leader>ad', function()
  require('telescope').extensions.adb.devices({})
end, { desc = 'ADB: pick device' })

-- Adb Install Part

-- :AdbPickInstall (bang => allow downgrade)
vim.api.nvim_create_user_command('AdbPickInstall', function(opts)
  require('custom.adb').install_from_picker({ downgrade = opts.bang })
end, { bang = true })

-- :AdbInstall path/to/file.apk
vim.api.nvim_create_user_command('AdbInstall', function(opts)
  require('custom.adb').install(opts.args, {})
end, { nargs = 1, complete = 'file' })

vim.keymap.set('n', '<Leader>ai', function()
  require('custom.adb').install_from_picker({})
end, { desc = 'ADB: pick & install APK' })

vim.keymap.set('n', '<Leader>aI', function()
  require('custom.adb').install_from_picker({ downgrade = true })
end, { desc = 'ADB: pick & install (downgrade)' })

-- Adb logcat part

-- :AdbLogcat[!] [package]   (bang = clear logs first)
vim.api.nvim_create_user_command('AdbLogcat', function(opts)
  require('custom.adb').logcat({
    serial = vim.g.adb_serial,
    clear  = opts.bang,
    pkg    = (opts.args ~= '' and opts.args or nil),
    pid    = true,          -- use PID filter when pkg provided
    level  = 'I',           -- default minimum level (I=nfo). Change to 'V' for everything.
    format = 'time',
  })
end, { bang = true, nargs = '?' })

-- :AdbLogcatClear
vim.api.nvim_create_user_command('AdbLogcatClear', function()
  require('custom.adb').clear_logcat({ serial = vim.g.adb_serial })
end, {})

vim.keymap.set('n', '<Leader>al', function()
  require('custom.adb').logcat({ serial = vim.g.adb_serial, level = 'I', format = 'time' })
end, { desc = 'ADB: logcat' })

vim.keymap.set('n', '<Leader>aL', function()
  require('custom.adb').logcat({ serial = vim.g.adb_serial, pkg = vim.g.adb_pkg, pid = true, clear = true, level = 'V', format = 'threadtime' })
end, { desc = 'ADB: logcat (pkg, clear, PID, verbose, threadtime)' })

local last_adb_regex = ''

local function start_log_with_regex(rx, opts)
  if not rx or rx == '' then return end
  last_adb_regex = rx
  require('custom.adb').logcat(vim.tbl_extend('force', {
    regex  = rx,
    level  = 'V',      -- show everything;
    format = 'time',
    -- serial = vim.g.adb_serial, -- uncomment if you always want your default device
  }, opts or {}))
end

-- prompt helper (uses nice UI if available)
local function prompt_and_log(opts)
  vim.ui.input({ prompt = 'adb regex: ', default = last_adb_regex }, function(rx)
    if rx then start_log_with_regex(rx, opts) end
  end)
end

-- Visual selection → prefill regex (quick escape of common chars for RE2)
local function get_visual_text_as_regex()
  local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, '<'))
  local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, '>'))
  local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
  if #lines == 0 then return '' end
  lines[#lines] = lines[#lines]:sub(1, ecol)
  lines[1]      = lines[1]:sub(scol + 1)
  local text = table.concat(lines, '\n')
  -- escape RE2 specials
  text = text:gsub('([%.%+%-%*%?%[%]%^%$%(%))])', '\\%1')
  return text
end

-- Keymaps:
-- Normal: prompt for regex and tail logs
vim.keymap.set('n', '<Leader>as', function()
  prompt_and_log({ clear = false })
end, { desc = 'ADB: logcat search (regex)' })

-- Normal: prompt + clear buffer first (bang-like)
vim.keymap.set('n', '<Leader>aS', function()
  prompt_and_log({ clear = true })
end, { desc = 'ADB: logcat search (clear first)' })

-- Visual: use selection as the initial regex (escaped), then tail
vim.keymap.set('v', '<Leader>as', function()
  local seed = get_visual_text_as_regex()
  vim.ui.input({ prompt = 'adb regex: ', default = seed }, function(rx)
    if rx then start_log_with_regex(rx, { clear = false }) end
  end)
end, { desc = 'ADB: logcat search (from selection)' })

-- ADB Log Bookmarks System
local adb_bookmarks = {
  crashes = { pattern = 'AndroidRuntime.*FATAL|Exception', label = 'Crashes' },
  network = { pattern = 'HttpConnection|OkHttp|Retrofit|Socket', label = 'Network' },
  database = { pattern = 'SQLite|Room|Database|cursor', label = 'Database' },
  ui = { pattern = 'ViewGroup|LayoutInflater|View|draw', label = 'UI/Layout' },
  app = { pattern = '', label = 'App package logs', use_pkg = true },
}

-- Dynamic bookmark to get current foreground app
vim.keymap.set('n', '<Leader>aG', function()
  local pkg = require('custom.adb').get_foreground_package(vim.g.adb_serial)
  if pkg then
    vim.g.adb_pkg = pkg
    vim.notify('Set adb_pkg to: ' .. pkg, vim.log.levels.INFO, { title = 'adb' })
  else
    vim.notify('Could not detect foreground app', vim.log.levels.WARN, { title = 'adb' })
  end
end, { desc = 'ADB: grab foreground app package' })

-- Bookmark selector with keymaps
vim.keymap.set('n', '<Leader>aw', function()
  local choices = {}
  for key, bookmark in pairs(adb_bookmarks) do
    table.insert(choices, key)
  end
  table.sort(choices)

  vim.ui.select(choices, {
    prompt = 'Select log filter: ',
    format_item = function(choice)
      return adb_bookmarks[choice].label
    end
  }, function(choice)
    if not choice then return end
    local bookmark = adb_bookmarks[choice]

    if bookmark.use_pkg then
      -- Filter by package
      if not vim.g.adb_pkg or vim.g.adb_pkg == '' then
        vim.notify('Set vim.g.adb_pkg first or use <Leader>aG to grab foreground app',
                   vim.log.levels.WARN, { title = 'adb' })
        return
      end
      require('custom.adb').logcat({
        serial = vim.g.adb_serial,
        pkg = vim.g.adb_pkg,
        pid = true,
        clear = true,
        level = 'V',
        format = 'threadtime'
      })
    else
      -- Filter by regex pattern
      start_log_with_regex(bookmark.pattern, { clear = true })
    end
  end)
end, { desc = 'ADB: log bookmarks' })

return {
  {
    "nvim-telescope/telescope.nvim",
    optional = true,  -- only run if Telescope is installed
    keys = {
      { "<Leader>ad", function() require("telescope").extensions.adb.devices({}) end, desc = "ADB: pick device" },
      { "<Leader>ai", function() require("custom.adb").install_from_picker({}) end, desc = "ADB: pick & install APK" },
      { "<Leader>aI", function() require("custom.adb").install_from_picker({ downgrade = true }) end, desc = "ADB: pick & install (downgrade)" },
    },
    config = function()
      -- your module with install() / install_from_picker()
      -- lives in lua/custom/adb/init.lua
      pcall(function() require("telescope").load_extension("adb") end) -- if you made the extension
    end,
  },
}

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
  require('custom.adb').logcat({ serial = vim.g.adb_serial, pkg = vim.g.adb_pkg, pid = true, clear = true })
end, { desc = 'ADB: logcat (pkg, clear, PID)' })

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

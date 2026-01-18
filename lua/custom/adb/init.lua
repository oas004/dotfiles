local AdbModule = {}

--- Check if adb binary is available in PATH
local function check_adb_available()
  if vim.fn.executable("adb") == 0 then
    vim.notify("adb not found in PATH", vim.log.levels.ERROR, { title = "adb" })
    return false
  end
  return true
end

function AdbModule.list_devices(long)
  if not check_adb_available() then return nil end

  local args = long and { 'adb', 'devices', '-l' } or { 'adb', 'devices' }
  local res = vim.system(args, { text = true }):wait()
  if res.code ~= 0 then
    return nil, (res.stderr ~= '' and res.stderr or 'adb failed')
  end

  local out = res.stdout or ''
  local devices = {}

  for line in out:gmatch('[^\r\n]+') do
    if not line:match('^List of devices attached') and line:match('%S') then
      local serial, state, rest = line:match('^(%S+)%s+(%S+)%s*(.*)$')
      if serial then
        local dev = { serial = serial, state = state }
        for k, v in rest:gmatch('([%w_]+):([^%s]+)') do
          dev[k] = v
        end
        table.insert(devices, dev)
      end
    end
  end

  return devices
end

function AdbModule.devices(opts)
  opts = opts or {}
  local list, err = AdbModule.list_devices(opts.long)
  if not list then
    vim.notify(err, vim.log.levels.ERROR, { title = 'adb devices' })
    return
  end
  local lines = { 'List of devices attached' }
  for _, d in ipairs(list) do
    table.insert(lines, string.format('%-20s %-10s %s %s',
      d.serial or '?', d.state or '', d.model or '', d.device or ''))
  end
  if #list == 0 then lines = { '(no devices)' } end

  vim.cmd('botright split')
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.bo.bufhidden = 'wipe'
  vim.bo.filetype = 'log'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end


-- Project root = nearest parent with settings.gradle(.kts)
local function project_root(startpath)
  local start = startpath
    or (vim.api.nvim_buf_get_name(0) ~= '' and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p:h'))
    or vim.loop.cwd()

  local markers = { 'settings.gradle', 'settings.gradle.kts' }
  local found = vim.fs.find(markers, { upward = true, path = start, stop = vim.loop.os_homedir() })[1]
  return found and vim.fs.dirname(found) or vim.loop.cwd()
end

-- adb install helper
function AdbModule.install(apk, opts)
  if not check_adb_available() then return end

  opts = opts or {}
  if not apk or apk == '' then
    vim.notify('No APK path provided', vim.log.levels.ERROR, { title = 'adb install' })
    return
  end
  if not apk:match('^/') then
    apk = project_root() .. '/' .. apk
  end
  local st = vim.loop.fs_stat(apk)
  if not st or st.type ~= 'file' then
    vim.notify('APK not found: ' .. apk, vim.log.levels.ERROR, { title = 'adb install' })
    return
  end

  local args = { 'adb' }
  local serial = opts.serial or vim.g.adb_serial
  if serial and serial ~= '' then table.insert(args, '-s'); table.insert(args, serial) end
  table.insert(args, 'install')
  if opts.replace ~= false then table.insert(args, '-r') end  -- default: replace
  if opts.grant   ~= false then table.insert(args, '-g') end  -- default: grant perms
  if opts.downgrade then table.insert(args, '-d') end
  table.insert(args, apk)

  local res = vim.system(args, { text = true }):wait()
  local ok  = (res.code == 0)
  local msg = (ok and res.stdout ~= '' and res.stdout) or (res.stderr ~= '' and res.stderr or '(no output)')
  vim.notify(msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR, { title = 'adb install' })
end

-- Telescope picker: choose an APK under the settings.gradle(.kts) root, then install
function AdbModule.install_from_picker(opts)
  if not check_adb_available() then return end

  opts = opts or {}
  local ok, telescope = pcall(require, 'telescope')
  if not ok then
    vim.notify('telescope.nvim not found', vim.log.levels.ERROR, { title = 'adb install' })
    return
  end
  local builtin       = require('telescope.builtin')
  local actions       = require('telescope.actions')
  local action_state  = require('telescope.actions.state')

  -- Prefer limiting to *.apk via fd/rg if available
  local find_cmd
  if vim.fn.executable('fd') == 1 then
    find_cmd = { 'fd', '--type', 'f', '--hidden', '--strip-cwd-prefix', '--glob', '*.apk', '--exclude', '.git' }
  elseif vim.fn.executable('rg') == 1 then
    find_cmd = { 'rg', '--files', '--hidden', '-g', '!*.git', '-g', '*.apk' }
  end

  builtin.find_files({
    cwd = project_root(),
    hidden = true,
    no_ignore = true,
    follow = true,
    previewer = false,
    prompt_title = 'Pick APK to install',
    find_command = find_cmd,  -- falls back to Telescope default if nil
    attach_mappings = function(bufnr, map)
      local function do_install()
        local entry = action_state.get_selected_entry()
        actions.close(bufnr)
        if not entry then return end
        local path = entry.path or entry.filename
        AdbModule.install(path, {
          replace   = (opts.replace ~= false),
          grant     = (opts.grant   ~= false),
          downgrade = opts.downgrade or false,
          serial    = opts.serial,
        })
      end
      map('n', '<CR>', do_install); map('i', '<CR>', do_install)
      return true
    end,
  })
end

-- Get the currently focused app package on the device
function AdbModule.get_foreground_package(serial)
  if not check_adb_available() then return nil end

  local args
  if serial and serial ~= '' then
    args = { 'adb', '-s', serial, 'shell', 'dumpsys', 'activity', 'recents' }
  else
    args = { 'adb', 'shell', 'dumpsys', 'activity', 'recents' }
  end

  local res = vim.system(args, { text = true }):wait()
  if res.code ~= 0 then return nil end

  -- Parse the output to find the package name
  for line in res.stdout:gmatch('[^\n]+') do
    local pkg = line:match('intent={.*?cmp=([^/]+)/') or line:match('mResumedActivity:.*?{[^}]*cmp=([^/]+)/')
    if pkg then return pkg end
  end

  return nil
end

-- Stream logcat in a terminal split
-- opts = { serial=..., clear=true/false, level='V/D/I/W/E', tag='MyTag',
--          pkg='com.example.app', pid=true, format='time|color|threadtime|long' }
function AdbModule.logcat(opts)
  if not check_adb_available() then return end

  opts = opts or {}
  local serial = opts.serial or vim.g.adb_serial

  -- Build adb args as a list (no empty strings)
  local args = { 'adb' }
  if serial and serial ~= '' then
    table.insert(args, '-s'); table.insert(args, serial)
  end
  table.insert(args, 'logcat')
  if opts.regex and opts.regex ~= '' then
    table.insert(args, '--regex'); table.insert(args, opts.regex)
  end
  -- Format (default 'time')
  local fmt = opts.format or 'time'
  vim.list_extend(args, { '-v', fmt })

  -- Optional tag / level
  if opts.tag or opts.level then
    local lvl = (opts.level or ''):sub(1,1) -- D/I/W/E/V
    local sel = opts.tag and (opts.tag .. (lvl ~= '' and (':'..lvl) or ''))
                  or ('*:' .. (lvl ~= '' and lvl or 'V'))
    table.insert(args, '-s'); table.insert(args, sel)
  end

  -- PID filter for a package (best fidelity)
  if opts.pkg and opts.pid ~= false then
    local function pidof(pkg)
      local r = vim.system(
        (serial and serial ~= '')
          and { 'adb', '-s', serial, 'shell', 'pidof', '-s', pkg }
          or  { 'adb', 'shell', 'pidof', '-s', pkg },
        { text = true }
      ):wait()
      if r.code == 0 and r.stdout and r.stdout:match('%S') then
        return vim.trim(r.stdout)
      end
      return nil
    end
    local pid = pidof(opts.pkg)
    if pid then
      table.insert(args, '--pid'); table.insert(args, pid)
    else
      vim.notify('pidof failed for '..opts.pkg..' — showing full logs (tip: launch app first)',
                 vim.log.levels.WARN, { title = 'adb logcat' })
    end
  end
  -- NOTE: if you prefer regex matching instead of PID, use:
  -- if opts.pkg and opts.pid == false then
  --   table.insert(args, '--regex'); table.insert(args, opts.pkg)
  -- end

  -- Clear buffer first if asked
  if opts.clear then
    local clr = vim.system(
      (serial and serial ~= '')
        and { 'adb', '-s', serial, 'logcat', '-c' }
        or  { 'adb', 'logcat', '-c' },
      { text = true }
    ):wait()
    vim.notify(clr.code == 0 and 'logcat cleared' or (clr.stderr ~= '' and clr.stderr or 'failed'),
               clr.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR,
               { title = 'adb logcat' })
  end

  -- Open a brand-new, unmodified buffer and start the terminal job
  local title = 'adb logcat'
  if serial and serial ~= '' then title = title .. ' ['..serial..']' end
  if opts.pkg then title = title .. ' pkg='..opts.pkg end
  vim.notify('Starting '..title, vim.log.levels.INFO, { title = 'adb logcat' })

  vim.cmd('botright split | enew')   -- IMPORTANT: fresh, unmodified buffer
  vim.bo.bufhidden = 'wipe'
  vim.bo.filetype = 'log'
  vim.bo.swapfile = false

  -- Do NOT write any lines before termopen, or the buffer becomes "modified"
  vim.fn.termopen(args, {
    on_exit = function(_, code)
      if code == 0 then
        vim.notify('logcat ended', vim.log.levels.INFO, { title = title })
      end
    end,
  })

  -- Quick 'q' to close
  vim.keymap.set('n', 'q', function()
    if vim.api.nvim_buf_is_valid(0) then
      vim.api.nvim_buf_delete(0, { force = true })
    end
  end, { buffer = 0, nowait = true, silent = true, desc = 'Close logcat' })

end

return AdbModule


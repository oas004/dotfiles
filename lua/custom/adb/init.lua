local AdbModule = {}

function AdbModule.list_devices(long)
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

return AdbModule


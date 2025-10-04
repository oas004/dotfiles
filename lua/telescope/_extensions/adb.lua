
local has_tel, telescope = pcall(require, 'telescope')
if not has_tel then
  error('[telescope-adb] telescope.nvim is required')
end

local pickers      = require('telescope.pickers')
local finders      = require('telescope.finders')
local conf         = require('telescope.config').values
local actions      = require('telescope.actions')
local action_state = require('telescope.actions.state')

local function devices_picker(opts)
  opts = opts or {}
  local adb = require('custom.adb')

  local list, err = adb.list_devices(true)
  if not list then
    vim.notify(err, vim.log.levels.ERROR, { title = 'adb devices' })
    list = {}
  end

  pickers.new(opts, {
    prompt_title = 'ADB Devices',
    finder = finders.new_table {
      results = list,
      entry_maker = function(d)
        local display = string.format('%-20s %-10s %-12s %-12s',
          d.serial or '?', d.state or '', d.model or '', d.device or '')
        return {
          value   = d,
          display = display,
          ordinal = table.concat({
            d.serial or '', d.state or '', d.model or '', d.device or ''
          }, ' ')
        }
      end
    },
    sorter = conf.generic_sorter(opts),

    attach_mappings = function(bufnr, map)
      local function get_entry() return action_state.get_selected_entry() end

      -- <CR>: set as default device (stores serial)
      actions.select_default:replace(function()
        local e = get_entry(); if not e then return end
        vim.g.adb_serial = e.value.serial
        vim.notify('ADB serial set: ' .. e.value.serial, vim.log.levels.INFO)
        actions.close(bufnr)
      end)

      -- s / <C-s>: open shell
      local function open_shell()
        local e = get_entry(); if not e then return end
        actions.close(bufnr)
        vim.cmd('botright split | terminal adb -s ' ..
          vim.fn.shellescape(e.value.serial) .. ' shell')
      end
      map('n', 's', open_shell); map('i', '<C-s>', open_shell)

      -- l / <C-l>: open logcat
      local function open_logcat()
        local e = get_entry(); if not e then return end
        actions.close(bufnr)
        vim.cmd('botright split | terminal adb -s ' ..
          vim.fn.shellescape(e.value.serial) .. ' logcat')
      end
      map('n', 'l', open_logcat); map('i', '<C-l>', open_logcat)

      -- y / <C-y>: yank serial
      local function yank_serial()
        local e = get_entry(); if not e then return end
        vim.fn.setreg('+', e.value.serial)
        vim.fn.setreg('"', e.value.serial)
        vim.notify('Yanked: ' .. e.value.serial)
      end
      map('n', 'y', yank_serial); map('i', '<C-y>', yank_serial)

      return true
    end,
  }):find()
end

return telescope.register_extension({
  exports = { devices = devices_picker },
})

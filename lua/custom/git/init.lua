local GitModule = {}

--- Check if in a git repository
local function is_in_git_repo()
  local result = vim.system({ 'git', 'rev-parse', '--is-inside-work-tree' }, { text = true }):wait()
  return result.code == 0
end

function GitModule.git_status(opts)
    opts = opts or {}

    -- Check if we're in a git repository
    if not is_in_git_repo() then
      vim.notify('Not in a git repository', vim.log.levels.ERROR, { title = 'git status' })
      return
    end

    local full = opts.full or false
    local to_scratch = opts.scratch or false
    local root = vim.system({ 'git', 'rev-parse', '--show-toplevel' }, { text = true }):wait()
    local cwd = (root.code == 0 and vim.trim(root.stdout) ~= '') and vim.trim(root.stdout) or vim.loop.cwd()
    local args = full and { 'git', 'status' } or { 'git', 'status', '--short' }
    local res = vim.system(args, { text = true, cwd = cwd }):wait()
    local ok = (res.code == 0)
    local out = (ok and res.stdout ~= '' and res.stdout) or (ok and '(no changes)' or res.stderr)
    if to_scratch then
      vim.cmd('botright split')
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.bo.bufhidden = 'wipe'
      vim.bo.filetype = 'gitstatus'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(out, '\n', { plain = true }))
    else
      vim.notify(out, ok and vim.log.levels.INFO or vim.log.levels.ERROR, { title = 'git status' })
    end
end

return GitModule


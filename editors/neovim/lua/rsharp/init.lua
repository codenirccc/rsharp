
local M = {}

M.opts = {
  rsc = nil,
  mini = nil,
  test = nil,
  lsp = nil,
}

local function repo_root()
  local here = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(here, ':h:h:h:h:h')
end

local function first_executable(root, names)
  for _, name in ipairs(names) do
    local path = root .. '/' .. name
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
  return nil
end

local function driver()
  if M.opts.rsc then
    return vim.fn.expand(M.opts.rsc)
  end
  return first_executable(repo_root(), { 'rsc.sh', 'rsc.cmd' })
end

local function mini_driver()
  if M.opts.mini then
    return vim.fn.expand(M.opts.mini)
  end
  return first_executable(repo_root(), { 'mini/run.sh', 'mini/run.cmd' })
end

local function test_driver()
  if M.opts.test then
    return vim.fn.expand(M.opts.test)
  end
  return first_executable(repo_root(), { 'regress.sh', 'regress.cmd' })
end

local function lsp_driver()
  if M.opts.lsp then
    return vim.fn.expand(M.opts.lsp)
  end
  return first_executable(repo_root(), {
    'work/lsp/build/t_lspsrv.exe',
    'work/lsp/build/t_lspsrv',
  })
end

local function outpath(file)
  local out = vim.fn.fnamemodify(file, ':p:r')
  if vim.fn.has('win32') == 1 then
    out = out .. '.exe'
  end
  return out
end

local function spawn(args)
  if vim.fn.has('win32') == 1 and args[1]:lower():sub(-4) == '.cmd' then
    local parts = {}
    for i = 1, #args do
      parts[i] = vim.fn.shellescape(args[i])
    end
    return table.concat(parts, ' ')
  end
  return args
end

local function parse(lines)
  local items = {}
  for _, line in ipairs(lines) do
    local file, lnum, col, msg = line:match('^rsc: (.-): line (%d+):(%d+): (.*)$')
    if file then
      items[#items + 1] = {
        filename = file,
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = msg,
        type = 'E',
      }
    else
      local file2, lnum2, msg2 = line:match('^rsc: (.-): line (%d+): (.*)$')
      if file2 then
        items[#items + 1] = {
          filename = file2,
          lnum = tonumber(lnum2),
          col = 1,
          text = msg2,
          type = 'E',
        }
      else
        local file3, msg3 = line:match('^rscb: (.-): (.*)$')
        if file3 then
          items[#items + 1] = { filename = file3, lnum = 1, col = 1, text = msg3, type = 'E' }
        end
      end
    end
  end
  return items
end

local function build(file)
  if file == '' then
    vim.notify('rsharp: buffer has no file name', vim.log.levels.ERROR)
    return false
  end
  local drv = driver()
  if not drv then
    vim.notify('rsharp: no rsc driver; pass one to setup({ rsc = ... })', vim.log.levels.ERROR)
    return false
  end

  local out = outpath(file)
  local result = vim.fn.system(spawn({ drv, file, out }))
  local items = parse(vim.split(result, '\n', { plain = true }))
  vim.fn.setqflist(items, 'r')

  if #items > 0 then
    vim.cmd('copen')
    return false
  end
  if vim.v.shell_error ~= 0 then
    vim.notify('rsharp: build failed', vim.log.levels.ERROR)
    return false
  end
  return true
end

local function run(file)
  if not build(file) then
    return
  end
  vim.cmd('botright new')
  vim.fn.termopen(spawn({ outpath(file) }), { cwd = vim.fn.fnamemodify(file, ':h') })
  vim.cmd('startinsert')
end

local function lsp_start(bufnr)
  local drv = lsp_driver()
  if not drv then
    vim.notify('rsharp: no language server; run work/lsp/run.cmd first', vim.log.levels.ERROR)
    return
  end
  vim.lsp.start({
    name = 'rsharp',
    cmd = { drv },
    root_dir = repo_root(),
  }, { bufnr = bufnr })
end

function M.setup(opts)
  M.opts = vim.tbl_extend('force', M.opts, opts or {})

  vim.filetype.add({
    extension = { rsx = 'rsx', mini = 'mini' },
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'rsx', 'mini' },
    callback = function()
      vim.opt_local.commentstring = '// %s'
    end,
  })

  vim.api.nvim_create_autocmd('FileType', {
    pattern = 'rsx',
    callback = function(args)
      if vim.api.nvim_buf_get_name(args.buf) == '' then
        return
      end
      if lsp_driver() then
        lsp_start(args.buf)
      end
    end,
  })

  vim.api.nvim_create_user_command('RsharpBuild', function()
    build(vim.api.nvim_buf_get_name(0))
  end, { desc = 'compile the current .rsx' })

  vim.api.nvim_create_user_command('RsharpRun', function()
    run(vim.api.nvim_buf_get_name(0))
  end, { desc = 'compile and run the current .rsx' })

  vim.api.nvim_create_user_command('RsharpTest', function()
    local drv = test_driver()
    if not drv then
      vim.notify('rsharp: no regress.sh; pass one to setup({ test = ... })', vim.log.levels.ERROR)
      return
    end
    vim.cmd('botright new')
    vim.fn.termopen(spawn({ drv }), { cwd = repo_root() })
    vim.cmd('startinsert')
  end, { desc = 'run the example suite' })

  vim.api.nvim_create_user_command('RsharpLsp', function()
    lsp_start(vim.api.nvim_get_current_buf())
  end, { desc = 'attach the rsharp language server to this buffer' })

  vim.api.nvim_create_user_command('MiniRun', function()
    local drv = mini_driver()
    if not drv then
      vim.notify('rsharp: no mini/run.sh; pass one to setup({ mini = ... })', vim.log.levels.ERROR)
      return
    end
    local file = vim.api.nvim_buf_get_name(0)
    if file == '' then
      vim.notify('rsharp: buffer has no file name', vim.log.levels.ERROR)
      return
    end
    vim.cmd('botright new')
    vim.fn.termopen(spawn({ drv, file }), { cwd = vim.fn.fnamemodify(file, ':h') })
    vim.cmd('startinsert')
  end, { desc = 'compile and run the current .mini' })
end

return M

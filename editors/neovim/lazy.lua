local root = vim.fn.expand('~/rsharp')

return {
  {
    dir = root .. '/editors/neovim',
    ft = { 'rsx', 'mini' },
    init = function()
      vim.filetype.add({ extension = { rsx = 'rsx', mini = 'mini' } })
      vim.opt.runtimepath:append(root .. '/editors/vim')
    end,
    config = function()
      require('rsharp').setup()
    end,
  },
}

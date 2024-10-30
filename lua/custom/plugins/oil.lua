return {
  'stevearc/oil.nvim',
  ---@module 'oil'
  ---@type oil.SetupOpts
  opts = {},
  -- Optional dependencies
  dependencies = { { 'echasnovski/mini.icons', opts = {} } },
  -- dependencies = { "nvim-tree/nvim-web-devicons" }, -- use if prefer nvim-web-devicons
  config = function()
    require('oil').setup {
      -- Change keymaps to mimic nvim-tree keys - will do the same for neo-tree
      keymaps = {
        ['<C-v>'] = { 'actions.select', opts = { vertical = true }, desc = 'Open the entry in a vertical split' },
        ['<C-x>'] = { 'actions.select', opts = { horizontal = true }, desc = 'Open the entry in a horizontal split' },
      },
    }
  end,
}

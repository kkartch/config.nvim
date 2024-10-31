return {
  -- Git command integration
  'tpope/vim-fugitive',
  config = function()
    -- Not sure what this keymap does but bring it over from my old nvim config
    vim.keymap.set('n', '<leader>gs', vim.cmd.Git)
  end,
}

return {
  -- 'iamcco/markdown-preview.nvim',
  'Tweekism/markdown-preview.nvim',
  cmd = { 'MarkdownPreviewToggle', 'MarkdownPreview', 'MarkdownPreviewStop' },
  build = 'cd app && yarn install',
  init = function()
    vim.g.mkdp_filetypes = { 'markdown' }
    vim.g.mkdp_preview_options = {
      disable_sync_scroll = 1,
    }
  end,
  ft = { 'markdown' },
}

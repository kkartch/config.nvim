return {
  cmd = { vim.fn.stdpath('data') .. '/mason/bin/emmet-language-server', '--stdio' },
  filetypes = { 'css', 'html', 'javascript', 'javascriptreact', 'less', 'sass', 'scss', 'typescriptreact', 'heex', 'elixir' },
  root_markers = { 'package.json', '.git' },
}
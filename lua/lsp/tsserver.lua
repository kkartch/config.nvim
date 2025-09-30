return {
  cmd = { vim.fn.stdpath('data') .. '/mason/bin/typescript-language-server', '--stdio' },
  filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact', 'typescript.tsx' },
  root_markers = { 'package.json', 'tsconfig.json', 'jsconfig.json', '.git' },
}
-- LazyGit
vim.keymap.set('n', '<leader>gg', ':LazyGit<CR>')

-- Window resizing
vim.keymap.set('n', '<CR>', '<c-w>_<c-w>|')
vim.keymap.set('n', '<c-i>', '<c-w>=')

-- Linting
vim.keymap.set('n', '<leader>l', '<CMD>lua require("lint").try_lint("credo")<CR>')

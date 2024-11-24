-- [[ Basic Keymaps ]]
--  See `:help vim.keymap.set()`

-- Clear highlights on search when pressing <Esc> in normal mode
--  See `:help hlsearch`
vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

-- Diagnostic keymaps
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev, { desc = 'Goto previous [D]iagnostic message' })
vim.keymap.set('n', ']d', vim.diagnostic.goto_next, { desc = 'Goto next [D]iagnostic message' })
vim.keymap.set('n', '<leader>e', function()
  vim.diagnostic.open_float { border = 'rounded' }
end, { desc = 'Show diagnostic [E]rror message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

-- Exit terminal mode in the builtin terminal with a shortcut that is a bit easier
-- for people to discover. Otherwise, you normally need to press <C-\><C-n>, which
-- is not what someone will guess without a bit more experience.
--
-- NOTE: This won't work in all terminal emulators/tmux/etc. Try your own mapping
-- or just use <C-\><C-n> to exit terminal mode
vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

-- Keybinds to make split navigation easier.
--  Use CTRL+<hjkl> to switch between windows
--
--  See `:help wincmd` for a list of all window commands
vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

-- Window resizing
vim.keymap.set('n', '<leader>M', '<c-w>_<c-w>|')
vim.keymap.set('n', '<leader>m', '<c-w>=')

-- Tab navigation
vim.keymap.set('n', '<leader>tn', ':tabnew<cr>', { desc = 'Create [T]ab [N]ew' })
vim.keymap.set('n', '<leader>tl', ':tabnext<cr>', { desc = 'Goto [T]ab to the [L]eft' })
vim.keymap.set('n', '<leader>th', ':tabprevious<cr>', { desc = 'Goto [T]ab to the right using [H] motion' })
vim.keymap.set('n', '<leader>tc', ':tabc<cr>', { desc = '[T]ab [C]lose' })

-- LazyGit
vim.keymap.set('n', '<leader>gg', ':LazyGit<CR>')

-- Linting
vim.keymap.set('n', '<leader>l', '<CMD>lua require("lint").try_lint("credo")<CR>')

-- Oil
vim.keymap.set('n', '-', '<CMD>Oil<CR>', { desc = 'Open parent directory' })

-- Dadbod
vim.keymap.set('n', '<leader>db', ':DBUI<CR>')

return {
  'mfussenegger/nvim-lint',
  config = function()
    require('lint').linters_by_ft = {
      lua = { 'luacheck' },
      python = { 'flake8' },
      javascript = { 'eslint' },
      typescript = { 'eslint' },
      go = { 'golangci-lint' },
      ruby = { 'rubocop' },
      elixir = { 'credo' },
      -- Add more filetypes and their respective linters here
    }

    -- This should be filetype specific
    vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
      callback = function()
        require('lint').try_lint 'credo'
      end,
    })
  end,
}

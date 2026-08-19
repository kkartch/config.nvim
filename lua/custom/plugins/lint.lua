return {
  'mfussenegger/nvim-lint',
  config = function()
    local lint = require('lint')

    lint.linters_by_ft = {
      lua = { 'luacheck' },
      python = { 'flake8' },
      javascript = { 'eslint' },
      javascriptreact = { 'eslint' },
      typescript = { 'eslint' },
      typescriptreact = { 'eslint' },
      go = { 'golangci-lint' },
      ruby = { 'rubocop' },
      elixir = { 'credo' },
      -- Add more filetypes and their respective linters here
    }

    -- Lint on save, dispatching on the buffer's filetype via linters_by_ft
    -- above. Linters whose command isn't installed are skipped rather than
    -- spawned, since nvim-lint raises an error notification on a failed
    -- spawn. They start working on their own once the tool is installed.
    vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
      callback = function()
        local available = vim.tbl_filter(function(name)
          local linter = lint.linters[name]
          if type(linter) ~= 'table' then
            return false
          end
          -- Some linters (eslint) compute `cmd` at call time to find a
          -- project-local binary, so resolve it before testing it.
          local cmd = linter.cmd
          if type(cmd) == 'function' then
            local ok, resolved = pcall(cmd)
            cmd = ok and resolved or nil
          end
          return type(cmd) == 'string' and vim.fn.executable(cmd) == 1
        end, lint.linters_by_ft[vim.bo.filetype] or {})

        if #available > 0 then
          lint.try_lint(available)
        end
      end,
    })
  end,
}

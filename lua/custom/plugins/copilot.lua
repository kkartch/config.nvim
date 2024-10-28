return {
  'zbirenbaum/copilot.lua',
  cmd = 'Copilot',
  event = 'InsertEnter',
  config = function()
    require('copilot').setup {
      filetypes = {
        elixir = true,
        -- Add more filetypes here
      },
      suggestion = { enabled = false },
      panel = { enabled = true },
    }
  end,
  -- 'github/copilot.vim',
}

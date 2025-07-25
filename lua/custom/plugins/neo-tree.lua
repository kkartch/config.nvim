-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
  },
  cmd = 'Neotree',
  keys = {
    { '\\', ':Neotree reveal<CR>', desc = 'NeoTree reveal', silent = true },
    { '|', ':Neotree close<CR>', desc = 'NeoTree close', silent = true },
  },
  opts = {
    filesystem = {
      window = {
        mappings = {
          ['\\'] = 'close_window',
          ['<C-v>'] = 'open_vsplit',
          ['<C-x>'] = 'open_split',
        },
      },
    },
  },
  config = function()
    require('neo-tree').setup {
      filesystem = {
        window = {
          mappings = {
            ['\\'] = 'close_window',
            ['<C-v>'] = 'open_vsplit',
            ['<C-x>'] = 'open_split',
          },
        },
        commands = {
          copy_selector = function(state)
            local node = state.tree:get_node()
            local filepath = node:get_id()
            local filename = node.name
            local modify = vim.fn.fnamemodify

            local vals = {
              ['BASENAME'] = modify(filename, ':r'),
              ['EXTENSION'] = modify(filename, ':e'),
              ['FILENAME'] = filename,
              ['PATH (CWD)'] = modify(filepath, ':.'),
              ['PATH (HOME)'] = modify(filepath, ':~'),
              ['PATH'] = filepath,
              ['URI'] = vim.uri_from_fname(filepath),
            }

            local options = vim.tbl_filter(function(val)
              return vals[val] ~= ''
            end, vim.tbl_keys(vals))
            if vim.tbl_isempty(options) then
              vim.notify('No values to copy', vim.log.levels.WARN)
              return
            end
            table.sort(options)
            vim.ui.select(options, {
              prompt = 'Choose to copy to clipboard:',
              format_item = function(item)
                return ('%s: %s'):format(item, vals[item])
              end,
            }, function(choice)
              local result = vals[choice]
              if result then
                vim.notify(('Copied: `%s`'):format(result))
                vim.fn.setreg('+', result)
              end
            end)
          end,
          copy_filepath = function(state)
            local node = state.tree:get_node()
            local filepath = node:get_id()
            vim.fn.setreg('+', filepath)
            vim.notify(('Copied: `%s`'):format(filepath))
          end,
        },
        window = {
          mappings = {
            Y = 'copy_selector',
            ['<C-y>'] = 'copy_filepath',
          },
        },
      },
    }
  end,
}

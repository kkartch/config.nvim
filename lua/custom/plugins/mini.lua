return { -- Collection of various small independent plugins/modules
  'echasnovski/mini.nvim',
  config = function()
    -- Better Around/Inside textobjects
    --
    -- Examples:
    --  - va)  - [V]isually select [A]round [)]paren
    --  - yinq - [Y]ank [I]nside [N]ext [Q]uote
    --  - ci'  - [C]hange [I]nside [']quote
    require('mini.ai').setup { n_lines = 500 }

    -- Add/delete/replace surroundings (brackets, quotes, etc.)
    --
    -- - saiw) - [S]urround [A]dd [I]nner [W]ord [)]Paren
    -- - sd'   - [S]urround [D]elete [']quotes
    -- - sr)'  - [S]urround [R]eplace [)] [']
    require('mini.surround').setup()

    -- Simple and easy statusline.
    --  You could remove this setup call if you don't like it,
    --  and try some other statusline plugin
    local statusline = require 'mini.statusline'
    -- set use_icons to true if you have a Nerd Font
    statusline.setup { use_icons = vim.g.have_nerd_font }

    -- Limit git branch name to 10 characters
    ---@diagnostic disable-next-line: duplicate-set-field
    statusline.section_git = function(args)
      local buf_id = args and args.buf or 0
      local head = vim.b[buf_id].minigit_summary_string or vim.b.gitsigns_head or ''
      if head == '' then
        return ''
      end
      if #head > 10 then
        head = head:sub(1, 10)
      end
      return head
    end

    -- Limit filename path to 75 characters and show modified indicator
    ---@diagnostic disable-next-line: duplicate-set-field
    statusline.section_filename = function()
      local filename = vim.fn.expand '%:~:.'
      if #filename > 75 then
        filename = '...' .. filename:sub(-72)
      end
      if vim.bo.modified then
        filename = filename .. ' [+]'
      end
      return filename
    end

    -- You can configure sections in the statusline by overriding their
    -- default behavior. For example, here we set the section for
    -- cursor location to LINE:COLUMN
    ---@diagnostic disable-next-line: duplicate-set-field
    statusline.section_location = function()
      return '%2l:%-2v'
    end

    -- ... and there is more!
    --  Check out: https://github.com/echasnovski/mini.nvim
  end,
}

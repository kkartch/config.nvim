return {
  -- LSP Plugins
  {
    -- `lazydev` configures Lua LSP for your Neovim config, runtime and plugins
    -- used for completion, annotations and signatures of Neovim apis
    'folke/lazydev.nvim',
    ft = 'lua',
    opts = {
      library = {
        -- Load luvit types when the `vim.uv` word is found
        { path = 'luvit-meta/library', words = { 'vim%.uv' } },
      },
    },
  },
  { 'Bilal2453/luvit-meta', lazy = true },
  {
    -- LSP Configuration using native vim.lsp.config (Neovim 0.11+)
    -- This replaces nvim-lspconfig for basic setup
    name = 'native-lsp-config',
    dir = vim.fn.stdpath('config'),
    dependencies = {
      -- Automatically install LSPs and related tools to stdpath for Neovim
      { 'williamboman/mason.nvim', config = true }, -- NOTE: Must be loaded before dependants
      'WhoIsSethDaniel/mason-tool-installer.nvim',

      -- Useful status updates for LSP.
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim', opts = {} },

      -- Allows extra capabilities provided by nvim-cmp
      'hrsh7th/cmp-nvim-lsp',
    },
    config = function()
      -- Brief aside: **What is LSP?**
      --
      -- LSP is an initialism you've probably heard, but might not understand what it is.
      --
      -- LSP stands for Language Server Protocol. It's a protocol that helps editors
      -- and language tooling communicate in a standardized fashion.
      --
      -- In general, you have a "server" which is some tool built to understand a particular
      -- language (such as `gopls`, `lua_ls`, `rust_analyzer`, etc.). These Language Servers
      -- (sometimes called LSP servers, but that's kind of like ATM Machine) are standalone
      -- processes that communicate with some "client" - in this case, Neovim!
      --
      -- LSP provides Neovim with features like:
      --  - Go to definition
      --  - Find references
      --  - Autocompletion
      --  - Symbol Search
      --  - and more!
      --
      -- Thus, Language Servers are external tools that must be installed separately from
      -- Neovim. This is where `mason` and related plugins come into play.
      --
      -- If you're wondering about lsp vs treesitter, you can check out the wonderfully
      -- and elegantly composed help section, `:help lsp-vs-treesitter`

      --  This function gets run when an LSP attaches to a particular buffer.
      --    That is to say, every time a new file is opened that is associated with
      --    an lsp (for example, opening `main.rs` is associated with `rust_analyzer`) this
      --    function will be executed to configure the current buffer
      -- Jump from a `defdelegate` to the function it delegates to.
      --
      -- Expert already resolves the delegated target, including `as:` renames,
      -- but two things stop a plain definition jump from landing there:
      --   * it also returns the defdelegate itself, and telescope sorts that
      --     self-reference first, so the jump goes nowhere
      --   * a multi-line defdelegate returns the same target twice
      -- So: ask at the function name, drop the self-reference, dedupe.
      --
      -- Returns true when it handled the jump, false to fall through to the
      -- normal definition mapping.
      local function jump_to_delegate()
        local bufnr = vim.api.nvim_get_current_buf()
        local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]

        local function line_at(lnum)
          return vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
        end

        local function is_continuation(text)
          return text:match('^%s*to:') ~= nil or text:match('^%s*as:') ~= nil
        end

        -- The cursor may be on a `to:`/`as:` continuation line, so walk up to
        -- the `defdelegate` that owns it.
        local deleg_lnum, deleg_line
        for lnum = cursor_lnum, math.max(1, cursor_lnum - 4), -1 do
          local text = line_at(lnum)
          if text:match('^%s*defdelegate%s') then
            deleg_lnum, deleg_line = lnum, text
            break
          end
          if lnum < cursor_lnum and not is_continuation(text) then
            break
          end
        end
        if not deleg_lnum then
          return false
        end

        local _, keyword_end = deleg_line:find('defdelegate%s+')
        local name_start = keyword_end and deleg_line:find('[%a_]', keyword_end + 1)
        if not name_start then
          return false
        end

        local client = vim.lsp.get_clients({ bufnr = bufnr, method = 'textDocument/definition' })[1]
        if not client then
          return false
        end

        -- How far the statement runs, so results inside it count as the self
        -- reference rather than as the target.
        local last_lnum = deleg_lnum
        while last_lnum < vim.api.nvim_buf_line_count(bufnr)
          and is_continuation(line_at(last_lnum + 1)) do
          last_lnum = last_lnum + 1
        end

        local self_uri = vim.uri_from_bufnr(bufnr)
        client:request('textDocument/definition', {
          textDocument = { uri = self_uri },
          position = { line = deleg_lnum - 1, character = name_start - 1 },
        }, function(err, result)
          if err or not result or vim.tbl_isempty(result) then
            return vim.notify('defdelegate: no definition returned', vim.log.levels.WARN)
          end

          local items = vim.islist(result) and result or { result }
          local seen, targets = {}, {}
          for _, item in ipairs(items) do
            local uri = item.uri or item.targetUri
            local range = item.range or item.targetSelectionRange
            local line = range and range.start.line or -1
            local is_self = uri == self_uri and line >= deleg_lnum - 1 and line <= last_lnum - 1
            local key = string.format('%s:%d:%d', uri, line, range and range.start.character or -1)
            if not is_self and not seen[key] then
              seen[key] = true
              table.insert(targets, item)
            end
          end

          if #targets == 1 then
            vim.cmd("normal! m'") -- leave a jumplist entry so <C-o> comes back
            vim.lsp.util.show_document(targets[1], client.offset_encoding, { focus = true })
          elseif #targets == 0 then
            -- The defdelegate resolved to itself and nothing else, which means
            -- the server has no record of the target module. Usually that is a
            -- module added since the project was indexed; Expert does not pick
            -- those up on its own.
            vim.notify(
              'defdelegate: only the definition site resolved -- the target module may not be indexed yet, try :LspReindex',
              vim.log.levels.WARN
            )
          else
            -- Genuinely ambiguous, so let the usual picker decide.
            require('telescope.builtin').lsp_definitions()
          end
        end, bufnr)

        return true
      end

      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
        callback = function(event)
          -- NOTE: Remember that Lua is a real programming language, and as such it is possible
          -- to define small helper and utility functions so you don't have to repeat yourself.
          --
          -- In this case, we create a function that lets us more easily define mappings specific
          -- for LSP related items. It sets the mode, buffer and description for us each time.
          local map = function(keys, func, desc, mode)
            mode = mode or 'n'
            vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
          end

          -- Jump to the definition of the word under your cursor.
          --  This is where a variable was first declared, or where a function is defined, etc.
          --  To jump back, press <C-t>.
          map('gd', function()
            if not jump_to_delegate() then
              require('telescope.builtin').lsp_definitions()
            end
          end, '[G]oto [D]efinition')

          -- Find references for the word under your cursor.
          map('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')

          -- Jump to the implementation of the word under your cursor.
          --  Useful when your language has ways of declaring types without an actual implementation.
          map('gI', require('telescope.builtin').lsp_implementations, '[G]oto [I]mplementation')

          -- Jump to the type of the word under your cursor.
          --  Useful when you're not sure what type a variable is and you want to see
          --  the definition of its *type*, not where it was *defined*.
          map('<leader>D', require('telescope.builtin').lsp_type_definitions, 'Type [D]efinition')

          -- Fuzzy find all the symbols in your current document.
          --  Symbols are things like variables, functions, types, etc.
          map('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')

          -- Fuzzy find all the symbols in your current workspace.
          --  Similar to document symbols, except searches over your entire project.
          map('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

          -- Rename the variable under your cursor.
          --  Most Language Servers support renaming across files, etc.
          map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')

          -- Execute a code action, usually your cursor needs to be on top of an error
          -- or a suggestion from your LSP for this to activate.
          map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })

          -- WARN: This is not Goto Definition, this is Goto Declaration.
          --  For example, in C this would take you to the header.
          map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

          -- The following two autocommands are used to highlight references of the
          -- word under your cursor when your cursor rests there for a little while.
          --    See `:help CursorHold` for information about when this is executed
          --
          -- When you move your cursor, the highlights will be cleared (the second autocommand).
          local client = vim.lsp.get_client_by_id(event.data.client_id)
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
            local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
            vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.document_highlight,
            })

            vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
              buffer = event.buf,
              group = highlight_augroup,
              callback = vim.lsp.buf.clear_references,
            })

            vim.api.nvim_create_autocmd('LspDetach', {
              group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
              callback = function(event2)
                vim.lsp.buf.clear_references()
                vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
              end,
            })
          end

          -- The following code creates a keymap to toggle inlay hints in your
          -- code, if the language server you are using supports them
          --
          -- This may be unwanted, since they displace some of your code
          if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
            map('<leader>th', function()
              vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
            end, '[T]oggle Inlay [H]ints')
          end

          -- Ask the server to reindex. Expert does not pick up newly created
          -- modules incrementally -- it only knows the files that existed when
          -- it indexed -- so a new file stays invisible until a reindex.
          local server_cmds = vim.tbl_get(client or {}, 'server_capabilities', 'executeCommandProvider', 'commands') or {}
          if vim.tbl_contains(server_cmds, 'Reindex') then
            map('<leader>ri', '<CMD>LspReindex<CR>', 'Re[i]ndex project')
          end
        end,
      })

      -- Configure diagnostics with rounded borders
      vim.diagnostic.config({
        float = {
          border = 'rounded',
        },
      })

      -- Neovim core ships none of :LspRestart/:LspStop/:LspInfo -- they come
      -- from nvim-lspconfig, which this config replaces. Rebuild the few that
      -- are actually useful on the native API.
      local function target_clients(name)
        if name and name ~= '' then
          return vim.lsp.get_clients { name = name }
        end
        return vim.lsp.get_clients { bufnr = vim.api.nvim_get_current_buf() }
      end

      local function complete_clients()
        local names = {}
        for _, client in ipairs(vim.lsp.get_clients()) do
          names[client.name] = true
        end
        return vim.tbl_keys(names)
      end

      vim.api.nvim_create_user_command('LspStop', function(opts)
        local clients = target_clients(opts.args)
        if #clients == 0 then
          return vim.notify('No matching LSP clients', vim.log.levels.WARN)
        end
        for _, client in ipairs(clients) do
          client:stop(true)
        end
      end, { nargs = '?', complete = complete_clients, desc = 'Stop LSP client(s)' })

      vim.api.nvim_create_user_command('LspRestart', function(opts)
        local clients = target_clients(opts.args)
        if #clients == 0 then
          return vim.notify('No matching LSP clients', vim.log.levels.WARN)
        end

        -- Remember which buffers were attached so they can be re-attached.
        local names, buffers = {}, {}
        for _, client in ipairs(clients) do
          table.insert(names, client.name)
          for buf in pairs(client.attached_buffers or {}) do
            if vim.api.nvim_buf_is_loaded(buf) then
              buffers[buf] = true
            end
          end
          client:stop(true)
        end

        -- Re-attaching before the old client exits would be ignored, so wait.
        vim.wait(5000, function()
          for _, client in ipairs(clients) do
            if not client:is_stopped() then
              return false
            end
          end
          return true
        end, 100)

        -- `vim.lsp.enable` attaches on FileType, so replaying it re-attaches.
        for buf in pairs(buffers) do
          if vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_exec_autocmds('FileType', { buffer = buf })
          end
        end
        vim.notify('Restarted: ' .. table.concat(names, ', '))
      end, { nargs = '?', complete = complete_clients, desc = 'Restart LSP client(s)' })

      vim.api.nvim_create_user_command('LspInfo', 'checkhealth vim.lsp', { desc = 'LSP status' })

      vim.api.nvim_create_user_command('LspReindex', function()
        local buf = vim.api.nvim_get_current_buf()
        local asked = {}
        for _, client in ipairs(vim.lsp.get_clients { bufnr = buf }) do
          local cmds = vim.tbl_get(client, 'server_capabilities', 'executeCommandProvider', 'commands') or {}
          if vim.tbl_contains(cmds, 'Reindex') then
            table.insert(asked, client.name)
            client:request('workspace/executeCommand', { command = 'Reindex', arguments = {} }, function(err)
              if err then
                vim.notify('Reindex failed: ' .. tostring(err.message or err), vim.log.levels.ERROR)
              end
            end, buf)
          end
        end
        if #asked == 0 then
          return vim.notify('No attached client supports Reindex', vim.log.levels.WARN)
        end
        vim.notify('Reindexing: ' .. table.concat(asked, ', '))
      end, { desc = 'Ask the language server to reindex the project' })

      -- Nothing rotates lsp.log and it had reached ~800MB. Truncate when it
      -- gets large; the log is a debugging aid, not a record worth keeping.
      local log_path = vim.lsp.log.get_filename()
      local stat = log_path and vim.uv.fs_stat(log_path)
      if stat and stat.size > 50 * 1024 * 1024 then
        local fd = vim.uv.fs_open(log_path, 'w', 420)
        if fd then
          vim.uv.fs_close(fd)
        end
      end

      -- LSP servers and clients are able to communicate to each other what features they support.
      --  By default, Neovim doesn't support everything that is in the LSP specification.
      --  When you add nvim-cmp, luasnip, etc. Neovim now has *more* capabilities.
      --  So, we create new capabilities with nvim cmp, and then broadcast that to the servers.
      local capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = vim.tbl_deep_extend('force', capabilities, require('cmp_nvim_lsp').default_capabilities())

      -- Set global LSP configuration
      vim.lsp.config('*', {
        capabilities = capabilities,
      })

      -- List of language servers to enable
      -- Configuration for each server is in lua/lsp/{server_name}.lua
      local servers = {
        'expert',
        'lua_ls',
        'tsserver',
        'emmet_language_server',
      }

      -- Mason package names (for automatic installation)
      local mason_packages = {
        'expert',
        'lua-language-server',
        'typescript-language-server',
        'emmet-language-server',
        'stylua', -- Used to format Lua code
      }

      -- Ensure the servers and tools above are installed
      --  To check the current status of installed tools and/or manually install
      --  other tools, you can run
      --    :Mason
      --
      --  You can press `g?` for help in this menu.
      require('mason').setup()
      require('mason-tool-installer').setup { ensure_installed = mason_packages }

      -- Enable language servers using the new native API
      -- Load and set configurations from lua/lsp/{server_name}.lua
      for _, server in ipairs(servers) do
        -- Load the server configuration file
        local ok, config = pcall(require, 'lsp.' .. server)
        if ok then
          -- Set the configuration
          vim.lsp.config[server] = config
        end
        -- Enable the server
        vim.lsp.enable(server)
      end
    end,
  },
}

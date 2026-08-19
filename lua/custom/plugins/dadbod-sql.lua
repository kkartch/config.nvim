return {
  'tpope/vim-dadbod',
  dependencies = {
    'kristijanhusak/vim-dadbod-ui',
    'kristijanhusak/vim-dadbod-completion',
  },
  -- `init` rather than `config`: dadbod-ui reads this global as it renders the
  -- drawer, so it has to be set before the plugin loads.
  init = function()
    -- Selecting a helper from the drawer runs it immediately instead of
    -- staging the query for you to write. (That path still opens a SQL
    -- buffer; the keymaps in `config` below skip the buffer entirely.)
    vim.g.db_ui_auto_execute_table_helpers = 1

    -- Extra helpers shown as child nodes under each table in the DBUI drawer.
    -- These merge with the built-ins (List, Columns, Indexes, Foreign Keys,
    -- References, Primary Keys) rather than replacing them; setting a built-in
    -- name to '' would remove it.
    --
    -- dadbod runs Postgres queries via `psql -f <tmpfile>`, so a helper can be
    -- a psql meta-command (\d+, \pset) just as easily as SQL.
    -- Placeholders: {table} {schema} {optional_schema} {dbname}
    vim.g.db_ui_table_helpers = {
      postgresql = {
        Describe = [[\d+ "{schema}"."{table}"]],

        ['Index Detail'] = [[
SELECT i.relname AS index,
       am.amname AS method,
       pg_size_pretty(pg_relation_size(i.oid)) AS size,
       s.idx_scan AS scans,
       pg_get_indexdef(i.oid) AS definition
FROM pg_class t
JOIN pg_namespace n ON n.oid = t.relnamespace
JOIN pg_index ix ON t.oid = ix.indrelid
JOIN pg_class i ON i.oid = ix.indexrelid
JOIN pg_am am ON am.oid = i.relam
LEFT JOIN pg_stat_all_indexes s ON s.indexrelid = i.oid
WHERE n.nspname = '{schema}' AND t.relname = '{table}'
ORDER BY i.relname;
]],

        ['Size & Rows'] = [[
SELECT (SELECT count(*) FROM "{schema}"."{table}") AS row_count,
       pg_size_pretty(pg_total_relation_size('"{schema}"."{table}"'::regclass)) AS total_size,
       pg_size_pretty(pg_relation_size('"{schema}"."{table}"'::regclass))       AS heap_size,
       pg_size_pretty(pg_indexes_size('"{schema}"."{table}"'::regclass))        AS indexes_size;
]],

        -- Reconstructed from the catalog rather than shelling out to pg_dump:
        -- `\!` spawns a subprocess that does not inherit psql's connection, so
        -- pg_dump cannot reach a DB that isn't on the default local socket.
        DDL = [[
\set QUIET on
\pset format unaligned
\pset tuples_only on
WITH cols AS (
  SELECT '    ' || quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod)
         || coalesce(' DEFAULT ' || pg_get_expr(d.adbin, d.adrelid), '')
         || CASE WHEN a.attnotnull THEN ' NOT NULL' ELSE '' END AS line, a.attnum
  FROM pg_attribute a
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
  WHERE a.attrelid = '"{schema}"."{table}"'::regclass
    AND a.attnum > 0 AND NOT a.attisdropped
), cons AS (
  SELECT '    CONSTRAINT ' || quote_ident(conname) || ' ' || pg_get_constraintdef(oid) AS line
  FROM pg_constraint WHERE conrelid = '"{schema}"."{table}"'::regclass
)
SELECT 'CREATE TABLE "{schema}"."{table}" (' || E'\n'
       || (SELECT string_agg(line, E',\n' ORDER BY attnum) FROM cols)
       || coalesce((SELECT E',\n' || string_agg(line, E',\n') FROM cons), '')
       || E'\n);'
UNION ALL
SELECT pg_get_indexdef(indexrelid) || ';'
  FROM pg_index WHERE indrelid = '"{schema}"."{table}"'::regclass AND NOT indisprimary;
]],
      },
    }
  end,

  config = function()
    -- Run a table helper against the table under the cursor in the DBUI
    -- drawer, sending output straight to a .dbout buffer. dadbod-ui's own
    -- flow opens a SQL buffer first; this skips it.
    --
    -- Helpers come from `db_ui#table_helpers#get`, so these keymaps and the
    -- drawer's expandable child nodes share one definition -- including
    -- anything added to `g:db_ui_table_helpers` later.

    -- Resolve the table node under the cursor into {db, schema, table}.
    local function target_under_cursor()
      local ok, drawer = pcall(vim.fn['db_ui#drawer#get'])
      if not ok or type(drawer) ~= 'table' or type(drawer.content) ~= 'table' then
        return nil, 'DBUI drawer is not open'
      end

      local item = drawer.content[vim.fn.line('.')]
      if type(item) ~= 'table' then
        return nil, 'Nothing under the cursor'
      end

      -- Table nodes carry a type of the form:
      --   schemas->items->{schema}->tables->items->{table}
      local schema, name = tostring(item.type or ''):match('^schemas%->items%->(.-)%->tables%->items%->(.+)$')
      if not schema then
        return nil, 'Put the cursor on a table'
      end

      local db = drawer.dbui.dbs[item.dbui_db_key_name]
      if type(db) ~= 'table' then
        return nil, 'Could not resolve the connection for this table'
      end

      return { db = db, schema = schema, table = name }
    end

    -- Mirrors the substitution dadbod-ui does in autoload/db_ui/query.vim, so a
    -- helper behaves identically whether run from here or from the drawer.
    local function expand(content, t)
      local optional_schema = ''
      if t.schema ~= t.db.default_scheme then
        optional_schema = (t.db.quote == 1) and ('"' .. t.schema .. '"') or t.schema
        optional_schema = optional_schema .. '.'
      end
      local dbname = t.schema ~= '' and t.schema or (t.db.db_name or '')

      -- Replace via functions: table names may contain `%`, which is special
      -- in a gsub replacement string.
      local function lit(v)
        return function()
          return v
        end
      end

      content = content:gsub('{table}', lit(t.table))
      content = content:gsub('{optional_schema}', lit(optional_schema))
      content = content:gsub('{schema}', lit(t.schema))
      content = content:gsub('{dbname}', lit(dbname))
      return content
    end

    local function run(content, t)
      local url = t.db.url
      if url == nil or url == '' then
        url = t.db.conn
      end
      if url == nil or url == '' then
        vim.notify('No connection URL for this database', vim.log.levels.ERROR)
        return
      end
      vim.fn['db#execute_command']('', 0, -1, -1, url .. ' ' .. expand(content, t))
    end

    -- Pick any helper for the table under the cursor.
    local function pick_helper()
      local t, err = target_under_cursor()
      if not t then
        vim.notify(err, vim.log.levels.WARN)
        return
      end

      local helpers = vim.fn['db_ui#table_helpers#get'](t.db.scheme)
      local names = vim.tbl_keys(helpers)
      table.sort(names)

      vim.ui.select(names, {
        prompt = ('Helpers for %s.%s'):format(t.schema, t.table),
      }, function(choice)
        if choice then
          run(helpers[choice], t)
        end
      end)
    end

    -- Run one named helper directly.
    local function run_helper(name)
      return function()
        local t, err = target_under_cursor()
        if not t then
          vim.notify(err, vim.log.levels.WARN)
          return
        end

        local content = vim.fn['db_ui#table_helpers#get'](t.db.scheme)[name]
        if not content then
          vim.notify(('No %q helper for %s'):format(name, t.db.scheme), vim.log.levels.WARN)
          return
        end

        run(content, t)
      end
    end

    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'dbui',
      group = vim.api.nvim_create_augroup('dbui-table-helpers', { clear = true }),
      callback = function(event)
        local map = function(lhs, rhs, desc)
          vim.keymap.set('n', lhs, rhs, { buffer = event.buf, nowait = true, desc = desc })
        end

        map('E', pick_helper, 'DBUI: pick a helper for this table')
        map('D', run_helper('Describe'), 'DBUI: describe this table (\\d+)')
        map('I', run_helper('Index Detail'), 'DBUI: index detail for this table')
        map('Z', run_helper('Size & Rows'), 'DBUI: size and row count for this table')
      end,
    })
  end,
}

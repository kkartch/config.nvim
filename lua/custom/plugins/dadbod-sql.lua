return {
  'tpope/vim-dadbod',
  dependencies = {
    'kristijanhusak/vim-dadbod-ui',
    'kristijanhusak/vim-dadbod-completion',
  },
  -- `init` rather than `config`: dadbod-ui reads this global as it renders the
  -- drawer, so it has to be set before the plugin loads.
  init = function()
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
}

# psql table helpers for the DBUI drawer

**Date:** 2026-08-19
**Status:** Implemented and verified against a live database.

## Problem

Running psql commands against a specific table meant typing the table name by hand —
`:DB \d public.concepts` — after already having located that table in the DBUI drawer. The name is
right there under the cursor; retyping it is the friction.

The initial framing of this work was "replace vim-dadbod, its interface is the problem." Investigation
showed that framing was wrong, in a way worth recording.

## What the investigation changed

**vim-dadbod is already psql.** Its Postgres adapter shells out to the `psql` binary rather than
speaking the wire protocol:

```vim
" vim-dadbod/autoload/db/adapter/postgresql.vim
function! db#adapter#postgresql#interactive(url, ...) abort
  return ['psql', '-w'] + (a:0 ? a:1 : []) + ['--dbname', ...]
endfunction

function! db#adapter#postgresql#input(url, in) abort
  return db#adapter#postgresql#filter(a:url) + ['-f', a:in]
endfunction
```

Queries are written to a temp file and run with `psql -f`. psql executes backslash meta-commands from
`-f` input, so **`\d+` and `\pset` work anywhere dadbod accepts a query** — including inside a table
helper. dadbod even uses `-c '\dtvm'` internally to list tables.

This makes a plugin replacement unnecessary. The alternatives were surveyed and rejected on the merits:
[nvim-dbee](https://github.com/kndndrj/nvim-dbee) has the result grid and CSV/JSON export, but it is a
Go wire-protocol client with no meta-command support at all — the opposite of what was wanted — and is
self-described alpha software. `trstringer/psql.nvim` is 24 stars and 12 commits.

**dadbod-ui already has the extension point.** `g:db_ui_table_helpers` is keyed by scheme; entries
appear as child nodes under every table in the drawer, with placeholders substituted. Per
`db_ui#table_helpers#get`, user entries *extend* the built-ins rather than replacing them, and an entry
set to `''` removes a built-in.

Available placeholders (`autoload/db_ui/query.vim:134-138`): `{table}`, `{schema}`,
`{optional_schema}`, `{dbname}`.

## Decision

Add four Postgres helpers via `g:db_ui_table_helpers`. No plugin change, no custom keymaps, no new
dependency. The existing four connections and eleven saved queries are untouched, as are the six
built-in helpers.

A direct keymap on the hovered table was initially dropped as redundant. That turned out to be wrong —
see *Round two* below — and it was added afterwards.

## Changes

Single file: `lua/custom/plugins/dadbod-sql.lua` gains an `init` block. `init` rather than `config`,
because dadbod-ui reads the global while rendering the drawer.

| Helper | Implementation |
|---|---|
| `Describe` | `\d+ "{schema}"."{table}"` — a real psql meta-command |
| `Index Detail` | Catalog query: index name, access method, on-disk size, **scan count**, full definition |
| `Size & Rows` | `count(*)` plus total / heap / index sizes via `pg_size_pretty` |
| `DDL` | Reconstructed `CREATE TABLE` from `pg_attribute` / `pg_constraint`, plus `pg_get_indexdef` |

Two of these departed from the obvious implementation, for reasons that were established empirically
rather than assumed.

### `Index Detail` is a query, not `\di`

`\di` takes an *index-name* pattern, not a table, so it cannot be scoped to the hovered table. The
catalog query also beats the built-in `Indexes` helper (a bare `pg_indexes` select) by adding size and
`idx_scan` counts — which is the column that shows whether an index is earning its keep.

### `DDL` reconstructs from the catalog instead of calling `pg_dump`

The first design shelled out from inside psql:

```
\! pg_dump --schema-only --no-owner --no-privileges -t '{schema}.{table}' {dbname}
```

**This was tested and it fails.** `\!` spawns a subprocess that does not inherit psql's connection, so
`pg_dump` fell back to the default Unix socket:

```
pg_dump: error: connection to server on socket "/tmp/.s.PGSQL.5432" failed: No such file or directory
```

The database runs in Docker, which publishes TCP only and provides no Unix socket. Passing host and
port through would still leave the password, which lives in dadbod's connection URL and is never
exposed to a subprocess.

The catalog reconstruction has no such dependency: it runs in the already-authenticated session, so it
works over any connection dadbod can reach, local or remote. It is prefixed with

```
\set QUIET on
\pset format unaligned
\pset tuples_only on
```

so the DDL emits as clean text. `\set QUIET on` is required — without it psql prints
`Output format is unaligned.` above the output. `\o /dev/null` does *not* suppress that message; this
was tested.

Because dadbod spawns a fresh psql process per query, these `\pset` changes cannot leak into any other
query.

## Verification

Executed through dadbod's real path — content in a buffer with `b:db` set, run via `:%DB` — against
`grotto_dev` (PostgreSQL 17.6, `pgvector/pgvector:pg17` in Docker, published on `localhost:5432`),
using the `public.concepts` table.

| Check | Result |
|---|---|
| Helpers merge with built-ins | pass — 10 total: the 6 built-ins plus these 4 |
| `Describe` (meta-command via dadbod) | pass — full `\d+` output, 0.054s |
| `Index Detail` | pass — 5 indexes with scan counts, 0.028s |
| `Size & Rows` | pass — 1221 rows, 18 MB total, 0.028s |
| `DDL` | pass — `CREATE TABLE` with defaults, all constraints, index statements, 0.028s |
| `\pset` noise suppressed | pass — no `Output format is unaligned.` line |

Note that `pg_isready` without `-h` reports the server as down, because it probes the Unix socket that
the Docker container does not provide. Use `pg_isready -h localhost`.

## Round two: removing the intermediate buffer

The helpers alone did not fix the interaction. Selecting one opens a **SQL buffer** containing the
generated query, which then has to be written to execute, with results arriving in a third pane. The
objection was never the helper content; it was having to pass through a buffer at all.

Two changes address this.

### `g:db_ui_auto_execute_table_helpers = 1`

A built-in option, default `0`, documented as "opening any table helper will automatically write the
query and execute it." This removes the manual write from the drawer's own expand-and-select path. The
SQL buffer still opens on that path — the option controls execution, not buffer creation
(`autoload/db_ui/query.vim:118` opens it unconditionally).

### Drawer keymaps that skip the buffer entirely

Buffer-local mappings on `FileType dbui`, resolving the table under the cursor and running the helper
straight to a `.dbout` buffer:

| Key | Action |
|---|---|
| `E` | Pick any helper for this table (`vim.ui.select`, rendered by telescope-ui-select) |
| `D` | Describe (`\d+`) |
| `I` | Index Detail |
| `Z` | Size & Rows |

`E`, `D`, `I`, `Z` are unused by dadbod-ui's own `ftplugin/dbui.vim`, and being buffer-local they
cannot collide with the global `<leader>d*` maps.

**Mechanism.** `db_ui#drawer#get()` is public and returns an instance whose `content` list is indexed
by line number. Table nodes carry:

```
type  = schemas->items->{schema}->tables->items->{table}
label = {table}
dbui_db_key_name = key into drawer.dbui.dbs
```

Schema and table are matched out of `type` rather than read from `label`, because schema nodes suffix
their label with a count (`public (51)`). Placeholder substitution mirrors
`autoload/db_ui/query.vim:134-138` exactly, so a helper behaves identically whichever way it is run.
Substitutions use replacement *functions* rather than strings, since a table name containing `%` would
otherwise be misinterpreted by `gsub`.

Execution is `db#execute_command('', 0, -1, -1, url .. ' ' .. content)`, which was verified to create a
`.dbout` buffer and no SQL buffer.

**Single source of truth.** Both the keymaps and the drawer's child nodes read
`db_ui#table_helpers#get(scheme)`. Anything added to `g:db_ui_table_helpers` later is automatically
available to both, with no second registration.

### Verified

| Check | Result |
|---|---|
| Multi-line helper via `db#execute_command` | pass — Index Detail, 14 lines |
| Meta-commands (`\set`/`\pset`) survive that path | pass — DDL output clean |
| `D` on a table node | pass — `\d+` for `public.about_edges`, **dbout only, no SQL buffer** |
| `D` on a non-table node | pass — warns "Put the cursor on a table", no error |
| `E` picker | pass — prompt `Helpers for public.ai_prompt_logs`, all 10 helpers offered |
| `E` → DDL | pass — `CREATE TABLE` output, dbout only |

## Out of scope

- No change to the existing connections or saved queries.
- No keymaps added; helpers alone cover the need.
- Helpers are defined for `postgresql` only. Other schemes keep their built-in helpers untouched.

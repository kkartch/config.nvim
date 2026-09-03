# Expert does not index new files; native LSP commands

**Date:** 2026-09-03
**Status:** Diagnosed and fixed. All claims below were measured, not inferred.

## Symptom

Newly added Elixir modules were invisible to Expert — no references, no go-to-definition — while
existing code worked. It read like a stale index.

## Root cause

**Expert v0.1.8 does not incrementally index new modules.** It knows only the files that existed when
it indexed the project.

Proven two ways against `~/src/grotto/apps/api`, each after waiting for the index to warm:

| How the file was created | Result |
|---|---|
| Written to disk outside the editor | **not found** — 18 attempts over 180s |
| Created *through* nvim, `didOpen` **and** `didSave` sent | **not found** — 18 attempts over 180s |

The second case rules out the obvious explanation. Expert registers **zero**
`workspace/didChangeWatchedFiles` watchers, even though the client correctly advertises
`dynamicRegistration = true` — so nothing tells it the file exists.

This is not a configuration fault. `root_dir` resolves correctly to `apps/api` (verified: there is no
`mix.exs` above it, so it is not an umbrella despite the `apps/` layout), the project compiles on the
host, and Elixir 1.18.1 matches the pin.

## Fix

Expert exposes a command that was simply undiscovered:

```
executeCommandProvider: { commands = { "Reindex", "connectionDetails" } }
```

Measured: new module → **NOT FOUND** (10 attempts / 60s) → `Reindex` → **found ~11s later**. No
restart required.

## Two further findings

### A ~30s cold-start window where requests are silently dropped

From Expert's log, on a fresh attach:

```
[ 0.5s] Received request textDocument/references before engine for api was initialized. Ignoring.
[ 4.3s] Engine initialized for project api
[ 8.1s] Compiled api in 2.8 seconds
[10.6s] Search index is loading for api...
[30.7s] references OK -- 7 results
```

Requests arriving before the engine is up are **ignored**, not queued or retried. So the first ~30s
after opening an Elixir file look like a dead server. This is expected behaviour, not a fault, but it
compounds the symptom above: it is easy to attribute the silence to the new file.

### The engine sometimes fails to start at all

```
Failed to start project node for api: {:shutdown,
 {:failed_to_start_child, {XPExpert.Project.Node, "api::74341911"}, {:error, :start_timeout}}}
```

Recurring on 2026-08-20 and 2026-08-27 for `api`, and once for `bn`. When this happens nothing works
for that project and `Reindex` cannot help, because there is no engine to reindex. **This is the case
that genuinely needs a restart** — and until now there was no way to perform one.

## Changes

All in `lua/custom/plugins/lsp.lua`.

### `:LspReindex` (+ `<leader>ri`)

Sends `workspace/executeCommand` with `Reindex`. Gated on the server advertising the command, so it
degrades to a warning rather than an error on servers that do not. The keymap is buffer-local and
registered from `LspAttach` only when the attached client advertises `Reindex`, so it never appears
where it would do nothing.

### `:LspRestart`, `:LspStop`, `:LspInfo`

Neovim core ships **none** of these — verified `vim.fn.exists()` returns `0` for all of them even with
a client attached. They came from `nvim-lspconfig`, which this config replaced in `8821b26`/`b93dfff`.

Rebuilt on the native API. `:LspRestart` records the attached buffers, stops the clients, **waits for
them to actually exit** (re-attaching first is silently ignored), then replays the `FileType`
autocommand that `vim.lsp.enable` hooks, which re-attaches. `:LspInfo` aliases
`checkhealth vim.lsp`, matching what current nvim-lspconfig now does.

Staying native was chosen over re-adding nvim-lspconfig because lspconfig does **not** provide
`Reindex` — the piece that actually fixes the reported problem — so it would have to be hand-written
either way, and it is the more useful of the two. Re-adding lspconfig would also put a second
`expert` config on the runtimepath, whose `cmd` expects `expert` on `$PATH` rather than the Mason
path.

### `lsp.log` cap

The log had reached **797 MB**. The log level is `WARN` (the default, not misconfigured) — Neovim
simply never rotates this file. Truncated at startup when it exceeds 50 MB.

## Verification

| Check | Result |
|---|---|
| `:LspRestart` / `:LspStop` / `:LspInfo` / `:LspReindex` defined | pass — all `exists() == 2` |
| `<leader>ri` bound buffer-locally, capability-gated | pass |
| New module before `:LspReindex` | **not found** — 8 attempts |
| After `:LspReindex` | **found** — notified `Reindexing: expert` |
| `:LspRestart` re-attaches | pass — `Restarted: expert`, client back, jump resolves |
| `lsp.log` truncation | pass — 797 MB → 0 |

Probe files created in `apps/api` during testing were removed; the repo was confirmed clean after
every run.

## Usage

After adding new modules — especially when an agent or generator writes them outside the editor — run
`:LspReindex` or `<leader>ri`. Allow ~10s. Reach for `:LspRestart` only when the engine failed to
start, which the log reports as `:start_timeout`.

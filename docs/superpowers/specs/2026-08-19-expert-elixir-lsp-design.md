# Replace ElixirLS with Expert

**Date:** 2026-08-19
**Status:** Implemented 2026-08-19. See *Implementation results* at the end.

## Problem

Cross-file code navigation is broken in Elixir buffers. Jumps *within* the current file resolve
correctly; jumps to another file fail — into project modules, into hex dependencies, into
macro-generated code, and into Elixir/Erlang stdlib alike.

That pattern — same-file works, cross-file does not — is the signature of a language server that
never completed a project-wide build, rather than one with weak go-to-definition support. ElixirLS
resolves same-file references from the syntax tree alone, but everything else depends on its
compiled project index in `.elixir_ls/build`. When that compile fails, navigation degrades to
exactly what is being observed.

A likely contributor is present in this environment: `~/src/portal.pdq.com` pins
`elixir 1.16.2-otp-26` in its own `.tool-versions`, while the global toolchain is
`elixir 1.18.1-otp-27` / `erlang 27.2.2`. ElixirLS has no per-project version handling, so a
mismatch of this kind can break its build silently.

## Decision

Replace ElixirLS with **Expert**, the official Elixir language server.

Expert is the amalgamation of the three prior community implementations — ElixirLS, Lexical, and
Next LS — developed by the official language server team announced by the core team in August 2024.
The three predecessors are slated to be archived. Current release: **v0.1.8 (2026-07-27)**, stable,
past release candidate.

The decisive technical reason, beyond it being the maintained path forward: **Expert detects each
project's configured Elixir and OTP version and rebuilds its analysis engine to match.** One binary
serves both the OTP 26 and OTP 27 projects on this machine. ElixirLS offers no equivalent.

## Approach

Mason-managed, clean cutover. This matches how every other server in this config is handled, and the
config is version-controlled, so a fallback copy of the old file would earn nothing that
`git revert` does not.

## Changes

### 1. New file: `lua/lsp/expert.lua`

`nvim-lspconfig` is not installed — `lua/custom/plugins/lsp.lua` replaces it with native
`vim.lsp.config` — so nothing supplies defaults and this table must be self-contained.

```lua
return {
  cmd = { vim.fn.stdpath('data') .. '/mason/bin/expert', '--stdio' },
  filetypes = { 'elixir', 'eelixir', 'heex', 'surface' },
  -- Umbrella-aware: search upward for up to 2 mix.exs and prefer the
  -- higher one, so sub-apps resolve against the umbrella root.
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    local matches = vim.fs.find({ 'mix.exs' }, { upward = true, limit = 2, path = fname })
    local child_or_root_path, maybe_umbrella_path = unpack(matches)
    on_dir(vim.fs.dirname(maybe_umbrella_path or child_or_root_path))
  end,
}
```

Two deliberate departures from the outgoing `elixirls.lua`:

- **`root_dir` function replaces `root_markers`.** The old `root_markers = { 'mix.exs', '.git' }`
  is a flat list, which selects the *nearest* ancestor containing *any* listed marker. In an
  umbrella or monorepo that roots the server at `apps/<sub_app>` instead of the workspace root,
  breaking cross-app navigation. The function above mirrors upstream's canonical config.
- **No `settings` block.** `dialyzerEnabled` and `fetchDeps` are ElixirLS-specific keys with no
  Expert equivalent. Expert's defaults are used.

### 2. Deleted: `lua/lsp/elixirls.lua`

### 3. `lua/custom/plugins/lsp.lua`

- `servers`: `'elixirls'` → `'expert'`
- `mason_packages`: `'elixir-ls'` → `'expert'`

### 4. `lua/lsp/emmet_language_server.lua`

Remove `'elixir'` from `filetypes`; keep `'heex'`. Emmet expansion is rarely wanted in `.ex` files,
and attaching there put a second language server on every Elixir buffer competing in the completion
menu.

### 5. `lua/custom/plugins/lint.lua`

The existing `BufWritePost` autocommand runs `try_lint 'credo'` unconditionally, for every filetype
— saving a `.lua` or `.ts` file shells out to `credo`. The file's own comment already flags this
("This should be filetype specific").

Fix: call `require('lint').try_lint()` with no argument. nvim-lint then dispatches on the buffer's
filetype via the `linters_by_ft` table directly above it.

**Resolved during implementation — narrowed as anticipated.** A bare `try_lint()` proved unsafe:
`nvim-lint` calls `vim.notify(..., ERROR)` on a failed spawn (`lint.lua:437`, guarded only by
`opts.ignore_errors`), and none of `luacheck`, `flake8`, `eslint`, `golangci-lint`, or `rubocop` are
installed on this machine. Bare dispatch would therefore raise an error popup on every `.ts`, `.lua`,
and `.py` save.

Final form filters `linters_by_ft` for the buffer's filetype down to linters whose command is
actually executable, and calls `try_lint(available)` only when that list is non-empty. Missing tools
are skipped silently and begin working on their own once installed.

Two details this surfaced:

- `credo`'s command is `mix`, not a `credo` binary — so Elixir linting is unaffected and continues to
  work. (The pre-existing autocommand was invoking `mix credo` on *every* save of *every* filetype,
  including in directories with no `mix.exs`.)
- `eslint` defines `cmd` as a *function* that resolves a project-local `node_modules/.bin/eslint`, so
  the filter must call it before testing. Passing a function to `vim.fn.executable()` raises
  `E1174: String required for argument 1`.

### 6. Mason state

The local registry copy is stale — cached `2026-07-11`, pinning `expert` at v0.1.6, before v0.1.8
shipped on 2026-07-27. Upstream already carries v0.1.8. Sequence: update the registry, install
`expert`, uninstall `elixir-ls`.

## Verification

Run against a real project, in order. Each step gates the next.

1. **Server attaches.** Open an `.ex` file; `:checkhealth vim.lsp` shows `expert` running.
2. **Root is correct.** `:lua =vim.lsp.get_clients({ name = 'expert' })[1].root_dir` returns the
   repository root, not a subdirectory.
3. **Project build completes.** Watch fidget for Expert's indexing progress. This is the step whose
   failure produces the reported symptom, so it must be confirmed finished before judging navigation.
4. **Cross-file navigation** — the actual acceptance criteria. `gd` must resolve:
   - into another module in the same project
   - into a hex dependency
   - into Elixir stdlib (`Enum.map/2`)
   - into macro-generated code (an Ecto schema field or a Phoenix router helper)
5. **Second project.** Repeat step 3 on `~/src/portal.pdq.com` (Elixir 1.16 / OTP 26) to confirm
   per-project engine rebuild works across the version boundary.
6. **Regressions.** Confirm formatting on save still works (conform, `mix format`), and that saving a
   non-Elixir file no longer invokes credo.

**If cross-file navigation still fails after step 3 confirms a completed build**, the cause is
environmental rather than server choice. Diagnose from Expert's logs (`:LspLog`) — do not call the
task complete.

## Expected, not defects

- **Higher memory on OTP 27.** Upstream documents dramatically increased memory use on Erlang 27
  caused by a bug in Erlang's ETS table compression. The global toolchain here is 27.2.2.
- **Slow first open per project.** The per-project engine rebuild is a one-time cost per Elixir
  version, then cached.

## Out of scope

- The uncommitted `.tool-versions` change in the working tree (`nodejs 22.8.0` → `24.13.0`) is
  unrelated and predates this work. It must not be swept into this commit.
- `elixir-tools.nvim` is not adopted. It is written by an Expert core team member but its Expert
  support is still in progress, and nothing in this design needs it.

## References

- [Expert repository](https://github.com/expert-lsp/expert)
- [Expert installation guide](https://github.com/elixir-lang/expert/blob/main/pages/installation.md)
- [Per-project Elixir versions](https://expert-lsp.org/docs/features/per_project_elixir/)
- [Announcing the official Elixir Language Server team](https://elixir-lang.org/blog/2024/08/15/welcome-elixir-language-server-team/)
- [Canonical `lsp/expert.lua` in nvim-lspconfig](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/expert.lua)


## Implementation results

All file changes applied; Mason registry updated to `2026-08-19-leafy-zipper`, `expert` **v0.1.8**
installed (`expert_darwin_arm64`, native Mach-O arm64), `elixir-ls` uninstalled. No `elixirls` or
`elixir-ls` references remain in any Lua file.

Verified headless against `~/src/bn` (Phoenix, 39 deps fetched, global toolchain):

| Check | Result |
|---|---|
| Expert attaches to `.ex` | pass — sole client on the buffer |
| `root_dir` | pass — `/Users/kyle/src/bn`, the repo root |
| Cross-file, same project (`Bn.Repo`) | **pass** — `lib/bn/repo.ex` |
| Hex dependency (`Phoenix.PubSub`) | **pass** — `deps/phoenix_pubsub/lib/phoenix/pubsub.ex` |
| Macro: `use BnWeb, :controller` | **pass** — `lib/bn_web.ex:1` |
| Macro: `render/3` via that `use` | **pass** — `deps/phoenix/lib/phoenix/controller.ex:937` |
| Macro: `pipe_through` | **pass** — `deps/phoenix/lib/phoenix/router.ex:923` |
| Scope-relative alias `PageController` | **pass** — `controllers/page_controller.ex:1` |
| Stdlib (`Supervisor`, `Application`) | **fail — known upstream gap, see below** |
| `conform` still formats Elixir | pass — `mix` |
| Emmet no longer attaches to `.ex` | pass |

Three of the four reported symptoms are fixed.

### Stdlib navigation is a documented Expert limitation

Probing both `textDocument/definition` and `textDocument/hover` at four stdlib positions
(`Supervisor`, `Supervisor.start_link`, `Application`, `Application.get_env`) returns **hover for all
four and a definition for none**. Expert resolves these symbols; it declines to return a location.

This is not a misconfiguration, a cursor-position problem, or missing source — Elixir's `.ex` sources
are present at `~/.asdf/installs/elixir/1.18.1-otp-27/lib/elixir/lib/` (246 files). Expert's own
[Go to Definition docs](https://expert-lsp.org/docs/features/go_to_definition/) state the feature
covers project and dependency code and "does not yet support navigating to definitions from the
standard library." Expect this to close in a future Expert release; nothing to do here.

### Unrelated blocker found in `portal.pdq.com`

That project pins `elixir 1.16.2-otp-26` / `erlang 26.2.2` in its `.tool-versions`, and **neither is
installed** — asdf has only Elixir 1.17.2/1.17.3/1.18.1 and Erlang 27.x/28.x. Running `elixir` in
that directory fails with "No version is set for command elixir."

So no language server can build that project today, and Expert will not change that. If Elixir
navigation was being judged there, this is the actual root cause. The fix is `asdf install` for the
pinned versions, or repointing the pin at an installed one — a decision for the repository owner, out
of scope here. Verification step 5 (per-project engine rebuild across a version boundary) is
therefore **unverified**, not failed.

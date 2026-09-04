# Jump from a defdelegate to its target

**Date:** 2026-09-04
**Status:** Implemented and verified against a live project.

## Problem

`gd` on a `defdelegate` does not reach the delegated function. It lands back on the line the cursor
already sits on.

The project uses the pattern heavily — **314 `defdelegate`s**, of which **25 are multi-line** — in two
shapes:

```elixir
defdelegate mint_losing_claims(...), to: GardenerReview           # name matches
defdelegate curation_context(view, all_views),                    # renamed target
  to: CurationContext, as: :proposal_briefing
```

## What the investigation changed

The obvious plan — yank the function name, jump to the module, search for the name — is
**unnecessary**. Expert already resolves a `defdelegate`'s function name directly to the target
function, and already follows `as:` correctly. Verified: `curation_context` resolves to
`curation_context.ex:25`, which is `def proposal_briefing`, not merely the module.

The real defect is narrower and was only visible in the UI, not in the protocol. Expert returns **two**
definitions for the function name:

```
[1] curation_context.ex:25   <- the delegated target
[2] concepts.ex:136          <- the defdelegate itself
```

Both are legitimate: a `defdelegate` genuinely does define the function at that site. But `gd` is bound
to `telescope.builtin.lsp_definitions`, and telescope **re-sorts the results, putting the current file
first**:

```
picker title: LSP Definitions
   1. concepts.ex:136        <- self-reference, preselected
   2. curation_context.ex:25 <- the target
```

So the jump goes nowhere. Reading the raw protocol array hides this completely — `result[1]` is the
correct target. The bug only exists after telescope's sort.

A second wrinkle: a multi-line `defdelegate` returns **three** results, the target twice plus the self
reference.

Position also matters. Definition only resolves within the function-name span; elsewhere on the
statement it returns nothing useful:

| Cursor position | Raw result |
|---|---|
| `defdelegate` keyword | none |
| function name | the target (plus self) |
| arguments | the current line only |
| `to:` | none |
| module name | the module's first line |

## Design

Extend `gd` rather than add a second binding, because `gd` on a `defdelegate` is currently *wrong*
rather than merely absent. Everywhere else `gd` is untouched.

`jump_to_delegate()` runs first and returns `false` to fall through to the normal
`telescope.builtin.lsp_definitions` whenever the cursor is not on a `defdelegate`.

1. **Find the statement.** If the cursor line has no `defdelegate`, walk up to 4 lines while the lines
   are `to:` / `as:` continuations. This is what makes the multi-line form work from any of its lines.
2. **Ask at the function name**, regardless of where on the statement the cursor actually is. This
   makes every column behave the same and is why no parsing of `to:` or `as:` is needed — Expert
   resolves the target itself.
3. **Drop the self-reference** — any result inside the statement's own line range. The statement's
   extent is computed by scanning forward over continuation lines, so a target defined in the same file
   is not discarded by accident.
4. **Dedupe** by `uri:line:character`, required by the multi-line case.
5. **Jump** with `vim.lsp.util.show_document`, after `normal! m'` so `<C-o>` returns. Exactly one
   result survives in all three shapes, so no picker appears. If more than one survives the filter the
   case is genuinely ambiguous, and it falls back to the usual telescope picker rather than guessing.

On the module name the jump also goes to the function, by choice: one uniform rule for the whole
statement.

## Verification

Against `~/src/grotto/apps/api/lib/grotto/concepts.ex`, driving the real `gd` mapping and asserting on
the **content of the landed line** rather than line numbers.

| Case | Cursor | Result |
|---|---|---|
| `rename_concept` → `to: ReviseConcept, as: :rename` | keyword / name / module | `def rename` — 3/3 |
| `curation_context` → `as: :proposal_briefing` | keyword / name / module | `def proposal_briefing` — 3/3 |
| `mint_losing_claims` (multi-line) | keyword / name / module / `to:` line | `def mint_losing_claims` — 4/4 |
| Regression: `alias` line, not a defdelegate | — | still jumps normally |

**11 pass, 0 fail.** No picker in any case.

## Failure messages

The first real-world use hit `No delegate target found` on
`defdelegate rename_concept(...), to: ReviseConcept, as: :rename`. The jump logic was correct: the
server returned only the defdelegate's own site, so the filter emptied the list.

The cause was the Expert limitation documented in
[2026-09-03](./2026-09-03-expert-reindex-and-lsp-commands.md). `Actions.ReviseConcept` was created the
same day in commit `06db036e`; the editor session predated the file, and Expert does not index new
modules on its own. A fresh server resolved it immediately. `:LspReindex` fixes it.

The message now distinguishes the two cases, so this diagnoses itself:

- nothing came back at all -> `defdelegate: no definition returned`
- only the definition site came back -> `defdelegate: only the definition site resolved -- the target
  module may not be indexed yet, try :LspReindex`

The second is verified by pointing a `defdelegate` at a module that does not exist, which produces
exactly that notification and leaves the cursor where it was.

## Two testing traps worth recording

**Assert on content, not line numbers.** The first test run failed everything because `concepts.ex`
changed mid-session — commit `06db036e` moved `rename_concept` to `Actions.ReviseConcept` and gave it
an `as: :rename`, shifting every line. The test now locates each `defdelegate` by name and asserts the
landed line matches `def <target>`, so it survives further edits.

**Suppress the swap-file prompt in headless runs.** One case failed reproducibly for a reason that had
nothing to do with the code: the file was open in a running editor, so opening it raised
`E325: ATTENTION`, which aborted `show_document` mid-jump and left the cursor on line 1. The other two
targets were not open, which is exactly why only that one failed. Headless verification against a live
working copy needs `-c 'set shortmess+=A'`.

Both traps produced *confident, plausible, wrong* results. Neither was visible without reading the full
stderr.

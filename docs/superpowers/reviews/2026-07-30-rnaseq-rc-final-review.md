# Final whole-branch review — `rnaseq-rc`

**Range:** `27cd7cd..4ddbf05` (36 commits) · **Reviewer:** Opus subagent, final
whole-branch pass after every task had passed its own scoped review ·
**Date:** 2026-07-30 · **Verdict: ready to merge, with fixes**

Suite state at review time: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 280 ]` in 46.5s.

> Transcribed verbatim from the reviewer's returned report, which was otherwise
> only in terminal scrollback and a session-scoped transcript. One annotation
> added by the controller, marked **[CORRECTION]**.

---

## Strengths

- **The deterministic/LLM boundary genuinely holds.** `lib/R/counts_files.R` has no
  reference to `llm_*` anywhere, and the counts file content is never sent to the
  API — only column headers (`sample_annotation.R:43-54`) and the `sample-info`
  text. That containment is the single most important architectural claim in the
  spec, and it is real, not aspirational.
- **Gate 1's rewrite is implemented soundly and documented better than most
  production code.** `sample_annotation.R:236-252` explains *why* it must not be
  `stop_if_entity_invalid()`, names the masking mechanism (`TESTTHAT=true`
  converting `quit()` into `stop()`), and tells a future maintainer not to
  "simplify" it back. The regression test at `test_sample_annotation.R:88-107` uses
  a duplicate-`sample.ID` annotation that passes gates 2 and 3 and fails only
  entity validation — it genuinely trips gate 1 and nothing else, and its comment
  honestly states that the test alone cannot fully protect against the regression.
- **Task 8b's fix is at the right layer.** `.stop_llm_api_error()`
  (`llm_client.R:128-133`) is a silent classed condition, and
  `classify_sample_ids()` converts it at its own call site
  (`sample_annotation.R:63-68`) precisely because it is the one `llm_text` caller
  not inside a retry. The reasoning is written down at both ends.
  `error_helpers.R` is byte-identical to `main`.
- **`counts_files.R` validation is unusually careful about readr's foot-guns.**
  `na = character(0)` with the comment at :192-196 (so blank/`"NA"` cells reach our
  own validator rather than becoming silent `NA`), and the
  `withCallingHandlers(..., vroom_parse_issue = ...)` narrowing at :208-218 rather
  than blanket `suppressWarnings()`. The column-major index arithmetic at :262-271
  to recover the offending gene/sample from a flat vector position is correct and
  produces a genuinely actionable message.
- **`check_deseq_suitability()` is not a no-op.** Verified independently in
  study-wrangler: `get_variable_metadata` (`R/Entity-methods.R:655-663`) filters
  `!data_type %in% c('id','category')`, so `sample.ID` is excluded from `vars` and
  cannot be miscounted as a varying factor. Fixture 17's pinned message
  (`usable factor variables among {} = FALSE`) confirms it.
- **Mock security is fail-closed and correctly reasoned.** `llm_mocks_init()`
  requires `identical(Sys.getenv("WRANGLER_ALLOW_LLM_MOCKS"), "1")` — exact match,
  so unset/`"true"`/typo all leave mocks off. Same construction for the `-live`
  skip (`test_examples.R:50`). An uploaded `llm-mocks.json` cannot divert
  production. `.env` is gitignored; `example.env:92` ships the key empty; no
  credential material anywhere in the diff.
- **`bin/` untouched** (`git diff --name-only 27cd7cd..4ddbf05 -- bin/` is empty),
  and `bulk-rnaseq-counts` survives only in the plan's own "never use this"
  instruction.

---

## Deferred-findings triage

| Finding | Verdict |
|---|---|
| `llm_client.R` retries generic network errors beyond 429/5xx | **Fine to defer.** Idempotent POST, capped at 3 attempts, ~3s total backoff. `test_sample_annotation.R:109-156` now covers this branch end-to-end via mocked `httr::POST`. |
| Unreachable `stop_unexpected_error()` after the retry loop | **Not actually a problem** as code, but the comment at `llm_client.R:217` is now doubly wrong — it says "stop_unexpected_error" in spirit while calling `.stop_llm_api_error()`, and cites "R CMD check" for a file that is `source()`d, never packaged. One-line comment fix. |
| Real-API path thinly covered | **Fine to defer.** Task 8b's `local_mocked_bindings(POST = ...)` test now drives the network-error branch, the success branch, and the missing-key branch. The genuinely untested edges (non-2xx, malformed body) are ≤5 lines each. |
| No test for an all-`__` counts file | **Not actually a problem.** `counts_files.R:229` drops the rows, then `:240` catches `nrow == 0` with a specific message. The identical code path is covered by the `no_genes` case in `test_counts_files.R:132`. |
| Duplicate sample-column headers unguarded | **Fine to defer**, but the ledger analysis understated one part and overstated another — see Minor 1. `setdiff()` at `counts_files.R:231` de-duplicates, so the duplicate column's values are *never validated*; but the end state is still a loud failure (duplicate `assay.ID` → `stop_if_entity_invalid` → exit 99), not silent corruption. Compounds with nothing dangerous. |
| Unescaped tabs/newlines in TSV values | **Must fix before merge** — and it is *not* inherited from the JS original in the way recorded. See Important 1. |
| No test for a sample missing a factor key, or `factors = list()` | **Fine to defer** for factor keys (`annotations_to_stf.R:98-101` fills `NA → ""`, length fixed by `vapply`). `factors = list()` is covered by `test_sample_annotation.R:197-205`. |
| Attempt-1/attempt-2 near-duplication | **Fine to defer.** ~14 lines, and the terminal-path fix will touch this block anyway. |
| `grepl(id, text, fixed = TRUE)` substring false-negative | **Fine to defer.** Fails *open* only: a missed ID falls through to the LLM, and gate 3 catches the omission → retry → transformation error. Worse message, correct outcome. |
| Temp STF dirs never `unlink()`d | **Fine to defer.** Two small dirs per import in a per-import container. |
| Gate 1 lost `format = "full"` detail | **Fine to defer.** Debuggability only; the `format = "upload"` text is what feeds the retry prompt, which is the load-bearing use. |
| Fixtures `03` and `05` overlap | **Fine to defer.** Cheap; `vdi-meta.json` comments now say what they do and don't prove. |
| ~3s real `Sys.sleep()` in a test | **Fine to defer.** 3s of 46.5s. |
| Live fixture doesn't check semantic correctness | **Fine to defer** — inherent to non-deterministic model output, and the spec's "Known follow-ups" says so. |
| `doc/rnaseq-rc.md` omits the >30-sample warning | **Fine to defer.** It appears only on a failure path the doc doesn't otherwise enumerate. |

---

## Issues

### Critical (must fix)

None.

### Important (should fix)

**1. `annotations_to_stf.R:102` — a missing `label` (or `sampleId`) silently shifts
every subsequent TSV column. This is a port defect, not inherited.**

```r
paste(c(s$sampleId, s$label, row_factor_vals), collapse = "\t")
```

`c()` drops `NULL`. Verified: `paste(c("a", NULL, "b"), collapse="\t")` →
`"a\tb"`. So if the model omits `label` for one sample, that row emits N−1 fields
against an N-field header: `label` silently receives the first factor's value, and
the last factor column becomes `NA`.

**No gate catches this.** Gates 2 and 3 only compare ID sets; the IDs are still
correct. Type inference uses `factor_values` computed from the JSON (`:84-92`), not
from the TSV, so the shift doesn't perturb the declared types — a
shifted-but-string-valued row validates cleanly. The result is a study with wrong
sample metadata and no error.

The JS original does **not** have this bug —
`[s.sampleId, sraIds, s.label, ...vals].join('\t')` renders `undefined` as an empty
string and preserves the field count. The R port introduced it.

The same `c()` drops apply to a `NULL` `sampleId`, but that case *is* caught (gate 2
sees an invented ID).

Fix (2 lines, and it makes the retry loop do the right thing):

```r
nz <- function(x) if (is.null(x) || length(x) != 1) "" else as.character(x)
paste(c(nz(s$sampleId), nz(s$label), row_factor_vals), collapse = "\t")
```

Then the unescaped-tab/newline finding: with the field count guaranteed, a literal
tab or newline in an LLM-authored `label` or factor value is the remaining way to
shift columns — and it is now reachable by a prompt-injecting uploader ("make every
label `X<tab>Y`"). Sanitising in the same helper closes both:
`gsub("[\t\r\n]+", " ", ...)`. `definition` and `displayName` are safe —
`yaml::as.yaml()` escapes them (pinned by `test_annotations_to_stf.R:50-58`).

**2. `sample_annotation.R:370-380` — a Claude API outage after the retry is reported
as a *transformation* error blaming the uploader's metadata, contradicting the
spec's own taxonomy.**

The design spec (`2026-07-29-rnaseq-rc-design.md:356`) says: *"API outage, auth
failure, malformed API response → `stop_unexpected_error` → 255."* That holds for
`classify_sample_ids()`. It no longer holds for the annotation step.

Since Task 8b made `llm_api_error` catchable, two consecutive API failures land in
the terminal branch and produce:

> `We were unable to automatically generate a valid sample annotation from your
> uploaded sample metadata, even after a second attempt.` → exit **99**

An outage on our side therefore tells the uploader their metadata is bad, and
signals *user error* (99) rather than *plugin error* (255) — so VDI won't classify
it as ours to fix. Task 8b fixed a real bug (a recovered error printing to STDOUT)
and, in doing so, moved an unrecovered one into the wrong bucket. This is exactly
the kind of seam a task-scoped review can't see: gate/terminal wording was Task 4's,
the condition class was Task 8b's.

The condition class survives `tryCatch(..., error = function(e) e)`, so the fix is
cheap:

```r
if (inherits(attempt_2, "llm_api_error")) {
  stop_unexpected_error(
    user_msg = "The wrangler could not reach the Claude API to process your sample metadata. Please try again later.",
    technical_msg = paste("First attempt error:", conditionMessage(attempt_1),
                          "\nSecond attempt error:", conditionMessage(attempt_2))
  )
}
```

Fixtures 12/16/22 regex-match the *transformation* path and are unaffected (mock
exhaustion and bad IDs are plain `stop()`s, not `llm_api_error`).

**3. Nothing prevents `make test` from making real, billable API calls.**

`docker-compose.yml` now passes `CLAUDE_API_KEY` into every `docker compose run`,
including `makefile`'s `test` target. `test_examples.R:29` sets
`WRANGLER_ALLOW_LLM_MOCKS=1`, which *permits* mocks but does not *forbid* real
calls: `.llm_mock_pop()` returns `found = FALSE` when no queue exists for a
`call_name`, and `llm_text()` proceeds straight to `httr::POST`.

All 24 fixtures were enumerated — today this is latent, not live: every fixture that
reaches the LLM has an `llm-mocks.json`, and the seven without one (13, 14, 15, 19,
20, 23, 24) fail in `discover_counts_files()`/`read_counts_long()` first. But a
future fixture with a forgotten mocks file, a typo'd `call_name`, or a defect that
lets a "should fail early" fixture reach step 3 spends money silently and makes the
suite network-dependent. Given the human explicitly budgeted live calls at 20, a
fail-closed guard is cheap insurance.

The clean fix is in `test_examples.R` (volume-mounted, no rebuild) rather than
`llm_client.R`, because the live fixtures share the process and must stay exempt:
set a `WRANGLER_LLM_OFFLINE=1` env var per example for non-`-live` datatypes and
unset it for `-live` ones, and have `llm_text()` refuse a real call when it is set.

### Minor (nice to have)

1. **`counts_files.R:231` — `setdiff()` de-duplicates, so a duplicate-named sample
   column escapes count validation.** `count_matrix` (`:262`) then selects the first
   match twice, so the second column's values are never checked against `^\d+$`;
   `as.integer()` at `:287` turns garbage into `NA` with an uncaught coercion
   warning. The upload still fails (duplicate `assay.ID` →
   `stop_if_entity_invalid` → 99), and for the stranded path `full_join` (`:310`)
   additionally emits dplyr's many-to-many warning. So the compounding is *noise*,
   not corruption — but the message the uploader sees ("could not be loaded into the
   database … duplicate IDs") won't tell them they have two columns called `S1`. A
   one-line `any(duplicated(names(raw)))` check next to the duplicate-gene check
   would produce the right message.
2. **`wrangle-rnaseq-rc.R:34` — `assay.ID = paste(sample.ID, Gene, sep = ".")` can
   collide** (sample `A.B` + gene `C` vs sample `A` + gene `B.C`). Fails loudly via
   duplicate-ID validation, so it's a message-quality issue, not correctness. Worth
   a comment at minimum.
3. **A pathological counts file can still produce a bare R traceback and exit 1.**
   `readr::read_delim` errors (unreadable file, embedded nuls, a directory named
   `unstranded-counts.tsv`) propagate uncaught through `wrangle()` to
   `bin/wrangle.R`, which has no top-level handler — no STDOUT message for the
   uploader, and an exit code `lib/includes.sh` doesn't define. Pre-existing and
   shared with every other wrangler, and `bin/` is off-limits on this branch, so
   it's a follow-up, not a merge blocker.
4. **Unbounded `sample-info` size flows into two Sonnet prompts.**
   `read_sample_info_text()` reads the whole file, and `annotation_prompt()`
   interpolates it verbatim — twice on the retry path. A large upload is real token
   spend, and it's the only unbounded input reaching the API. Whether this matters
   depends on VDI's upload size cap. A `nchar()` guard in `discover_counts_files()`
   (reject > ~100KB with a validation error) is the cheap answer if the cap is
   generous.
5. **`llm_client.R:140`** documents `@param model` with the example
   `"claude-opus-5"`, which the code never uses. Cosmetic, but the kind of stale
   example that invites someone to "fix" the real model IDs.
6. **`claude-haiku-4-5-20251001`** is a valid ID, but `claude-haiku-4-5` is the
   preferred alias — the dated form pins a snapshot needing manual migration.
   `claude-sonnet-5` is correctly the alias form. Both are human-ruled in the plan;
   flagged only so the pin is deliberate.
7. **Latin-1/UTF-16 `sample-info`.** This repo has explicit encoding tests
   (`isasimple/09-iso8859-OK`), and `jsonlite::toJSON` on non-UTF-8 bytes raises a
   plain error inside `attempt_1` → retried → same failure → transformation error
   blaming the metadata. Contained, poorly diagnosed, untested.

---

## Recommendations

- **[CORRECTION — controller]** The reviewer reported the working tree as not clean,
  with a one-line wording change in `doc/rnaseq-rc.md`, and inferred the reviewed
  head and on-disk state had diverged. That change was the **human's own edit**, made
  during the review. It is committed as `43931dd`. No process violation occurred and
  the reviewer's observation was correct on the facts.
- Fold Minor 3 (no top-level handler in `bin/wrangle.R`) into the spec's "Known
  follow-ups" next to the entity-name item. A single `tryCatch` there would convert
  every bare-traceback path across all four datatypes into a proper exit-255 with a
  user message — the highest-leverage change available once a rebuild is affordable.
- The ledger is the most useful artifact of this branch after the code. Two entries
  needed correcting: the TSV-escaping finding is a **port defect**, not inherited
  from the JS; and the duplicate-header finding's `full_join` framing should note
  that `setdiff()` de-duplicates, so the real hole is *unvalidated values*, not
  many-to-many row explosion. (Both applied.)
- The comment discipline in `sample_annotation.R` and `counts_files.R` — explaining
  *why* a non-obvious choice exists and what not to "simplify" — is worth holding as
  the standard for this repo. It is the reason most deferred findings could be
  triaged by reading rather than by experiment.

---

## Assessment

**Ready to merge?** With fixes.

**Reasoning:** The architecture is sound, the deterministic/LLM boundary and
mock-security posture hold under scrutiny, and the two human-ruled deviations
(catchable gate 1, `this.path`) are implemented well and documented against
regression. Three things should land first: the `paste(c(...))` NULL-drop in
`annotations_to_stf.R:102`, which is a silent-metadata-corruption path that no gate
catches and that the JS original does not have; the terminal-error taxonomy in
`generate_sample_entity()`, where an API outage now reports as exit-99 user error
against the branch's own spec; and a fail-closed guard so `make test` cannot bill
the API. Each is a handful of lines and none touch `bin/`.

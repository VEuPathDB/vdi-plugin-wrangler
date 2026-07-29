# Bulk RNA-seq counts wrangler — design

Date: 2026-07-29
Branch: `bulk-rnaseq-counts`
Supersedes: `PLAN.md` (retained as the originating brief; this document is authoritative where the two disagree)

## Goal

Add a `bulk-rnaseq-counts` user dataset type to the VDI wrangler plugin. A user uploads two or three
files in a zip; VDI unpacks them into the plugin's input directory. The plugin turns them into an
EDA-loadable study containing a sample entity and a counts entity.

## Core design principle

Count-file handling is fully deterministic. The only LLM-dependent step is generating a correctly
formed sample annotation. Consequently:

- count-file validation failures fail immediately
- sample-annotation validation failures may trigger exactly one LLM retry
- final study-validation failures fail; they indicate a processing or linkage bug, not an
  annotation-generation problem

## Input contract

```
sense-counts.{txt,tsv,csv}  +  antisense-counts.{txt,tsv,csv}
        — or —
unstranded-counts.{txt,tsv,csv}
        plus
sample-info.{txt,tsv,csv}
```

Fixed filename stems. Any of the three extensions, matched case-insensitively. The delimiter is
sniffed from file content, so a `.txt` may be tab- or comma-separated.

Count files have genes as rows and samples as columns. Column 1 is the gene ID **by position**; its
header may be anything, including empty — production HTSeq output has an empty first header cell,
which `readr` names `...1`.

### Count-file validation rules

Every rule below is a hard failure (`stop_validation_error`) except where stated:

- exactly one file per recognised stem; a stem appearing zero or twice is an error
- `sense-counts` without `antisense-counts` (or vice versa) is an error
- `unstranded-counts` alongside either stranded file is an error
- `sample-info.*` must be present and non-empty
- no unrecognised `.txt`/`.tsv`/`.csv` files in the input directory — an unexpected extra file is
  more likely a misnamed count file than a deliberate extra, and silently ignoring it would mean
  silently ignoring the user's data
- at least one sample column and at least one gene row
- no duplicate gene IDs
- every non-gene-ID cell parses as a non-negative integer; blank, non-numeric, fractional and
  negative values all fail
- rows whose gene ID starts with `__` are dropped silently (HTSeq's `__no_feature`,
  `__ambiguous`, `__too_low_aQual`, …)
- for stranded input, sense and antisense must have identical **sample column sets** (order is free)
  and identical **gene row sets**

The last rule is a deliberate divergence from production `wrangleRNASeq.R`, which `inner_join`s on
`(sample.ID, Gene)` and therefore silently drops genes present in only one file. Silent data loss is
worse than a clear error for user uploads.

The authoritative sample-ID set is the shared set of count-file sample columns. `PLAN.md` §1 called
this a union; with identical sample columns required, union and intersection coincide.

## Processing flow

`wrangle(input_dir)` in `lib/R/wrangle-bulk-rnaseq-counts.R`:

1. `llm_mocks_init(input_dir)`
2. Discover and validate count files. Derive the authoritative sample-ID set.
3. Classify the sample IDs as `labels_informative` or `labels_uninformative` (Haiku 4.5).
   If uninformative, check deterministically that every sample ID appears literally in
   `sample-info.*`; if any is absent, fail before spending a Sonnet call.
4. Generate the sample annotation. Validate. Retry once on failure. Fail on second failure.
5. DESeq-suitability check.
6. Build the counts entity.
7. `study_from_entities()` and return.

Step 7 returns to `bin/wrangle.R`, which already calls `validate()` and `export_to_vdi()`. The
wrangler does not duplicate that.

## Counts entity

One tall entity, named `HTSeq counts`, parent `sample`. One row per (sample × gene). This follows
production `study-dealer-nextflow/bin/wrangleRNASeq.R` and overrides `PLAN.md` §7, which described
separate sense and antisense entities.

```
assay.ID      sample.ID  Gene     Sense.Count  Antisense.Count
S1.PF_0100    S1         PF_0100  120          3
S1.PF_0200    S1         PF_0200  4            0
S2.PF_0100    S2         PF_0100  98           7
```

| Column | Role |
|---|---|
| `assay.ID` | own level-0 ID, `paste(sample.ID, Gene, sep = ".")`, hidden from `variableTree` |
| `sample.ID` | parent FK to `sample`, hidden from `variableTree` |
| `Gene` | `stable_id = "VEUPATHDB_GENE_ID"` |
| `Sense.Count` | `stable_id = "SEQUENCE_READ_COUNT_SENSE"`, `is_featured = TRUE`, `display_order = 1` |
| `Antisense.Count` | `stable_id = "SEQUENCE_READ_COUNT_ANTISENSE"`, `display_order = 2` |

Unstranded input produces the same entity shape with a single `Count` column,
`stable_id = "SEQUENCE_READ_COUNT"`, in place of the two stranded columns.

Built with `entity_from_tibble(..., skip_type_convert = TRUE)` then `set_parents('sample', 'sample.ID')`.
`skip_type_convert` matters: per-column type inference across a wide intermediate is slow and can
yield inconsistent types.

No variable collections. Production uses collections only for WGCNA eigengenes, which are out of
scope here.

## Sample annotation

### Classification (step 3)

Haiku 4.5 (`claude-haiku-4-5-20251001`). Input: the authoritative sample IDs. Output: the single
token `labels_informative` or `labels_uninformative`.

`male_3h_rep1` style IDs are informative and need not appear in `sample-info.*`. `S001` style IDs are
uninformative and must be explicitly mapped there.

### Generation (step 4)

Sonnet 5 (`claude-sonnet-5`). Input: the authoritative sample IDs and the verbatim contents of
`sample-info.*`. Output: annotation JSON in the schema the `sample-annotations-to-stf` dataset-curator
skill already uses:

```json
{
  "profileSetName": "Short description of the experiment",
  "factors": {
    "timepoint": { "displayName": "timepoint", "definition": "Time elapsed after treatment", "unit": "hour" }
  },
  "samples": [
    { "sampleId": "S001", "label": "infected 24h", "factors": { "timepoint": "24" } }
  ]
}
```

Prompt content is ported from `skills/curate-bulk-rnaseq/resources/step-2-analyze-samples.md`:
factor identification, `displayName`/`definition`/`unit` rules, unit stripping from values, label
rules (no replicate numbers, so replicates share a label).

`label` is a fixed-schema field: always `string`/`categorical`, never carries a unit, and deliberately
conflates all factors (`female_4h_uninfected`). Production sets it `is_featured = TRUE` and forces it
to `display_order = 1`; this design keeps that.

### JSON → STF → entity

`lib/R/annotations_to_stf.R` is an R port of
`dataset-curator/skills/sample-annotations-to-stf/scripts/sample-annotations-to-stf.js`. It writes
`entity-sample.tsv` and `entity-sample.yaml` into a **temp directory**, never `input_dir`. The entity
is then read back with `entity_from_stf(tsv_path)`, which auto-discovers the sibling YAML.

Round-tripping through STF rather than constructing the entity in memory buys study-wrangler's own
YAML field validation (unknown fields hard-error with the allowed list) and leaves an inspectable
artifact for debugging.

Two deviations from the JS original:

- serialise YAML with `yaml::as.yaml()`, not string concatenation. The JS emits
  `display_name: ${value}` unquoted, which breaks as soon as an LLM-written `definition` contains a
  colon.
- omit the `SRA.ID.s.` column. User uploads have no SRA accessions.

Type inference follows the JS rules, corrected for study-wrangler's actual `data_type` factor levels
(`id`, `string`, `number`, `date`, `longitude`, `integer`, `category` — there is no `boolean` or
`decimal`, contrary to the stale `STF_documentation/metadata-fields.md`):

| Values | data_type | data_shape |
|---|---|---|
| all integers | `integer` | `continuous` |
| all numeric | `number` | `continuous` |
| all `YYYY-MM-DD` | `date` | `continuous` |
| otherwise | `string` | `categorical` |

The sample entity's ID column is named `sample.ID`, so the TSV's first header cell is
`sample.ID \\ Descriptors` (two literal backslashes) — the marker tells the STF reader where ID
columns stop. The YAML declares `id_column: sample.ID` with `entity_name: sample`. This matches both
the JS original and production `wrangleRNASeq.R`, which does
`set_variable_metadata('sample.ID', display_name = "Sample ID", hidden = list('variableTree'))` and
`set_parents('sample', 'sample.ID')` on the counts entity. The sample entity is the study root and
has no parent, so there are no preceding parent ID columns.

### Validation gates

In order:

1. entity validity via `stop_if_entity_invalid()` (profiles `baseline` + `eda`)
2. every generated sample ID is a member of the authoritative set
3. every authoritative sample ID is present in the generated entity

Any failure triggers exactly one retry. The retry prompt repeats the original instructions and adds
the validation messages, an instruction to correct them, and a reminder that sample IDs must come
from the supplied authoritative set.

A second failure is fatal (`stop_transformation_error`). When the sample count is large (> 30), the
message additionally carries: *"This dataset contains a lot of samples (N), which can challenge our
AI-based processing."* Claude Code agents script annotation generation at this scale rather than
working from deep context; the plugin cannot, because it makes plain message calls with no tool use.
Detecting the resulting validation failure and saying so is the available mitigation.

### DESeq-suitability check (step 5)

Runs after annotation validation, before entity construction. Suitable if:

- `n_samples >= 2`, **and**
- at least one variable that is neither the ID column nor `label` has ≥ 2 distinct values

No type-awareness. This accepts `timepoint: 1,2,3,4` with one sample each (groupable into early/late)
and `tissue: liver,spleen,brain,gut`. It rejects annotations carrying only `sample.ID` + `label`,
since `label` conflates factors and cannot define a contrast on its own; it also rejects
all-constant annotations and single-sample datasets.

Failure is fatal (`stop_validation_error`).

## LLM client

`lib/R/llm_client.R`. No new dependencies — `httr` and `jsonlite` are both already installed via apt
in the Dockerfile.

```r
llm_json(call_name, model, system_prompt, user_prompt, max_tokens)
```

`httr::POST` to `https://api.anthropic.com/v1/messages` with `x-api-key`,
`anthropic-version: 2023-06-01`. Plain message calls only — no tool use, so no associated attack
surface. Three attempts with exponential backoff on 429 and 5xx. Markdown code fences are stripped
from the response before `jsonlite::fromJSON`.

`CLAUDE_API_KEY` comes from the environment. It exists in `.env` today but `docker-compose.yml` does
not list it under `environment:`, so it never reaches the container; this design adds it there and to
`example.env`. Production deployment must supply it by the same mechanism.

API outage or auth failure is `stop_unexpected_error` (exit 255) — it is ours to fix, not the user's.

## Mocking

`llm_mocks_init(input_dir)` reads `llm-mocks.json` from the input directory, but **only** when
`WRANGLER_ALLOW_LLM_MOCKS=1`. Production never sets that variable, so a user who uploads
`llm-mocks.json` cannot divert a real run.

```json
{
  "classify_labels": ["labels_uninformative"],
  "annotate": [
    { "…deliberately broken annotation…" },
    { "…corrected annotation…" }
  ]
}
```

Responses are ordered queues keyed by `call_name`, so a retry receives a different answer from the
first attempt. `llm_json` pops the next queued response when one is registered for its `call_name`,
and errors if the queue is exhausted — an unexpected extra call is a test failure, not a silent
fallthrough to a paid API call. The file doubles as readable documentation of the LLM contract.

## Test strategy

Two additions to `tests/testthat/test_examples.R`, which is volume-mounted and so needs no rebuild:

- `Sys.setenv(WRANGLER_ALLOW_LLM_MOCKS = "1")` in the preamble
- skip datatype directories whose name ends in `-live` unless `WRANGLER_LLM_LIVE=1`

Live directories reach the real wrangler through the existing `vdi-meta.json` `type.name` override, so
no duplicate harness is needed.

All changes are confined to `lib/R/`, `tests/`, `doc/` and the compose files. `bin/` is not
volume-mounted, so touching it would cost a 45-minute rebuild per iteration.

### Fixtures

~10 genes per fixture. Nothing in the logic scales with gene count, and
`phenotype/10-performance-10k-genes-OK` already covers volume. The `__`-row fixture carries ~10 real
genes plus three HTSeq specials. The large-N fixture has 30+ sample columns and still only 10 genes.

### Test directories

`tests/testthat/bulk-rnaseq-counts/`:

| Directory | Covers |
|---|---|
| `01-unstranded-horizontal-tsv-OK` | unstranded counts, horizontal TSV sample-info |
| `02-stranded-pair-OK` | sense + antisense merge |
| `03-horizontal-csv-OK` | horizontal CSV sample-info |
| `04-vertical-tsv-OK` | vertical TSV sample-info |
| `05-vertical-csv-OK` | vertical CSV sample-info |
| `06-free-text-OK` | free text describing the samples |
| `07-methods-text-OK` | article methods text |
| `08-informative-ids-not-in-sample-info-OK` | `labels_informative`, IDs absent from sample-info |
| `09-opaque-ids-mapped-OK` | `labels_uninformative`, IDs correctly mapped |
| `10-opaque-ids-missing-BAD` | `labels_uninformative`, IDs absent → fail before Sonnet call |
| `11-retry-corrects-OK` | first annotation invalid, retry succeeds |
| `12-retry-fails-BAD` | both annotations invalid |
| `13-bad-count-filename-BAD` | unrecognised count filename stem |
| `14-malformed-counts-BAD` | ragged rows / non-numeric cells |
| `15-inconsistent-sample-columns-BAD` | sense and antisense disagree on samples |
| `16-generated-ids-not-in-counts-BAD` | annotation invents a sample ID |
| `17-deseq-unsuitable-BAD` | only `sample.ID` + `label` |
| `18-awkward-gene-ids-OK` | gene IDs that tibble name-repair would mangle survive the transpose |
| `19-negative-counts-BAD` | negative count value |
| `20-duplicate-genes-BAD` | duplicate gene IDs |
| `21-htseq-underscore-rows-OK` | `__no_feature` etc. stripped |
| `22-many-samples-warning-BAD` | 30+ samples, retry fails, large-N warning present |
| `23-sense-without-antisense-BAD` | incomplete stranded pair |
| `24-gene-set-mismatch-BAD` | sense and antisense disagree on genes |

`tests/testthat/bulk-rnaseq-counts-live/` holds the opt-in real-model tests, skipped unless
`WRANGLER_LLM_LIVE=1`.

`PLAN.md` also lists "count-to-sample linkage failures during final study validation". That case is
**unreachable by construction**: validation gates 2 and 3 together force the generated sample-ID set
to equal the authoritative set, and gate 1's `entity_id_no_duplicates` rules out duplicates, so
`validate_study_entity_relationships` cannot find an orphan. Rather than write a test that can only
pass vacuously, `18-awkward-gene-ids-OK` covers a linkage risk that *is* real: the transpose routes
gene IDs through `pivot_wider(names_from = ...)`, making them column names momentarily, so gene IDs
containing spaces or punctuation can be silently altered by name repair before becoming `Gene`
values. Sample IDs are never exposed to this — they stay as values throughout.

Passing directories get `assert.R` files pinning entity shape, stable_ids and row counts. The
existing harness otherwise only checks that import completed and that the expected number of cache
files exist.

Failing directories get `expected_technical_error_regex` and `expected_user_error_regex` in
`vdi-meta.json`, following the existing convention.

## Error taxonomy

| Condition | Helper | Exit |
|---|---|---|
| count-file problems | `stop_validation_error` | 99 |
| uninformative sample IDs absent from `sample-info.*` | `stop_validation_error` | 99 |
| DESeq-suitability failure | `stop_validation_error` | 99 |
| annotation still invalid after retry | `stop_transformation_error` | 99 |
| API outage, auth failure, malformed API response | `stop_unexpected_error` | 255 |
| final study validation | handled by `bin/wrangle.R` | 99 |

## Out of scope

- WGCNA eigengene entities
- strandedness auto-detection from count magnitudes (production writes a
  `strandedness_report.txt`; filenames tell us the strandedness here)
- multi-organism datasets — production keys entities off an organism abbreviation; a user upload is
  a single organism
- fractional counts from RSEM/salmon/kallisto; counts must be integers
- doing anything about poor-quality metadata extraction beyond detecting validation failure

## Key references

| Path | Why |
|---|---|
| `study-dealer-nextflow/bin/wrangleRNASeq.R` | production reference implementation; the tall-entity pattern, stable_ids and `label` handling all come from here |
| `study-wrangler/tmp/lee_gamb/wrangleRNASeq.R` | **stale** earlier variant using wide entities + gene collections; do not follow |
| `expression-shepherd/R/wrangle-rnaseq.R` | also the stale wide variant |
| `dataset-curator/skills/sample-annotations-to-stf/` | JSON schema and the JS converter being ported |
| `dataset-curator/skills/curate-bulk-rnaseq/resources/step-2-analyze-samples.md` | source of the annotation prompt content |
| `study-wrangler/R/Entity-metadata-defaults.R` | authoritative `data_type`/`data_shape` levels and allowed YAML variable fields |
| `study-wrangler/STF_documentation/metadata-fields.md` | **out of date** on `data_type` values |

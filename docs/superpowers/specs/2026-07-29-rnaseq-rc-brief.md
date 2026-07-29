> **SUPERSEDED.** This is the originating brief, kept for provenance.
> The authoritative design is
> [`2026-07-29-rnaseq-rc-design.md`](2026-07-29-rnaseq-rc-design.md).
> This document disagrees with it on three points: it describes separate
> sense and antisense entities, a union of count-file sample IDs, and a
> count-to-sample linkage failure test. The design doc explains why each
> was changed.

# Bulk RNA-seq count wrangling

The task is to create a new 'rnaseq-rc' user dataset type and:

```text
lib/R/wrangle-rnaseq-rc.R
```

with its own comprehensive test suite.

## Inputs

`wrangle()` expects:

* a sense or unstranded counts file
* an antisense counts file, if and only if the first file contains sense counts
* a `sample-info.txt` file containing sample metadata in some form

Counts files contain genes as rows and samples as columns.

When deployed, the user will provide the 2 or 3 files in a zip file and we can expect the VDI system to unpack them into the plugin's working directory. For the test suite we put the 2 or 3 files directly in the test directories (no zip file).

## Core design principle

The count files and their conversion into count entities are handled deterministically.

The only LLM-dependent step is the creation of a correctly formed sample annotation STF. Once that sample entity is valid, all remaining study construction and validation should be deterministic.

Therefore:

* count-file validation failures should fail immediately
* sample-annotation validation failures may trigger an LLM retry
* final study-validation failures should normally fail rather than trigger another LLM call, because they indicate a deterministic processing or linkage error rather than an annotation-generation problem

## Processing flow

### 1. Validate the count files

`wrangle()` first checks that the supplied count files:

* have valid filenames
* have the expected structure
* contain genes as rows and samples as columns
* form a valid sense/antisense or unstranded input combination

It then extracts the sample IDs from each count file and takes their union.

This produces the authoritative set of sample IDs present in the count data.

### 2. Check whether the sample IDs require an explicit mapping

Some sample IDs may already encode useful metadata, for example:

```text
male_3h_rep1
male_3h_rep2
female_6h_rep1
```

In such cases, the IDs do not necessarily need to appear verbatim in `sample-info.txt`.

Other IDs may be opaque codes or serial numbers, for example:

```text
S001
S002
S003
```

For these, `sample-info.txt` must explicitly associate each ID with its metadata.

Unfortunately, whether a set of labels is informative cannot be determined reliably without semantic interpretation.

Use a small, inexpensive LLM call to classify the sample IDs as either:

```text
labels_informative
```

or:

```text
labels_uninformative
```

If the result is `labels_uninformative`, check deterministically that the relevant sample IDs occur in `sample-info.txt`. If they do not, stop with an import error before attempting sample annotation.

### 3. Generate the sample annotation STF

Use a one-shot LLM prompt, similar to the `@veupathdb/dataset-curator/skills/sample-annotations-to-stf` skill (LLM JSON generation and scripted (JS to R port) JSON-to-STF conversion via `@veupathdb/dataset-curator/skills/sample-annotations-to-stf/scripts/sample-annotations-to-stf.js`), to convert:

* the union of sample IDs
* the contents of `sample-info.txt`

into a sample entity STF file. (Actually two sibling files: `entity-sample.tsv` and `entity-sample.yaml`)

The R process then reads and validates the generated STF.

Validation should include the standard sample-entity checks plus an explicit requirement that every sample ID in the generated entity is a member of the authoritative union of sample IDs from the count files.

The generated sample entity must include **all sample IDs from the count files**, and validation must fail if any count-file sample ID is missing from the sample annotation STF.

### 4. Retry invalid sample annotation once

If the generated sample entity fails validation, make one further LLM call.

The retry prompt should repeat the original generation instructions and additionally include:

* the validation error message or messages
* an explicit instruction to correct those errors
* a reminder that sample IDs must come from the supplied authoritative set

If the second result also fails validation, stop with an import error.

### 5. Check suitability for differential-expression analysis

After the sample annotation has validated, perform a DESeq-suitability check.

This should detect annotation structures that are technically valid STF but unsuitable for the intended differential-expression workflow.

If the check fails, stop with an import error.

This check occurs after LLM annotation processing but before the count entities and complete study are constructed.

### 6. Construct the count entities

Re-read the validated count files and convert them into count entities.

Attach each count record to the appropriate sample using a parent-ID column derived from the count-file column headers.

Because the count files have already been validated and the sample entity has been checked against their sample-ID set, this linkage should be deterministic.

### 7. Construct and validate the study

Return a study object containing:

* the sample entity
* the sense and antisense count entities, or the unstranded count entity

Validate the complete study.

Study validation will check parent/child ID consistency through the entity-table joins and therefore validates the count-to-sample linkage.

A failure at this stage should be treated as a deterministic import or implementation error. It should not normally trigger another LLM attempt.

## Test coverage

The test suite should cover `sample-info.txt` inputs in the following forms:

* horizontal TSV
* horizontal CSV
* vertical TSV
* vertical CSV
* free text describing the samples
* article methods text

Tests should also cover:

* unstranded counts
* paired sense and antisense counts
* invalid count filenames
* malformed count files
* inconsistent sample columns between count files
* informative sample IDs not repeated in `sample-info.txt`
* opaque sample IDs correctly mapped in `sample-info.txt`
* opaque sample IDs missing from `sample-info.txt`
* an initially invalid sample STF corrected by the retry
* an invalid sample STF that remains invalid after the retry
* generated sample IDs not present in the count files
* failure of the DESeq-suitability check
* count-to-sample linkage failures during final study validation

## LLM test policy

Tests that make real LLM calls cost money and should therefore be opt-in.

The normal test suite should use mocked or recorded LLM responses to exercise:

* informative-label classification
* uninformative-label classification
* successful first-shot annotation
* successful correction after validation feedback
* repeated annotation failure

A separate opt-in integration test group may exercise the real models and prompts.

The current test harness `tests/testthat/test_examples.R` is not designed to run mock LLM calls, but I'm sure we can come up with an elegant solution. See the `assert.R` custom assertion approach as a possible option. Maybe we can drop the relevant override files into each test directory, and not make too much of an impact on `test_examples.R`?

# Dev environment and other implementation notes

Environment variable CLAUDE_API_KEY is available via the `.env` file.

Use Sonnet 5 (`claude-sonnet-5`) for the main API calls and Haiku 4.5 (`claude-haiku-4-5-20251001`) for the quick check on sample ID informativeness.

Since we don't need any advanced LLM API call features (other than structured JSON response), we should probably code a small wrapper around the Anthropic/Claude REST API rather than import new dependencies. Do you agree?

The Docker image `veupathdb/vdi-plugin-wrangler` has been built (`make build`) and all 74 current tests pass (`make test`). See the Dockerfile and docker compose files for more details.

The `study-wrangler` source code is added as a working directory but there should be no need to modify it.

The `dataset-curator` sources are also available for reference to RNAseq data processing skills.

Note that in production all study-wrangler R code will be repo-based. The plugin must not use LLM API calls to create and run wrangler R code. When running the plugin will use LLM API calls to generate sample annotation JSON only.

There is one wrinkle here, actually. When I've watched the `curate-bulk-rnaseq` skills in action in Claude Code I've noticed that for large datasets with, say, more than 30 samples, the Claude-based agent decides correctly to script the annotation file generation, rather than risk making mistakes using deep context. We can't do that here. We want the API calls to be simple messages only - no tool calls and their associated security risks. So I think the answer for now is to return additional warning messaging along the lines of "This dataset contains a lot of samples (N) which can challenge our AI-based processing" if the sample entity validation fails. We can't do anything about poor quality metadata extraction, we can only detect validation failures.


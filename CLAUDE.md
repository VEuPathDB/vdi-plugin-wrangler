# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a VDI (VEuPathDB Dataset Installer) plugin that uses the [Study Wrangler](https://github.com/VEuPathDB/study-wrangler) R package to process user-uploaded files into EDA-loadable assets. The plugin validates, transforms, and exports study data based on different data types (e.g., phenotype, stf).

## Development Environment

### Docker-based Development

Development is done entirely within Docker containers:

```bash
# Build the container (takes ~45 minutes)
make build

# Get a shell inside the container
make shell

# Run something inside the container
docker compose run --rm -w /opt/veupathdb bin/run_tests.R
```

The working directory inside the container is `/opt/veupathdb`.

### Build Time Notes

The build is slow (~45 min) and dominated by the `remotes::install_github('VEuPathDB/study-wrangler', ...)` step (~42 min). This step compiles many R packages from CRAN source because the `study.wrangler` → `plot.data` → `veupathUtils` dependency chain requires newer versions than Ubuntu 24.04's apt packages ship.

We pre-install R packages via apt (`r-cran-*`) to provide pre-compiled binaries, but most of them get upgraded to newer CRAN versions during the `install_github` step anyway. The heaviest compilation culprits are `igraph`, `RcppEigen`, `RcppArmadillo`, and `fs`. If build time becomes critical, the next lever would be a more up-to-date R base image (e.g. `rocker/r-ver`) rather than Ubuntu's apt packages.

`devtools` was removed from the build — it was being installed unnecessarily. `remotes` (which is all that was needed for `install_github`) is installed from CRAN rather than apt because the apt version is too old to handle the `huge=url` remote type used by `veupathUtils`.

### Volume Mounting for Development

A `docker-compose.override.yml` file is used to mount local directories into the container so code changes are reflected without rebuilding:

```yaml
services:
  plugin:
    volumes:
      - ./bin:/opt/veupathdb/bin
      - ./lib/R:/opt/veupathdb/lib/R
      - ./tests:/opt/veupathdb/tests
```

### Test Directory Permissions

To avoid permission issues with container-created files:

```bash
chmod -R g+s tests
```

## Architecture

### Plugin Entry Points

The plugin implements the VDI plugin interface with these key scripts:

- **`bin/import`** - Main entry point for the import process. Validates directories and calls `bin/wrangle.R`
- **`bin/wrangle.R`** - Core orchestrator that:
  1. Reads `vdi-meta.json` to determine the data type
  2. Loads the appropriate datatype-specific wrangler script (`lib/R/wrangle-<datatype>.R`)
  3. Executes the `wrangle()` function
  4. Validates and exports the resulting study object to VDI format

### Datatype-based Wrangling System

The system is extensible via datatype-specific wrangler scripts:

- Each datatype has its own wrangler in `lib/R/wrangle-<datatype>.R`
- Each wrangler must export a `wrangle(input_dir)` function that returns a study object
- The datatype is determined from `vdi-meta.json` in the input directory (defaults to "phenotype")
- Available datatypes: `phenotype`, `stf`, `isasimple`, `rnaseq-rc`

**Phenotype Wrangler** (`lib/R/wrangle-phenotype.R`):
- Expects exactly one `.txt` or `.tsv` file
- First column must be `geneID` (no duplicates allowed)
- Must have at least one numeric column
- Creates a `gene` variable column (copy of `geneID`) with stable_id `VEUPATHDB_GENE_ID`
- Demotes extra ID columns to regular variables

**STF Wrangler** (`lib/R/wrangle-stf.R`):
- Simple wrapper around `study_from_stf(input_dir)` from the study.wrangler package

**rnaseq-rc Wrangler** (`lib/R/wrangle-rnaseq-rc.R`):
- Bulk RNA-seq counts (a `sense-counts`/`antisense-counts` pair, or a single `unstranded-counts`
  file) plus a free-form `sample-info` file. Builds a `sample` root entity (via an LLM-assisted
  annotation step) and a tall `HTSeq counts` child entity from the deterministically-parsed counts.
  See `doc/rnaseq-rc.md` for the user-facing format contract.
- The orchestrator (`wrangle-rnaseq-rc.R`) sources its own sibling modules via
  `this.path::this.dir()` (see below), since `bin/wrangle.R` only sources
  `lib/R/wrangle-<datatype>.R` itself. It sequences the modules below and owns the error taxonomy;
  it must not reimplement anything from them.
  - `lib/R/llm_client.R` - generic Claude Messages API transport (`llm_text()`/`llm_json()`), plus
    the test mock registry (see `llm-mocks.json` below). No domain knowledge of RNA-seq.
  - `lib/R/counts_files.R` - deterministic count-file discovery, filename/shape/value validation,
    and sense/antisense merge. No awareness of the LLM step.
  - `lib/R/sample_annotation.R` - the one LLM-dependent step: classifies sample IDs as
    informative/uninformative, generates the sample annotation JSON (with one retry on validation
    failure), and runs the DESeq-suitability check.
  - `lib/R/annotations_to_stf.R` - R port of `dataset-curator`'s
    `sample-annotations-to-stf.js`; converts the parsed annotation JSON into an
    `entity-sample.tsv`/`entity-sample.yaml` STF pair for `entity_from_stf()` to read back.
- **`llm-mocks.json` test convention**: a test directory may include an `llm-mocks.json` file with
  FIFO response queues keyed by call_name (`classify_labels`, `annotate`). `llm_mocks_init()` only
  loads it when the environment variable `WRANGLER_ALLOW_LLM_MOCKS` is exactly `"1"` **and** the
  file exists, so an uploaded `llm-mocks.json` can never divert a production run — mocks are only
  ever consulted when a test has explicitly opted in. `tests/testthat/test_examples.R` sets
  `WRANGLER_ALLOW_LLM_MOCKS=1` for the whole suite.
- **`-live` directory convention**: any top-level datatype directory under `tests/testthat/`
  suffixed `-live` (e.g. `rnaseq-rc-live/`) makes real, billable Claude API calls instead of using
  mocks, and is skipped by `test_examples.R` unless `WRANGLER_LLM_LIVE=1` is set. Do not run this
  path casually — it costs real money.

### Dependencies

Key R packages (installed in Dockerfile):
- `tidyverse` - Data manipulation
- `study.wrangler` - Core VEuPathDB study wrangling functionality
- `veupathUtils` - VEuPathDB utilities
- `plot.data` - Provides `binWidth` function and data visualization
- `this.path` - Lets `lib/R/wrangle-rnaseq-rc.R` resolve its sibling `source()` calls via
  `this.path::this.dir()`, independent of the caller's working directory

Key Perl modules:
- `VdiStudyHandlerCommon.pm` - Common VDI plugin functionality - comes from https://github.com/VEuPathDB/vdi-lib-plugin-study at container build time.

## Testing

### Running Tests

Inside the container:

```bash
cd /opt/veupathdb
bin/run_tests.R
```

Tests use `testthat` and run against example data in `tests/testthat/<datatype>/<test-name>/`.

### Test Structure

Tests are organized by datatype in `tests/testthat/`:
- `tests/testthat/<datatype>/<numbered-test-name>/`
- Each test directory contains input files and optional `vdi-meta.json`
- `vdi-meta.json` can specify:
  - `"test_expectation": "fail"` - Test expects wrangling to fail
  - `"test_expectation": "pass"` - Test expects success (default)
  - `"type": {"name": "<name>", "version": "<version>"}` - Override datatype for testing (object with name and optional version)

**Important**: Tests only verify that import completes or fails as expected - they do NOT validate output correctness.

For cases where it's worth pinning a non-obvious invariant about the resulting study object or its exported cache files, an optional `assert.R` file can be provided in a test directory. `test_examples.R` sources it and calls `assert(study, output_dir)` after a successful export.

```r
# Example: tests/testthat/isasimple/09-iso8859-OK/assert.R
assert <- function(study, output_dir) {
  cache_files <- list.files(output_dir, pattern = "attributevalue.*\\.cache$", full.names = TRUE)
  stopifnot("No attributevalue cache found" = length(cache_files) > 0)
  all_text <- paste(
    sapply(cache_files, function(f) paste(readLines(f, encoding = "UTF-8", warn = FALSE), collapse = "\n")),
    collapse = "\n"
  )
  expect_true(grepl("ü", all_text, fixed = TRUE), label = "ü preserved in cache")
}
```

**Current count**: 280 passing tests (including assert.R assertions for encoding and for rnaseq-rc entity shape/stable_id checks).

### Adding a New Datatype

1. Create test directories: `tests/testthat/<datatype>/<test-number-description>/`
2. Add input files (keep them small for fast testing)
3. Create wrangler script: `lib/R/wrangle-<datatype>.R` with a `wrangle(input_dir)` function
4. The `wrangle()` function must:
   - Find and process input files
   - Create entities using study.wrangler functions
   - Optionally call `stop_if_entity_invalid(entity)` before assembling a study object — this surfaces entity-level problems as user-friendly validation errors rather than the generic fallback in `wrangle.R`
   - Return a study object via `study_from_entities(entities = list(...))`
5. Add format documentation in `doc/<datatype>.md` for outreach

## Common Commands

```bash
# Manual import test (inside container)
import /datasets/build-65/inputs/my-dataset /datasets/build-65/outputs/my-dataset

# Run all tests
bin/run_tests.R

# Direct wrangling (inside container)
Rscript bin/wrangle.R <INPUT_DIR> <OUTPUT_DIR>
```

## Exit Codes

Defined in `lib/includes.sh`:
- `99` - Validation error
- `99` - Incompatibility error
- `99` - Transformation error
- `255` - Unexpected error

## Key Files

- `bin/import` - Bash entry point for VDI plugin
- `bin/wrangle.R` - R orchestrator script
- `lib/R/wrangle-*.R` - Datatype-specific wranglers
- `lib/includes.sh` - Bash utilities and exit codes
- `tests/testthat/test_examples.R` - Main test runner
- `Dockerfile` - Container definition with all dependencies

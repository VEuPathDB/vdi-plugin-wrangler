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
- Available datatypes: `phenotype`, `stf`

**Phenotype Wrangler** (`lib/R/wrangle-phenotype.R`):
- Expects exactly one `.txt` or `.tsv` file
- First column must be `geneID` (no duplicates allowed)
- Must have at least one numeric column
- Creates a `gene` variable column (copy of `geneID`) with stable_id `VEUPATHDB_GENE_ID`
- Demotes extra ID columns to regular variables

**STF Wrangler** (`lib/R/wrangle-stf.R`):
- Simple wrapper around `study_from_stf(input_dir)` from the study.wrangler package

### Dependencies

Key R packages (installed in Dockerfile):
- `tidyverse` - Data manipulation
- `study.wrangler` - Core VEuPathDB study wrangling functionality
- `veupathUtils` - VEuPathDB utilities
- `plot.data` - Provides `binWidth` function and data visualization

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

For cases where it's worth pinning a non-obvious invariant about the resulting study object, an optional `assert.R` file could be provided in a test directory. `test_examples.R` would source it and call `assert(study)` after a successful wrangling run. This is not needed for most tests.

```r
# Example: tests/testthat/isasimple/01-basic/assert.R
assert <- function(study) {
  entity <- study %>% get_entities() %>% .[[1]]
  vars <- entity %>% get_variable_metadata() %>% filter(!is.na(display_order))
  expect_equal(vars$display_order, seq_len(nrow(vars)))
}
```

`test_examples.R` would need a small addition after `export_to_vdi`:

```r
assert_path <- file.path(example_dir, "assert.R")
if (file.exists(assert_path)) {
  local({ source(assert_path); assert(study) })
}
```

**Current count**: 48 passing tests.

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

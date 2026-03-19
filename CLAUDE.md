# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a VDI (VEuPathDB Dataset Installer) plugin that uses the [Study Wrangler](https://github.com/VEuPathDB/study-wrangler) R package to process user-uploaded files into EDA-loadable assets. The plugin validates, transforms, and exports study data based on different data types (e.g., phenotype, stf).

## Development Environment

### Docker-based Development

Development is done entirely within Docker containers:

```bash
# Build the container (takes ~30 minutes)
make build

# Get a shell inside the container
make shell

# Run something inside the container
docker compose run --rm -w /opt/veupathdb bin/run_tests.R
```

The working directory inside the container is `/opt/veupathdb`.

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

### Adding a New Datatype

1. Create test directories: `tests/testthat/<datatype>/<test-number-description>/`
2. Add input files (keep them small for fast testing)
3. Create wrangler script: `lib/R/wrangle-<datatype>.R` with a `wrangle(input_dir)` function
4. The `wrangle()` function must:
   - Find and process input files
   - Create entities using study.wrangler functions
   - Validate entities
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

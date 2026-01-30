# vdi-plugin-wrangler

This is a VDI plugin that uses the [Study Wrangler](https://github.com/VEuPathDB/study-wrangler) to process user-uploaded files into EDA-loadable assets.

## Set-up

Copy `example.env` to `.env` and ask colleagues (including Bob and
Ellie) what to provide for these guys:

```
LDAP_SERVER
ORACLE_BASE_DN
```

Nothing else should need changing, for now at least. The database
connections are not yet in use.

### VDI Plugin Server Config

The VDI plugin server requires a configuration file at `/etc/vdi/config.yml` inside the container. A minimal configuration file is provided at `config/local-dev-config.yml` and is automatically mounted by `docker-compose.override.yml`. This config defines the wrangler plugin's data types and basic server settings without requiring the full VDI infrastructure. Note that the OAuth-related env vars are not needed to run this container in isolation.


### `tests` directory permissions

For convenient host-side maintenance of the test data in the `tests`
directory, it's worth doing the following so that when the container
makes files as root user, you can still edit/delete them without going
into the container. You may need to repeat this after a checkout, pull
or merge that creates new subdirectories. Or you can add local git
hooks (`post-checkout` and `post-merge`) to do this automatically.

```
chmod -R g+s tests
```

### `mount` directory

In your .env file you will have something like this:

```
DATASET_INSTALL_ROOT=/datasets
SITE_BUILD=build-65
```

When using the docker compose file, `./mount` is "mounted" as `/datasets` in the container.

You should create a directory `mount/build-65` before attempting to build the container.


### build

```
# can take 30 minutes!
make build

# start the container (running a VDI server but you may not need to use it)
make start

# get a shell 
make shell

# not essential, but this is the "home directory"
cd /opt/veupathdb

# test import with data from outside the container
import /datasets/build-65/inputs/my-cool-dataset /datasets/build-65/outputs/my-cool-dataset
```

## Developing with the container

A `docker-compose.override.yml` file is provided with the following volume mounts:

```
services:
  plugin:
    volumes:
      - ./bin:/opt/veupathdb/bin  # Mount local bin directory
      - ./lib/R:/opt/veupathdb/lib/R  # Mount local R code
      - ./tests:/opt/veupathdb/tests # and the test data
      - ./config/local-dev-config.yml:/etc/vdi/config.yml  # Mount VDI server config
```

This allows you to work on the code and tests without rebuilding/restarting the container. You can add further volume mounts as required.

## Running the import tests

The easiest way to run tests:

```
make test
```

Or, in the container shell:

```
cd /opt/veupathdb
bin/run_tests.R
```

The tests validate that:
- Wrangling either completes without warnings/errors (if expected to pass) or throws an error (if expected to fail)
- For passing tests, the VDI export creates the expected output files (validates file count and presence of required base files)
- For failing tests with regex patterns in meta.json, both user-facing and technical error messages match expected patterns
- Test timing is reported for performance tracking

## Adding a new datatype of wrangler

Let's call this 'rnaseq'

### Add test cases

Make a directory for the datatype and then a numbered directory for the first test case

```
mkdir tests/testthat/rnaseq
mkdir tests/testthat/rnaseq/01-basic
```

In that directory add whatever input files are needed. **But try to
keep them small.** Large test files will slow down automated testing.

There are currently two types of test data

- expected to load without errors
- expected to fail

If your test data is expected to fail the import stage (for example a
directory with no data files in it) then place a file called
`meta.json` inside the directory with the following contents:

```
{
  "test_expectation": "fail"
}
```

If it is expected to pass, this file is not needed, or you can set the value to `"pass"`.

#### Validating Error Messages

For failing tests, you can (and should) validate that the expected error messages are shown to users. This helps prevent error message regressions. Add optional regex patterns to `meta.json`:

```
{
  "test_expectation": "fail",
  "expected_user_error_regex": "No data file found",
  "expected_technical_error_regex": "No txt/tsv/csv input file found",
  "type": {
    "name": "rnaseq",
    "version": "1.0"
  }
}
```

- `expected_user_error_regex`: Pattern to match the user-friendly error message (sent to STDOUT, shown to users in VDI)
- `expected_technical_error_regex`: Pattern to match the technical error message (sent to STDERR, written to logs)
- `type`: Override the datatype for testing. Must be an object with `name` field (e.g., `{"name": "rnaseq", "version": "1.0"}`) (optional, defaults to the directory name)

These fields are optional, but error message patterns are recommended for failing tests to ensure error messages remain helpful and don't regress.

### Add wrangler script

Create a file called `lib/R/wrangle-rnaseq.R` containing a function
called `wrangle()` that takes an input directory and returns a study. The
study does not need `name` metadata. No need to load the
`study.wrangler` package - `tidyverse` is available too. Error helper
functions are available (loaded by test framework and bin/wrangle.R).

```
wrangle <- function(input_dir) {
  # find input file(s) in `input_dir`
  input_files <- Sys.glob(paste0(input_dir, "/*.fastq"))

  if (length(input_files) == 0) {
    stop_validation_error(
      user_msg = "No FASTQ files found in your upload.",
      technical_msg = paste("No .fastq files found in:", input_dir),
      file = input_dir
    )
  }

  # create entity(ies)
  entity <- entity_from_file(input_files[1], name = "rnaseq")

  # perform extra checks for edge cases
  # and make modifications on the entity as needed
  # ...

  # validate
  if (entity %>% validate() == FALSE) {
    stop_transformation_error(
      user_msg = "Data validation failed after processing. Please check that your data file is properly formatted.",
      technical_msg = "Entity validation failed after transformation."
    )
  }

  return(study_from_entities(entities = list(entity)))
}
```

#### Error Helper Functions

Use these functions instead of `stop()` to provide better error messages to users:

- `stop_validation_error(user_msg, technical_msg, file)` - For invalid input data (exit code 1)
- `stop_transformation_error(user_msg, technical_msg, file)` - For processing failures (exit code 1)
- `stop_incompatible_error(user_msg, technical_msg, file)` - For unsupported datatypes (exit code 2)
- `stop_unexpected_error(user_msg, technical_msg, file)` - For internal errors (exit code 255)

Each function:
- Writes `user_msg` to STDOUT (shown to users in VDI)
- Writes `technical_msg` to STDERR (logged for debugging)
- Returns appropriate exit code to the system
- Optional `file` parameter adds file path to technical logs

### Add documentation

This should be enough information for outreach to make user-facing documentation for the upload form.

e.g. see [the format documentation for phenotype](./doc/phenotype.md)


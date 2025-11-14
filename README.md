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

The VDI plugin server requires a configuration file at `/etc/vdi/config.yml` inside the container. A minimal configuration file is provided at `config/local-dev-config.yml` and is automatically mounted by `docker-compose.override.yml`. This config defines the wrangler plugin's data types and basic server settings without requiring the full VDI infrastructure.


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
- Test timing is reported for performance tracking

## Adding a new category of wrangler

Let's call this 'rnaseq'

### Add test cases

Make a directory for the category and then a numbered directory for the first test case

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

### Add wrangler script

Create a file called `lib/R/wrangle-rnaseq.R` containing a function
called `wrangle()` that takes an input directory returns a study. The
study does not need `name` metadata. No need to load the
`study.wrangler` package - `tidyverse` is available too.

```
wrangle <- function(input_dir) {
  # find input file(s) in `input_dir`
  # ...

  # create entity(ies)
  entity <- entity_from_file(input_file, name = "phenotype")

  # perform extra checks for edge cases
  # and make modifications on the entity as needed
  # ...

  # validate
  if (entity %>% validate() == FALSE) {
    stop("wrangle-rnaseq.R ERROR: entity does not validate.")
  }

  return(study_from_entities(entities = list(entity)))
}
```

### Add documentation

This should be enough information for outreach to make user-facing documentation for the upload form.

e.g. see [the format documentation for phenotype](./doc/phenotype.md)


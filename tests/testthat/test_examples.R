# `suppressWarnings()` needed due to
# https://github.com/VEuPathDB/plot.data/issues/266
# We can remove it when that is fixed.

# `suppressPackageStartupMessages()` is needed because the blanket
# tidyverse import involves quite a few name clashes (that don't concern us)

suppressWarnings({
  suppressPackageStartupMessages({
    library(tidyverse)
    library(study.wrangler)
  })
})

### PREAMBLE ###

# Get the original working directory
original_wd <- Sys.getenv("ORIGINAL_WD")

if (!dir.exists(original_wd) || original_wd == "") {
  skip(glue::glue("Skipping all tests: ORIGINAL_WD ('{original_wd}') is not set or invalid."))
}

# Load error helpers (needed by all wrangler scripts)
source(file.path(original_wd, "lib/R/error_helpers.R"))

# Configure validation to use both baseline and EDA profiles
set_config(validation.profiles = c("baseline", "eda"))

expect_clean <- function(code) {
  testthat::expect_no_error({
    testthat::expect_no_warning({
      code
    })
  })
}

### TEST ALL THE DIFFERENT DATATYPES (WRANGLER SCENARIOS) ###

# Store test timings
test_timings <- list()

datatypes <- list.dirs(recursive = FALSE, full.names = FALSE)

for (datatype in datatypes) {
  examples <- list.dirs(datatype, recursive = FALSE, full.names = FALSE)

  # This sets the context in the testthat output, so we get pass/fail counts
  # per datatype. The function is deprecated but let's use it while we can.
  testthat::context(datatype)

  for (example in examples) {
    test_that(glue::glue("Example '{datatype}/{example}' loads or fails as appropriate"), {

      example_dir <- file.path(datatype, example)

      # Most tests we expect to complete without errors
      # however, you can set `"test_expectation": "fail"` in the
      # meta.json file within the test data directory if you like

      test_expectation <- 'pass'
      expected_technical_error_regex <- NULL
      expected_user_error_regex <- NULL

      meta_json_path <- file.path(example_dir, 'meta.json')

      if (file.exists(meta_json_path)) {
        metadata <- jsonlite::read_json(meta_json_path)
        if (!is.null(metadata$test_expectation)) {
          test_expectation <- metadata$test_expectation
        }
        # optionally read expected error patterns for failing tests
        if (!is.null(metadata$expected_technical_error_regex)) {
          expected_technical_error_regex <- metadata$expected_technical_error_regex
        }
        if (!is.null(metadata$expected_user_error_regex)) {
          expected_user_error_regex <- metadata$expected_user_error_regex
        }
        # it's also possible to override the datatype
        if (!is.null(metadata$type) && !is.null(metadata$type$name)) {
          datatype <- metadata$type$name
        }
      }

      valid_expectations <- c("pass", "fail")
      if (!(test_expectation %in% valid_expectations)) {
        stop(glue::glue("Invalid test expectation '{test_expectation}'. Expected one of: {paste(valid_expectations, collapse=', ')}"))
      }

      # Determine appropriate path to the script with the appropriate `wrangle()` function
      script_path <- file.path(original_wd, "lib/R", paste0("wrangle-", datatype, ".R"))

      if (!file.exists(script_path)) {
        skip(glue::glue("Skipping example '{example}': Bad datatype/missing script '{script_path}'"))
        return() # from `test_that()` scope
      }

      # local scope for dynamic `wrangle()` function
      local({
        # Load the appropriate `wrangle` function dynamically
        source(script_path)
  
        # Ensure `wrangle()` is defined after sourcing
        if (!exists("wrangle", mode = "function")) {
          skip(glue::glue("No `wrangle` function in '{script_path}'"))
          return()
        }
  
        # Determine study name as either $VDI_IMPORT_ID or the input directory path
        study_name <- Sys.getenv("VDI_IMPORT_ID", unset = example_dir)

        expect_function <- if (test_expectation == 'pass') {
          expect_clean
        } else {
          # For failing tests, capture STDOUT and validate both user and technical messages
          function(code) {
            # Capture STDOUT (user message)
            stdout_output <- capture.output(
              # Expect error for technical message (STDERR)
              if (!is.null(expected_technical_error_regex)) {
                expect_error(code, regexp = expected_technical_error_regex)
              } else {
                expect_error(code)
              }
            )

            # Validate STDOUT contains user error message if pattern provided
            if (!is.null(expected_user_error_regex)) {
              stdout_text <- paste(stdout_output, collapse = "\n")
              expect_match(stdout_text, expected_user_error_regex,
                           info = paste0("User error message not found in STDOUT: ", stdout_text))
            }
          }
        }

        # Time the test execution
        test_time <- system.time({
          expect_function({
            study <- wrangle(example_dir) %>% set_study_name(study_name)
            if (study %>% validate()) {
              tmp_dir <- tempfile("temp_output_")
              dir.create(tmp_dir)
              withr::defer(unlink(tmp_dir, recursive = TRUE))  # Ensure cleanup
              study %>% export_to_vdi(tmp_dir)

              # Validate output files (only for passing tests)
              if (test_expectation == 'pass') {
                # Get number of entities in the study
                num_entities <- study %>% get_entities() %>% length()

                # Count output files
                output_files <- list.files(tmp_dir, full.names = FALSE)

                # Calculate minimum expected files
                # Base files: install.json, study.cache, entitytypegraph.cache (3 files)
                # Per-entity files: ancestors, attributegraph, attributevalue (3 files per entity)
                # Note: Actual count may be higher if entities have collections (+2 per entity with collections)
                base_file_count <- 3
                per_entity_files <- 3
                min_expected_files <- base_file_count + (per_entity_files * num_entities)

                # Validate file count
                if (length(output_files) < min_expected_files) {
                  stop(glue::glue(
                    "VDI export validation failed for '{datatype}/{example}': ",
                    "Expected at least {min_expected_files} files ",
                    "({base_file_count} base + {per_entity_files} per entity × {num_entities} entities), ",
                    "but found {length(output_files)}"
                  ))
                }

                # Validate required base files exist
                required_base_files <- c("install.json", "study.cache", "entitytypegraph.cache")
                missing_files <- setdiff(required_base_files, output_files)
                if (length(missing_files) > 0) {
                  stop(glue::glue(
                    "VDI export validation failed for '{datatype}/{example}': ",
                    "Missing required base files: {paste(missing_files, collapse=', ')}"
                  ))
                }
              }
            } else {
              stop(glue::glue("Validation of study failed for '{datatype}/{example}'"))
            }
          })
        })

        # Store timing for this test
        test_key <- glue::glue("{datatype}/{example}")
        test_timings[[test_key]] <<- test_time["elapsed"]
      })
    })
  }
}

# Report timings after all tests complete and testthat has finished its output
withr::defer({
  cat("\n")
  cat("════════════════════════════════════════════════════════════════════════════\n")
  cat("Test Timings\n")
  cat("════════════════════════════════════════════════════════════════════════════\n")

  # Sort by elapsed time (descending)
  sorted_timings <- test_timings[order(unlist(test_timings), decreasing = TRUE)]

  for (test_name in names(sorted_timings)) {
    elapsed <- sorted_timings[[test_name]]
    cat(sprintf("  %-50s %6.2fs\n", test_name, elapsed))
  }

  cat("════════════════════════════════════════════════════════════════════════════\n")
}, envir = globalenv())

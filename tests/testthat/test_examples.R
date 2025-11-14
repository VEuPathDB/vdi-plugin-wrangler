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


expect_clean <- function(code) {
  testthat::expect_no_error({
    testthat::expect_no_warning({
      code
    })
  })
}

### TEST ALL THE DIFFERENT CATEGORIES (WRANGLER SCENARIOS) ###

# Store test timings
test_timings <- list()

categories <- list.dirs(recursive = FALSE, full.names = FALSE)

for (category in categories) {
  examples <- list.dirs(category, recursive = FALSE, full.names = FALSE)

  # This sets the context in the testthat output, so we get pass/fail counts
  # per category. The function is deprecated but let's use it while we can.
  testthat::context(category)

  for (example in examples) {
    test_that(glue::glue("Example '{category}/{example}' loads or fails as appropriate"), {

      example_dir <- file.path(category, example)

      # Most tests we expect to complete without errors
      # however, you can set `"test_expectation": "fail"` in the
      # meta.json file within the test data directory if you like

      test_expectation <- 'pass'
     
      meta_json_path <- file.path(example_dir, 'meta.json')

      if (file.exists(meta_json_path)) {
        metadata <- jsonlite::read_json(meta_json_path)
        if (!is.null(metadata$test_expectation)) {
          test_expectation <- metadata$test_expectation
        }
        # it's also possible to override the category
        if (!is.null(metadata$category)) {
          category <- metadata$category
        }
      }

      valid_expectations <- c("pass", "fail")
      if (!(test_expectation %in% valid_expectations)) {
        stop(glue::glue("Invalid test expectation '{test_expectation}'. Expected one of: {paste(valid_expectations, collapse=', ')}"))
      }

      # Determine appropriate path to the script with the appropriate `wrangle()` function
      script_path <- file.path(original_wd, "lib/R", paste0("wrangle-", category, ".R"))

      if (!file.exists(script_path)) {
        skip(glue::glue("Skipping example '{example}': Bad category/missing script '{script_path}'"))
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
        
        expect_function <- if (test_expectation == 'pass')
	  expect_clean
	else
	  expect_error

        # Time the test execution
        test_time <- system.time({
          expect_function({
            study <- wrangle(example_dir) %>% set_study_name(study_name)
            if (study %>% validate()) {
              tmp_dir <- tempfile("temp_output_")
              dir.create(tmp_dir)
              withr::defer(unlink(tmp_dir, recursive = TRUE))  # Ensure cleanup
              study %>% export_to_vdi(tmp_dir)
            } else {
              stop(glue::glue("Validation of study failed for '{category}/{example}'"))
            }
          })
        })

        # Store timing for this test
        test_key <- glue::glue("{category}/{example}")
        test_timings[[test_key]] <<- test_time["elapsed"]
      })
    })
  }
}

# Report timings after all tests complete
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

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

### TEST ALL THE DIFFERENT CATEGORIES (WRANGLER SCENARIOS) ###

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

      # Now we repeat some of the code in `bin/wrangle.R`
      script_path <- file.path(original_wd, "lib/R", paste0("wrangle-", category, ".R"))

      if (!file.exists(script_path)) {
        skip(glue::glue("Skipping example '{example}': Bad category/missing script '{script_path}'"))
        return() # from `test_that()` scope
      }

      # We're about to load a `wrangle()` function from source code.
      # If necessary, delete any existing function of that name.
      if (exists("wrangle", mode = "function", envir = .GlobalEnv)) {
        rm(wrangle, envir = .GlobalEnv)
      }

      # Load the appropriate `wrangle` function dynamically
      source(script_path)

      # Ensure `wrangle()` is defined after sourcing
      if (!exists("wrangle", mode = "function")) {
        skip(glue::glue("No `wrangle` function in '{script_path}'"))
        return()
      }

      ## The next few lines are modified from `bin/wrangle.R` ##
      
      # Determine study name as either $VDI_IMPORT_ID or the input directory path
      study_name <- Sys.getenv("VDI_IMPORT_ID", unset = example_dir)
      
      # Tell testthat to accept 'pass' (no errors) or 'fail' (expect an error)
      expect_function <- if (test_expectation == 'pass') expect_no_error else expect_error

      expect_function({
        study <- wrangle(example_dir) %>% set_study_name(study_name)
        if (study %>% validate()) {
          tmp_dir <- tempfile("temp_output_")
          dir.create(tmp_dir)
          study %>% export_to_vdi(tmp_dir)
        } else {
          stop(glue::glue("Validation of study failed for '{category}/{example}'"))
        }
      })
    })
  }
}

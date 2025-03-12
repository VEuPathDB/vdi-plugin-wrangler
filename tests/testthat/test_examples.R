### PREAMBLE ###

# get the original working directory
original_wd <- Sys.getenv("ORIGINAL_WD")

if (!dir.exists(original_wd) || original_wd == "") {
  skip(glue::glue("Skipping all tests: ORIGINAL_WD ('{original_wd}') is not set or invalid."))
}

### TEST ALL THE DIFFERENT CATEGORIES (WRANGLER SCENARIOS) ###

categories <- list.dirs(recursive = FALSE, full.names = FALSE)

for (category in categories) {
  test_that(glue::glue("All examples in category '{category}' load or fail as appropriate"), {

    examples <- list.dirs(category, recursive = FALSE, full.names = FALSE)

    for (example in examples) {
      example_dir <- file.path(category, example)

# TO DO REMOVE THIS TEST
#      # expect at least one file (this could be the `meta.json` file)
#      some_files <- list.files(example_dir)
#      expect_true(length(some_files) > 0)

      # most tests we expect to complete without errors
      # however, you can set `"test_expectation": "fail"` in the
      # meta.json file within the test data directory if you like

      # local scope because we might redefine `category` for this iteration only
      local({
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

        # now we repeat some of the code in `bin/wrangle.R`
        script_path <- file.path(original_wd, "lib/R", paste0("wrangle-", category, ".R"))

        if (!file.exists(script_path)) {
          skip(glue::glue("Skipping example '{example}': Bad category/missing script '{script_path}'"))
	  return() # exit `local()` scope
        }

	# Load the appropriate `wrangle` function dynamically (into new/empty local scope)
        source(script_path)

        # Ensure `wrangle()` is defined after sourcing
        if (!exists("wrangle", mode = "function")) {
          skip(glue::glue("No `wrangle` function in '{script_path}'"))
	  return()
        }

        ## the next few lines are modified from `bin/wrangle.R`
	
        # determine study name as either $VDI_IMPORT_ID or the input directory path
        study_name <- Sys.getenv("VDI_IMPORT_ID", unset = example_dir)
        
        # tell testthat to accept 'pass' (no errors) or 'fail' (expect an error)
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


  })
}

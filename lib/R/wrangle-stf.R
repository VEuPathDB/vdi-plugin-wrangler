#'
#' wrangle(input_dir)
#'
#' @return a study object
#'
#' Expects STF-format TSV files and optional STF YAML metadata
#'
wrangle <- function(input_dir) {
  check_stf_files_are_utf8(input_dir)

  study <- tryCatch(
    study_from_stf(input_dir, validate = FALSE) %>%
      map_entities(~ .x %>% set_variable_display_names_from_provider_labels()),
    error = function(e) {
      stop_validation_error(
        user_msg = "Your STF upload could not be parsed. Please check that the entity TSV and YAML files are correctly formatted.",
        technical_msg = conditionMessage(e),
        file = input_dir
      )
    }
  )

  return(study)
}

#' check_stf_files_are_utf8
#'
#' STF input is produced by trusted internal tooling and is expected to
#' always be UTF-8. Unlike the user-upload wranglers (which sniff encoding
#' via `detect_file_encoding()` and read accordingly, see
#' `entity_from_file.R` in study.wrangler), `study_from_stf()` reads with a
#' plain UTF-8 locale -- a non-UTF-8 file would silently decode as mojibake
#' rather than error. Check the precondition explicitly instead.
check_stf_files_are_utf8 <- function(input_dir) {
  globs <- paste0(input_dir, "/*", c(".tsv", ".yaml", ".yml"))
  files <- Sys.glob(globs)

  non_utf8_files <- files[vapply(files, function(f) detect_file_encoding(f) != "UTF-8", logical(1))]

  if (length(non_utf8_files) > 0) {
    stop_validation_error(
      user_msg = paste0(
        "Your upload contains file(s) that are not valid UTF-8: ",
        paste(basename(non_utf8_files), collapse = ", "),
        ". STF uploads must be UTF-8 encoded."
      ),
      technical_msg = paste0(
        "Non-UTF-8 STF file(s) detected: ",
        paste(non_utf8_files, collapse = ", ")
      ),
      file = input_dir
    )
  }
}

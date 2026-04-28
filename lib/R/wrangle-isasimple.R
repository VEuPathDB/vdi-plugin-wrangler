#'
#' wrangle(input_dir)
#'
#' @return a study object
#'
#' Expects only one *.txt, *.tsv, or *.csv file in input directory (case-insensitive).
#' Generates a serial entity ID column and treats all user-supplied columns as variables.
#'

wrangle <- function(input_dir) {
  # check for one input file only
  globs <- paste0(input_dir, "/*", c(".txt", ".tsv", ".csv", ".TXT", ".TSV", ".CSV"))
  input_files <- Sys.glob(globs)

  if (length(input_files) > 1) {
    stop_validation_error(
      user_msg = "Your upload contains more than one data file. Please upload exactly one .txt, .tsv, or .csv file.",
      technical_msg = "Too many txt/tsv/csv input files found in input directory."
    )
  }
  if (length(input_files) == 0) {
    stop_validation_error(
      user_msg = "No data file found in your upload. Please include exactly one .txt, .tsv, or .csv file.",
      technical_msg = paste("No txt/tsv/csv input file found in:", input_dir),
      file = input_dir
    )
  }

  input_file <- input_files[1]

  # Add serial ID column before type inference so entity_from_file detects it as the entity ID.
  # provider_label for each column is set automatically to the column name by sync_variable_metadata.
  entity <- tryCatch(
    entity_from_file(
      input_file,
      name = "record",
      preprocess_fn = function(data) {
        data %>% mutate(entity_id = sprintf("entity%06d", seq_len(nrow(data))), .before = 1)
      }
    ),
    error = function(e) {
      stop_validation_error(
        user_msg = "Your data file could not be parsed. Please check that it is a valid TSV or CSV file where every row has the same number of columns as the header (use empty values rather than omitting them).",
        technical_msg = conditionMessage(e),
        file = input_file
      )
    }
  )

  # Redetect all user-supplied columns as variables (not IDs), leaving entity_id as the ID.
  user_columns <- setdiff(names(entity@data), "entity_id")
  entity <- entity %>% redetect_columns_as_variables(user_columns)

  # Preserve input column order in the visualization system
  for (i in seq_along(user_columns)) {
    entity <- entity %>% set_variable_metadata(user_columns[[i]], display_order = i)
  }

  # Infer lat/lng variable metadata for EDA
  entity <- entity %>% infer_geo_variables_for_eda()

  # Set display names from provider labels (original column names)
  entity <- entity %>% set_variable_display_names_from_provider_labels()

  stop_if_entity_invalid(entity)

  return(study_from_entities(entities = list(entity)))
}

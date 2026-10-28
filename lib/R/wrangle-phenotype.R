#'
#' wrangle(input_dir)
#'
#' @return a study object
#'
#' Expects only one *.txt, *.tsv, or *.csv file in input directory (case-insensitive)
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

  # The user's first column must be 'gene'. We opaquely prepend a copy called 'geneID__'
  # before type inference so that entity_from_file detects it as the entity ID, and the
  # user-facing 'gene' column becomes a regular variable (see below).
  user_column_names <- NULL
  entity <- tryCatch(
    entity_from_file(
      input_file,
      name = "phenotype",
      display_name = "Phenotype",
      display_name_plural = "Phenotypes",
      preprocess_fn = function(data) {
        user_column_names <<- names(data)
        if (length(user_column_names) == 0 || user_column_names[1] != "gene") {
          return(data) # reported below, outside this tryCatch
        }
        if ("geneID__" %in% user_column_names) {
          return(data) # reported below, outside this tryCatch
        }
        data %>% mutate(`geneID__` = gene, .before = 1)
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

  if (length(user_column_names) == 0 || user_column_names[1] != "gene") {
    stop_validation_error(
      user_msg = "Your data file must have a column named 'gene' (case-sensitive) as the first column.",
      technical_msg = paste("'gene' column not present or misnamed in:", input_file),
      file = input_file
    )
  }
  if ("geneID__" %in% user_column_names) {
    stop_validation_error(
      user_msg = "Your data file contains a column named 'geneID__', which is a reserved name. Please remove or rename it.",
      technical_msg = paste("Reserved column name 'geneID__' found in:", input_file),
      file = input_file
    )
  }

  gene_values <- entity %>% get_data() %>% pull(gene)
  if (any(is.na(gene_values) | gene_values == "")) {
    stop_validation_error(
      user_msg = "The 'gene' column in your data file contains empty values. Every row must have a gene ID.",
      technical_msg = paste("Empty values in 'gene' column in:", input_file),
      file = input_file
    )
  }
  if (anyDuplicated(gene_values) > 0) {
    stop_validation_error(
      user_msg = "The 'gene' column in your data file contains duplicate values. Each row must have a unique gene ID (if you have more than one phenotype value, use multiple columns for these).",
      technical_msg = paste("Duplicate values in 'gene' column in:", input_file),
      file = input_file
    )
  }

  # all user-supplied columns (including 'gene') are regular variables; 'geneID__' stays as the ID
  entity <- entity %>% redetect_columns_as_variables(user_column_names)

  # give the 'gene' column the stable_id that has been used elsewhere for phenotype datasets
  # e.g. in ApiCommonModel/Model/lib/wdk/model/records/geneTableQueries.xml
  entity <- entity %>% set_variable_metadata('gene', display_name = 'Gene ID', stable_id = 'VEUPATHDB_GENE_ID')

  # set default display names for any other variables that need it
  entity <- entity %>% set_variable_display_names_from_provider_labels()

  # check there's a number variable
  number_variables <- entity %>%
    get_variable_metadata() %>%
    filter(data_type %in% c('number', 'integer'))
  if (nrow(number_variables) == 0) {
    stop_validation_error(
      user_msg = "Your data file must contain at least one numeric column (in addition to the gene column).",
      technical_msg = paste("No numeric column found in:", input_file),
      file = input_file
    )
  }

  # must do this in case we have lat/long variables
  # (because we are validating with the EDA profile)
  entity <- entity %>% infer_geo_variables_for_eda()

  stop_if_entity_invalid(entity)

  return(study_from_entities(entities = list(entity)))
}

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
  entity <- entity_from_file(input_file, name = "phenotype")

  # see how many ID columns were detected
  id_column_metadata <- entity %>% get_id_column_metadata()

  # assume first column is the gene ID column
  id_column_names <- id_column_metadata %>% pull(variable)

  if (length(id_column_names) == 0) {
    stop_validation_error(
      user_msg = "No ID column detected in your data file. This usually means the 'geneID' column has duplicate values. Each row must have a unique geneID.",
      technical_msg = paste("No ID column detected - likely duplicate geneID values in:", input_file),
      file = input_file
    )
  }

  gene_id_column <- id_column_names[1]

  if (gene_id_column != "geneID") {
    stop_validation_error(
      user_msg = "Your data file must have a column named 'geneID' (case-sensitive) as the first column.",
      technical_msg = paste("'geneID' column not present or misnamed in:", input_file),
      file = input_file
    )
  }

  if (length(id_column_names) > 1) {
    # demote any extra ID columns to regular variables
    non_gene_column_names <- id_column_names[-1]
    entity <- entity %>% redetect_columns_as_variables(non_gene_column_names)
  }

  # we're now going to add a 'gene' column (copy of 'geneID') unless it already
  # exists and is identical to 'geneID'.
  
  variable_column_names <- entity %>% get_variable_metadata() %>% pull('variable')
  if ('gene' %in% variable_column_names) {
    data <- entity %>% get_data()
    if (!identical(data$geneID, data$gene)) {
      # if it's not identical, it's too complicated to fix - just throw an error
      stop_validation_error(
        user_msg = "Your data file contains both 'geneID' and 'gene' columns, but they have different values. Please remove the 'gene' column or ensure it matches 'geneID' exactly.",
        technical_msg = paste("User-supplied 'gene' column was not identical to 'geneID' column in:", input_file),
        file = input_file
      )
    }
  } else {
    # in most cases we want to create a copy of the geneID column called 'gene'
    # and convert it to a regular variable column
    entity <- entity %>%
      modify_data(
        mutate(gene = geneID)
      ) %>%
      sync_variable_metadata() %>%
      redetect_columns_as_variables('gene')
  }

  # give the 'gene' column the stable_id that has been used elsewhere for phenotype datasets
  # e.g. in ApiCommonModel/Model/lib/wdk/model/records/geneTableQueries.xml
  entity <- entity %>% set_variable_metadata('gene', display_name = 'Gene ID', stable_id = 'VAR_bdc8e679')

  # check there's a number variable
  number_variables <- entity %>%
    get_variable_metadata() %>%
    filter(data_type %in% c('number', 'integer'))
  if (nrow(number_variables) == 0) {
    stop_validation_error(
      user_msg = "Your data file must contain at least one numeric column (in addition to the geneID column).",
      technical_msg = paste("No numeric column found in:", input_file),
      file = input_file
    )
  }

  if (entity %>% validate() == FALSE) {
    stop_transformation_error(
      user_msg = "Data validation failed after processing. Please check that your data file is properly formatted.",
      technical_msg = "Entity validation failed after transformation."
    )
  }

  return(study_from_entities(entities = list(entity)))
}

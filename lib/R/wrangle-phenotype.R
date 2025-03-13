#'
#' wrangle(input_dir)
#'
#' @return a study object
#'
#' Expects only one *.txt or *.tsv file in input directory
#'
wrangle <- function(input_dir) {
  # check for one input file only
  globs <- paste0(input_dir, "/*", c(".txt", ".tsv"))
  input_files <- Sys.glob(globs)

  if (length(input_files) > 1) {
    stop("wrangle-phenotype.R ERROR: Too many txt/tsv input files.")
  }
  if (length(input_files) == 0) {
    stop(paste("wrangle-phenotype.R ERROR: No txt/tsv input file found in:", input_dir))
  }

  input_file <- input_files[1]
  entity <- entity_from_file(input_file, name = "phenotype")

  # see how many ID columns were detected
  id_column_metadata <- entity %>% get_id_column_metadata()

  # assume first column is the gene ID column
  id_column_names <- id_column_metadata %>% pull(variable)
  gene_id_column <- id_column_names[1]

  if (gene_id_column != "geneID") {
    stop(paste("wrangle-phenotype.R ERROR: 'geneID' column not present or misnamed in:", input_file))
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
      stop(paste("wrangle-phenotype.R ERROR: user-supplied 'gene' column was not identical to 'geneID' column in:", input_file))
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

  if (entity %>% validate() == FALSE) {
    stop("wrangle-phenotype.R ERROR: entity does not validate.")
  }

  return(study_from_entities(entities = list(entity)))
}

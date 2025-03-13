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

  if (gene_id_column == 'gene') {
  
  } 

  if (entity %>% validate() == FALSE) {
    stop("wrangle-phenotype.R ERROR: entity does not validate.")
  }

  return(study_from_entities(entities = list(entity)))
}

library(tidyverse)
library(study.wrangler)

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

  entity <- entity_from_file(input_files, name = "phenotype")

  if (entity %>% validate() == FALSE) {
    stop("wrangle-phenotype.R ERROR: entity does not validate.")
  }

  return(study_from_entities(entities = list(entity)))
}

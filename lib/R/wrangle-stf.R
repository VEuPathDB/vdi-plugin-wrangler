#'
#' wrangle(input_dir)
#'
#' @return a study object
#'
#' Expects STF-format TSV files and optional STF YAML metadata
#'
wrangle <- function(input_dir) {
  study <- study_from_stf(input_dir)
  return(study)
}

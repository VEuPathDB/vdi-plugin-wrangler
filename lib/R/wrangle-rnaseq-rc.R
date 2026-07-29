#'
#' wrangle(input_dir)
#'
#' @return a study object
#'
#' Bulk RNA-seq counts + free-form sample metadata. Builds a `sample` root
#' entity (via the LLM-assisted annotation step) and a tall `HTSeq counts`
#' child entity from the deterministically-parsed count file(s).
#'
#' This file is the orchestrator only: it sequences the modules below and
#' owns the error taxonomy. It must not reimplement anything from them.
#'

# `bin/wrangle.R` sources only `lib/R/wrangle-<datatype>.R`, so this file
# must source its own siblings. Resolved via this.path::this.dir(), which
# returns the directory of *this* sourced file regardless of the caller's
# cwd or how it was invoked -- independent of ORIGINAL_WD being set, unlike
# the Sys.getenv("ORIGINAL_WD", unset = ".") fallback used elsewhere in this
# repo (e.g. tests/testthat/test_examples.R:18).
.this_dir <- this.path::this.dir()
source(file.path(.this_dir, "llm_client.R"))
source(file.path(.this_dir, "counts_files.R"))
source(file.path(.this_dir, "annotations_to_stf.R"))
source(file.path(.this_dir, "sample_annotation.R"))

#' Build the tall `HTSeq counts` entity from merged count data
#'
#' @param merged Result of `read_and_merge_counts()`: a tibble with `Gene`,
#'   `sample.ID`, and either `Count` (unstranded) or `Sense.Count` +
#'   `Antisense.Count` (stranded).
#' @return a validated `HTSeq counts` Entity, parented on `sample`
counts_entity <- function(merged) {
  tbl <- merged %>%
    mutate(assay.ID = paste(sample.ID, Gene, sep = ".")) %>%
    relocate(assay.ID, .before = sample.ID)

  entity <- entity_from_tibble(
    tbl,
    name = "HTSeq counts",
    display_name = "HTSeq counts",
    display_name_plural = "HTSeq counts",
    skip_type_convert = TRUE
  ) %>%
    set_parents('sample', 'sample.ID') %>%
    set_variable_metadata('sample.ID', display_name = "Sample ID", hidden = list('variableTree')) %>%
    set_variable_metadata('assay.ID',  display_name = "Assay ID",  hidden = list('variableTree')) %>%
    set_variable_metadata('Gene', display_name = "Gene", stable_id = "VEUPATHDB_GENE_ID")

  if ("Sense.Count" %in% names(tbl)) {
    entity <- entity %>%
      set_variable_metadata('Sense.Count', display_name = "Sense Count",
                            stable_id = "SEQUENCE_READ_COUNT_SENSE",
                            is_featured = TRUE, display_order = 1) %>%
      set_variable_metadata('Antisense.Count', display_name = "Antisense Count",
                            stable_id = "SEQUENCE_READ_COUNT_ANTISENSE", display_order = 2)
  } else {
    entity <- entity %>%
      set_variable_metadata('Count', display_name = "Count",
                            stable_id = "SEQUENCE_READ_COUNT", is_featured = TRUE)
  }

  stop_if_entity_invalid(entity)
  entity
}

wrangle <- function(input_dir) {
  llm_mocks_init(input_dir)

  discovered <- discover_counts_files(input_dir)
  merged     <- read_and_merge_counts(discovered)
  sample_ids <- counts_sample_ids(merged)

  info_text <- read_sample_info_text(discovered$paths[["sample_info"]])

  if (classify_sample_ids(sample_ids) == "labels_uninformative") {
    check_ids_present_in_sample_info(sample_ids, info_text)
  }

  samples <- generate_sample_entity(sample_ids, info_text)
  check_deseq_suitability(samples)

  counts <- counts_entity(merged)

  study_from_entities(list(samples, counts))
}

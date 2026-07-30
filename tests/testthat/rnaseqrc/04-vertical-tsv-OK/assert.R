assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  counts <- study %>% get_entity("HTSeq counts")
  data   <- counts %>% get_data()
  expect_equal(nrow(data), 40)                       # 10 genes x 4 samples
  expect_true("Count" %in% names(data))
  expect_false("Sense.Count" %in% names(data))

  meta <- counts %>% get_variable_metadata()
  stable <- setNames(meta$stable_id, meta$variable)
  expect_equal(stable[["Gene"]],  "VEUPATHDB_GENE_ID")
  expect_equal(stable[["Count"]], "SEQUENCE_READ_COUNT")
}

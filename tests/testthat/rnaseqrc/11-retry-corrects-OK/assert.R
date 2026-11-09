assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  samples <- study %>% get_entity("sample")
  ids <- samples %>% get_data() %>% pull(sample.ID)

  # The first queued `annotate` mock invents "S9" in place of "S4" -- a
  # sample ID absent from the count files. That must be rejected by
  # build_sample_entity()'s gate 2 (invented IDs) and retried automatically
  # with the second, correct, mock. If the retry did not fire, "S9" would
  # leak into the entity here instead of "S4".
  expect_setequal(ids, c("S1", "S2", "S3", "S4"))
  expect_equal(length(ids), 4)
  expect_false("S9" %in% ids)

  # sampleId is exposed as an ordinary variable (so samples can be filtered
  # in the UI) and mirrors the entity ID.
  sample_data <- samples %>% get_data()
  expect_true("sampleId" %in% (samples %>% get_variable_metadata() %>% pull(variable)))
  expect_equal(sample_data$sampleId, sample_data$sample.ID)

  counts <- study %>% get_entity("HTSeq counts")
  expect_equal(counts %>% get_data() %>% nrow(), 40)  # 10 genes x 4 samples
}

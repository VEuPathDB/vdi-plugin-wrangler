assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  samples <- study %>% get_entity("sample")
  sample_data <- samples %>% get_data()
  expect_setequal(
    sample_data %>% pull(sample.ID),
    c("male_3h_rep1", "male_3h_rep2", "female_6h_rep1", "female_6h_rep2")
  )
  # These informative IDs are not mentioned verbatim in sample-info.txt, so
  # this fixture only passes because classify_labels returned
  # labels_informative and skipped check_ids_present_in_sample_info() -- if
  # that branch regressed to always-check, this fixture would fail instead.
  sample_vars <- samples %>% get_variable_metadata() %>% pull(variable)
  expect_true(all(c("sex", "timepoint") %in% sample_vars))

  counts <- study %>% get_entity("HTSeq counts")
  expect_equal(counts %>% get_data() %>% nrow(), 40)  # 10 genes x 4 samples
}

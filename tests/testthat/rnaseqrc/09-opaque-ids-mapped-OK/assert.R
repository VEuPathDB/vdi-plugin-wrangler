assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  samples <- study %>% get_entity("sample")
  # These opaque IDs only pass because sample-info.txt explicitly lists all
  # four of them, satisfying check_ids_present_in_sample_info() (which runs
  # because classify_labels mocks labels_uninformative here).
  expect_setequal(
    samples %>% get_data() %>% pull(sample.ID),
    c("S001", "S002", "S003", "S004")
  )

  counts <- study %>% get_entity("HTSeq counts")
  expect_equal(counts %>% get_data() %>% nrow(), 40)  # 10 genes x 4 samples
}

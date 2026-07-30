assert <- function(study, output_dir) {
  # Regression test for Task 10 / final review's Minor 7: sample-info.txt
  # here is Windows-1252 (a "notes" column mentions "Müller"), and
  # classify_labels is mocked to "labels_uninformative", which forces
  # check_ids_present_in_sample_info() to grepl() each authoritative sample
  # ID against the whole sample-info text. Before read_sample_info_text()
  # transcoded to UTF-8, that whole string carried one invalid-in-locale
  # byte sequence (the "ü"), which made grepl() treat the *entire* string as
  # unmatchable and warn "invalid in this locale" -- so every sample ID was
  # reported "missing" even though S1..S4 appear in plain ASCII right at the
  # start of the file. That surfaced as a validation error blaming the
  # uploader's metadata. This test passing at all is the assertion: it would
  # not have passed before the fix.
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  counts <- study %>% get_entity("HTSeq counts")
  data   <- counts %>% get_data()
  expect_equal(nrow(data), 40)  # 10 genes x 4 samples
}

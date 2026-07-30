assert <- function(study, output_dir) {
  # Same regression as 28-windows1252-sample-info-OK/assert.R, but for a
  # UTF-16 sample-info.txt (BOM plus alternating NULs). This also exercises
  # discover_counts_files()'s own blank-line check on the raw undecoded
  # bytes: base readLines() on UTF-16 without a declared encoding truncates
  # each "line" at the embedded NUL bytes, and the resulting short strings
  # must not crash that check (see the useBytes = TRUE fix in
  # discover_counts_files()) before read_sample_info_text() ever gets a
  # chance to detect the encoding and transcode properly.
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  counts <- study %>% get_entity("HTSeq counts")
  data   <- counts %>% get_data()
  expect_equal(nrow(data), 40)  # 10 genes x 4 samples
}

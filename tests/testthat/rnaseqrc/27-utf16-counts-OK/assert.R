assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  counts <- study %>% get_entity("HTSeq counts")
  data   <- counts %>% get_data()
  expect_equal(nrow(data), 16)  # 4 genes x 4 samples

  # Regression test for Task 10: read_counts_long() used to assume UTF-8
  # unconditionally, unlike every other datatype, so a UTF-16 counts file
  # (BOM plus alternating NULs) used to read as garbage rather than being
  # detected and transcoded. Greek letters (outside the Windows-1252 /
  # ISO-8859-1 repertoire) prove genuine Unicode decoding, not just a
  # Latin-1 special case.
  expect_true("gene_β" %in% data$Gene, label = "β (beta) preserved in Gene")
  expect_true("gene_Ω" %in% data$Gene, label = "Ω (omega) preserved in Gene")
  expect_true("gene_é" %in% data$Gene, label = "é (e-acute) preserved in Gene")
}

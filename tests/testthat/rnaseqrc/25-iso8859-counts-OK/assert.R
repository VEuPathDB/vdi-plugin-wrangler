assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  counts <- study %>% get_entity("HTSeq counts")
  data   <- counts %>% get_data()
  expect_equal(nrow(data), 16)  # 4 genes x 4 samples

  # Regression test for Task 10: read_counts_long() used to assume UTF-8
  # unconditionally, unlike every other datatype. This counts file is
  # ISO-8859-1; if it were misread as UTF-8, these single-byte accented
  # characters would come out mangled or throw a parse error rather than
  # surviving verbatim into the Gene column.
  expect_true("gene_ü" %in% data$Gene, label = "ü (u-umlaut, ISO-8859-1 0xFC) preserved in Gene")
  expect_true("gene_Å" %in% data$Gene, label = "Å (A-ring, ISO-8859-1 0xC5) preserved in Gene")
  expect_true("gene_é" %in% data$Gene, label = "é (e-acute, ISO-8859-1 0xE9) preserved in Gene")
}

assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  counts <- study %>% get_entity("HTSeq counts")
  data   <- counts %>% get_data()
  expect_equal(nrow(data), 16)  # 4 genes x 4 samples

  # Regression test for Task 10: read_counts_long() used to assume UTF-8
  # unconditionally, unlike every other datatype. This counts file is
  # Windows-1252 (distinct from ISO-8859-1 -- see the euro sign below, which
  # only Windows-1252 encodes at 0x80).
  expect_true("gene_ü" %in% data$Gene, label = "ü (u-umlaut) preserved in Gene")
  expect_true("gene_€" %in% data$Gene, label = "€ (euro sign, Windows-1252 0x80) preserved in Gene")
  expect_true("gene_é" %in% data$Gene, label = "é (e-acute) preserved in Gene")
}

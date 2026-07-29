assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  counts <- study %>% get_entity("HTSeq counts")
  data   <- counts %>% get_data()
  expect_equal(nrow(data), 40)  # 10 genes x 4 samples

  # Pins the straight-to-long reading strategy: these gene IDs contain a
  # space, a colon, a dot, and parentheses, and must survive verbatim into
  # the Gene column rather than being mangled by any header-parsing or
  # column-name-sanitization step.
  awkward_ids <- c("gene one", "gene-two:x", "gene.three", "gene(four)")
  expect_true(all(awkward_ids %in% data$Gene))
}

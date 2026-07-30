assert <- function(study, output_dir) {
  entity_names <- study %>% get_entities() %>% map_chr(get_entity_name)
  expect_setequal(entity_names, c("sample", "HTSeq counts"))

  counts <- study %>% get_entity("HTSeq counts")
  data   <- counts %>% get_data()

  # 10 real genes x 4 samples -- the three "__" HTSeq summary rows must have
  # been dropped, not counted as genes.
  expect_equal(nrow(data), 40)
  expect_false(any(startsWith(data$Gene, "__")))
}

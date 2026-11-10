assert <- function(study, output_dir) {
  samples <- study %>% get_entity("sample")
  data <- samples %>% get_data()
  expect_equal(nrow(data), 4)
  expect_true("timepoint" %in% names(data))
  # S1/S2 have timepoints; the controls S3/S4 have none.
  expect_false(any(is.na(data$timepoint[data$sample.ID %in% c("S1", "S2")])))
  expect_true(all(is.na(data$timepoint[data$sample.ID %in% c("S3", "S4")])))
}

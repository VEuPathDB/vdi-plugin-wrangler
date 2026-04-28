assert <- function(study, output_dir) {
  cache_files <- list.files(output_dir, pattern = "attributevalue.*\\.cache$", full.names = TRUE)
  stopifnot("No attributevalue cache found" = length(cache_files) > 0)
  all_text <- paste(
    sapply(cache_files, function(f) paste(readLines(f, encoding = "UTF-8", warn = FALSE), collapse = "\n")),
    collapse = "\n"
  )
  expect_true(grepl("ü", all_text, fixed = TRUE), label = "ü (u-umlaut, ISO-8859-1 0xFC) preserved in cache")
  expect_true(grepl("Å", all_text, fixed = TRUE), label = "Å (A-ring, ISO-8859-1 0xC5) preserved in cache")
  expect_true(grepl("é", all_text, fixed = TRUE), label = "é (e-acute, ISO-8859-1 0xE9) preserved in cache")
}

assert <- function(study, output_dir) {
  cache_files <- list.files(output_dir, pattern = "attributevalue.*\\.cache$", full.names = TRUE)
  stopifnot("No attributevalue cache found" = length(cache_files) > 0)
  all_text <- paste(
    sapply(cache_files, function(f) paste(readLines(f, encoding = "UTF-8", warn = FALSE), collapse = "\n")),
    collapse = "\n"
  )
  expect_true(grepl("ü", all_text, fixed = TRUE), label = "ü (u-umlaut) preserved in cache")
  # € is the euro sign, encoded as 0x80 in Windows-1252 — not present in ISO-8859-1
  expect_true(grepl("€", all_text, fixed = TRUE), label = "€ (euro sign, Windows-1252 0x80) preserved in cache")
}

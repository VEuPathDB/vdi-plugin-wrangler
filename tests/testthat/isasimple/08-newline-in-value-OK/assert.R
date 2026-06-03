assert <- function(study, output_dir) {
  cache_files <- list.files(output_dir, pattern = "attributevalue.*\\.cache$", full.names = TRUE)
  stopifnot("No attributevalue cache found" = length(cache_files) > 0)
  all_text <- paste(
    sapply(cache_files, function(f) paste(readLines(f, encoding = "UTF-8", warn = FALSE), collapse = "\n")),
    collapse = "\n"
  )
  expect_true(grepl("this value contains a newline", all_text, fixed = TRUE),
              label = "newline in value munged to space in cache")
}

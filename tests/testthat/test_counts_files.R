original_wd <- Sys.getenv("ORIGINAL_WD")
if (!dir.exists(original_wd) || original_wd == "") skip("ORIGINAL_WD not set")
suppressWarnings(suppressPackageStartupMessages(library(tidyverse)))
source(file.path(original_wd, "lib/R/error_helpers.R"))
source(file.path(original_wd, "lib/R/counts_files.R"))

# Builds an input dir. `files` is a named list: filename -> character vector of lines.
make_input <- function(files) {
  d <- tempfile("counts_"); dir.create(d)
  for (nm in names(files)) writeLines(files[[nm]], file.path(d, nm))
  d
}

TSV_OK <- c("geneID\tS1\tS2", "g1\t10\t20", "g2\t0\t5")
INFO_OK <- c("sample\ttreatment", "S1\tinfected", "S2\tcontrol")

# DEVIATION from the brief's verbatim test block (self-initiated, not
# requested): stop_validation_error() deliberately cat()s its user-facing
# message to stdout (production VDI captures that for user feedback), and
# every expect_error() call below exercises that path, so without this the
# console fills with ~17 duplicated messages. tests/testthat/test_examples.R
# already swallows this for "fail" fixtures via capture.output() for the same
# reason; we shadow expect_error() here so every expect_error() call below
# (each byte-identical to the brief) gets the same treatment without having
# to touch any test body.
expect_error <- function(...) {
  invisible(capture.output(testthat::expect_error(...)))
}

test_that("unstranded input is discovered", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  got <- discover_counts_files(d)
  expect_equal(got$mode, "unstranded")
  expect_setequal(names(got$paths), c("unstranded", "sample_info"))
})

test_that("stranded pair is discovered", {
  d <- make_input(list("sense-counts.tsv" = TSV_OK, "antisense-counts.tsv" = TSV_OK,
                       "sample-info.txt" = INFO_OK))
  got <- discover_counts_files(d)
  expect_equal(got$mode, "stranded")
  expect_setequal(names(got$paths), c("sense", "antisense", "sample_info"))
})

test_that("sample-info text is returned whole", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  got <- discover_counts_files(d)
  txt <- read_sample_info_text(got$paths[["sample_info"]])
  expect_length(txt, 1)
  expect_match(txt, "infected")
  expect_match(txt, "\n")
})

test_that("sense without antisense is rejected", {
  d <- make_input(list("sense-counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  expect_error(discover_counts_files(d), "antisense")
})

test_that("unstranded alongside stranded is rejected", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sense-counts.tsv" = TSV_OK,
                       "antisense-counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  expect_error(discover_counts_files(d))
})

test_that("missing sample-info is rejected", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK))
  expect_error(discover_counts_files(d), "sample-info")
})

test_that("empty sample-info is rejected", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sample-info.txt" = character(0)))
  expect_error(discover_counts_files(d), "sample-info")
})

test_that("an unrecognised data file is rejected", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK,
                       "counts.tsv" = TSV_OK))
  expect_error(discover_counts_files(d), "counts.tsv")
})

test_that("a duplicated stem is rejected", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "unstranded-counts.csv" = TSV_OK,
                       "sample-info.txt" = INFO_OK))
  expect_error(discover_counts_files(d))
})

test_that("counts are read to long format", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  got <- read_counts_long(file.path(d, "unstranded-counts.tsv"))
  expect_equal(nrow(got), 4)
  expect_named(got, c("Gene", "sample.ID", "Count"))
  expect_type(got$Count, "integer")
  expect_setequal(got$sample.ID, c("S1", "S2"))
})

test_that("comma-delimited .txt is read", {
  d <- make_input(list("unstranded-counts.txt" = c("geneID,S1,S2", "g1,10,20")))
  got <- read_counts_long(file.path(d, "unstranded-counts.txt"))
  expect_setequal(got$sample.ID, c("S1", "S2"))
  expect_equal(sum(got$Count), 30)
})

test_that("an empty first header cell is tolerated", {
  d <- make_input(list("unstranded-counts.tsv" = c("\tS1\tS2", "g1\t10\t20")))
  got <- read_counts_long(file.path(d, "unstranded-counts.tsv"))
  expect_equal(got$Gene, c("g1", "g1"))
})

test_that("HTSeq __ rows are dropped", {
  d <- make_input(list("unstranded-counts.tsv" =
    c("geneID\tS1", "g1\t10", "__no_feature\t999", "__ambiguous\t42")))
  got <- read_counts_long(file.path(d, "unstranded-counts.tsv"))
  expect_equal(got$Gene, "g1")
})

test_that("gene IDs with awkward characters survive verbatim", {
  d <- make_input(list("unstranded-counts.tsv" =
    c("geneID\tS1", "gene one\t10", "gene-two:x\t20")))
  got <- read_counts_long(file.path(d, "unstranded-counts.tsv"))
  expect_setequal(got$Gene, c("gene one", "gene-two:x"))
})

test_that("malformed counts are rejected", {
  bad <- list(
    negative    = c("geneID\tS1", "g1\t-5"),
    fractional  = c("geneID\tS1", "g1\t12.5"),
    nonnumeric  = c("geneID\tS1", "g1\tNA"),
    blank       = c("geneID\tS1\tS2", "g1\t10\t"),
    thousands   = c("geneID\tS1", "g1\t1,200"),
    dupe_gene   = c("geneID\tS1", "g1\t10", "g1\t20"),
    no_samples  = c("geneID", "g1"),
    no_genes    = c("geneID\tS1")
  )
  for (nm in names(bad)) {
    d <- make_input(setNames(list(bad[[nm]]), "unstranded-counts.tsv"))
    expect_error(read_counts_long(file.path(d, "unstranded-counts.tsv")), info = nm)
  }
})

test_that("stranded files are merged into two count columns", {
  d <- make_input(list(
    "sense-counts.tsv"     = c("geneID\tS1\tS2", "g1\t10\t20", "g2\t1\t2"),
    "antisense-counts.tsv" = c("geneID\tS1\tS2", "g1\t3\t4",   "g2\t5\t6"),
    "sample-info.txt" = INFO_OK
  ))
  merged <- read_and_merge_counts(discover_counts_files(d))
  expect_named(merged, c("Gene", "sample.ID", "Sense.Count", "Antisense.Count"))
  expect_equal(nrow(merged), 4)
  expect_equal(counts_sample_ids(merged), c("S1", "S2"))
})

test_that("mismatched sample columns are rejected", {
  d <- make_input(list(
    "sense-counts.tsv"     = c("geneID\tS1\tS2", "g1\t10\t20"),
    "antisense-counts.tsv" = c("geneID\tS1",     "g1\t3"),
    "sample-info.txt" = INFO_OK
  ))
  expect_error(read_and_merge_counts(discover_counts_files(d)), "sample")
})

test_that("mismatched gene sets are rejected", {
  d <- make_input(list(
    "sense-counts.tsv"     = c("geneID\tS1", "g1\t10", "g2\t1"),
    "antisense-counts.tsv" = c("geneID\tS1", "g1\t3"),
    "sample-info.txt" = INFO_OK
  ))
  expect_error(read_and_merge_counts(discover_counts_files(d)), "gene")
})

test_that("unstranded merge keeps a single Count column", {
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  merged <- read_and_merge_counts(discover_counts_files(d))
  expect_named(merged, c("Gene", "sample.ID", "Count"))
})

original_wd <- Sys.getenv("ORIGINAL_WD")
if (!dir.exists(original_wd) || original_wd == "") skip("ORIGINAL_WD not set")
suppressWarnings(suppressPackageStartupMessages({
  library(tidyverse); library(study.wrangler)
}))
set_config(validation.profiles = c("baseline", "eda"))
source(file.path(original_wd, "lib/R/annotations_to_stf.R"))

ANN <- list(
  profileSetName = "Infection time course",
  factors = list(
    timepoint = list(displayName = "timepoint",
                     definition = "Time elapsed after treatment: post-infection",
                     unit = "hour"),
    infection = list(displayName = "infection status",
                     definition = "Whether samples were exposed to a pathogen")
  ),
  samples = list(
    list(sampleId = "S1", label = "infected 24h",
         factors = list(timepoint = "24", infection = "infected")),
    list(sampleId = "S2", label = "control 24h",
         factors = list(timepoint = "24", infection = "control")),
    list(sampleId = "S3", label = "infected 48h",
         factors = list(timepoint = "48", infection = "infected"))
  )
)

test_that("type inference follows the documented rules", {
  expect_equal(infer_stf_type(c("1", "2"))$data_type, "integer")
  expect_equal(infer_stf_type(c("1.5", "2"))$data_type, "number")
  expect_equal(infer_stf_type(c("1e3"))$data_type, "number")
  expect_equal(infer_stf_type(c("2024-01-02"))$data_type, "date")
  expect_equal(infer_stf_type(c("infected", "control"))$data_type, "string")
  expect_equal(infer_stf_type(c("", NA))$data_type, "string")
  expect_equal(infer_stf_type(c("1", "2"))$data_shape, "continuous")
  expect_equal(infer_stf_type(c("a"))$data_shape, "categorical")
})

test_that("the STF pair is written with the correct ID header", {
  d <- tempfile("stf_"); dir.create(d)
  tsv <- annotations_to_stf(ANN, d)
  expect_true(file.exists(tsv))
  expect_true(file.exists(file.path(d, "entity-sample.yaml")))
  header <- strsplit(readLines(tsv)[1], "\t", fixed = TRUE)[[1]]
  expect_equal(header[1], "sample.ID \\\\ Descriptors")
  expect_true("label" %in% header)
  expect_false(any(grepl("SRA", header)))
})

test_that("a colon in a definition does not corrupt the YAML", {
  d <- tempfile("stf_"); dir.create(d)
  annotations_to_stf(ANN, d)
  y <- yaml::read_yaml(file.path(d, "entity-sample.yaml"))
  defs <- vapply(y$variables,
                 function(v) if (is.null(v$definition)) "" else v$definition,
                 character(1))
  expect_true(any(grepl("Time elapsed after treatment: post-infection", defs, fixed = TRUE)))
})

test_that("timepoint is typed integer with its unit, label is always string", {
  d <- tempfile("stf_"); dir.create(d)
  annotations_to_stf(ANN, d)
  y <- yaml::read_yaml(file.path(d, "entity-sample.yaml"))
  by_name <- setNames(y$variables, vapply(y$variables, function(v) v$variable, character(1)))
  expect_equal(by_name$timepoint$data_type, "integer")
  expect_equal(by_name$timepoint$unit, "hour")
  expect_equal(by_name$label$data_type, "string")
  expect_null(by_name$label$unit)
})

test_that("the written STF loads as a valid study-wrangler entity", {
  d <- tempfile("stf_"); dir.create(d)
  tsv <- annotations_to_stf(ANN, d)
  entity <- entity_from_stf(tsv)
  expect_true(isTRUE(entity %>% quiet() %>% validate()))
  expect_setequal(entity %>% get_data() %>% pull(sample.ID), c("S1", "S2", "S3"))
})

test_that("a sample with no label does not shift the following columns", {
  # Regression test for finding 1: c() drops NULL, so an LLM response that
  # omits `label` for one sample used to shift every later field in that
  # row one column to the left against the (unshifted) header.
  ann <- ANN
  ann$samples[[1]]$label <- NULL # simulate the LLM omitting the field entirely
  d <- tempfile("stf_"); dir.create(d)
  tsv <- annotations_to_stf(ann, d)
  lines <- readLines(tsv)
  header_fields <- strsplit(lines[1], "\t", fixed = TRUE)[[1]]
  row1_fields <- strsplit(lines[2], "\t", fixed = TRUE)[[1]]
  expect_length(row1_fields, length(header_fields))
  expect_equal(row1_fields[1], "S1")
  expect_equal(row1_fields[2], "") # label: empty, not eaten by the shift
  expect_equal(row1_fields[3], "24") # timepoint: still in its own column
  expect_equal(row1_fields[4], "infected") # infection: still in its own column
})

test_that("a literal tab or newline in an LLM-authored value does not shift columns", {
  # Regression test for finding 1's second hazard: even with the field count
  # guaranteed, a literal tab/CR/LF embedded in a label or factor value
  # (reachable by a prompt-injecting uploader via the free-form sample-info
  # file, since it flows through the LLM into this JSON) would itself act as
  # a stray field separator or row terminator.
  ann <- ANN
  ann$samples[[1]]$label <- "infected\t24h"
  ann$samples[[2]]$factors$infection <- "cont\nrol"
  d <- tempfile("stf_"); dir.create(d)
  tsv <- annotations_to_stf(ann, d)
  lines <- readLines(tsv)
  header_fields <- strsplit(lines[1], "\t", fixed = TRUE)[[1]]
  for (line in lines[-1]) {
    expect_length(strsplit(line, "\t", fixed = TRUE)[[1]], length(header_fields))
  }
  entity <- entity_from_stf(tsv)
  expect_true(isTRUE(entity %>% quiet() %>% validate()))
  expect_setequal(entity %>% get_data() %>% pull(sample.ID), c("S1", "S2", "S3"))
})

test_that("a factor key containing a space becomes a dotted column", {
  ann <- ANN
  ann$factors <- list(`cell type` = list(displayName = "cell type"))
  ann$samples <- list(
    list(sampleId = "S1", label = "a", factors = list(`cell type` = "liver")),
    list(sampleId = "S2", label = "b", factors = list(`cell type` = "spleen"))
  )
  d <- tempfile("stf_"); dir.create(d)
  tsv <- annotations_to_stf(ann, d)
  expect_true("cell.type" %in% strsplit(readLines(tsv)[1], "\t", fixed = TRUE)[[1]])
  expect_true(isTRUE(entity_from_stf(tsv) %>% quiet() %>% validate()))
})

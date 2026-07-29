original_wd <- Sys.getenv("ORIGINAL_WD")
if (!dir.exists(original_wd) || original_wd == "") skip("ORIGINAL_WD not set")
suppressWarnings(suppressPackageStartupMessages({
  library(tidyverse); library(study.wrangler)
}))
set_config(validation.profiles = c("baseline", "eda"))
for (f in c("error_helpers.R", "llm_client.R", "annotations_to_stf.R", "sample_annotation.R")) {
  source(file.path(original_wd, "lib/R", f))
}

# DEVIATION from the brief's verbatim test block (self-initiated, not
# requested): several expect_error() calls below exercise
# stop_validation_error()/stop_transformation_error(), which deliberately
# cat() a user-facing message to stdout (production VDI captures that for
# user feedback). Without this shim the console fills with duplicated
# messages. tests/testthat/test_counts_files.R (Task 2) already establishes
# this exact pattern and documents it the same way.
expect_error <- function(...) {
  invisible(capture.output(testthat::expect_error(...)))
}

ann_for <- function(ids, factor_values = NULL) {
  if (is.null(factor_values)) factor_values <- rep(c("infected", "control"), length.out = length(ids))
  list(
    profileSetName = "test",
    factors = list(infection = list(displayName = "infection",
                                    definition = "Exposure to a pathogen")),
    samples = map2(ids, factor_values, ~ list(
      sampleId = .x, label = .y, factors = list(infection = .y)
    ))
  )
}

mock_dir <- function(obj) {
  d <- tempfile("mocks_"); dir.create(d)
  jsonlite::write_json(obj, file.path(d, "llm-mocks.json"), auto_unbox = TRUE)
  d
}

test_that("classification maps an unrecognised reply to uninformative", {
  d <- mock_dir(list(classify_labels = list("who knows")))
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    expect_equal(classify_sample_ids(c("S1", "S2")), "labels_uninformative")
  })
})

test_that("classification passes through a recognised reply", {
  d <- mock_dir(list(classify_labels = list("labels_informative")))
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    expect_equal(classify_sample_ids(c("male_3h_rep1")), "labels_informative")
  })
})

test_that("IDs absent from sample-info are rejected by name", {
  expect_error(
    check_ids_present_in_sample_info(c("S1", "S2", "S9"), "S1 is infected, S2 is control"),
    "S9"
  )
  expect_true(check_ids_present_in_sample_info(c("S1"), "S1 is infected"))
})

test_that("a well-formed annotation builds a valid entity", {
  entity <- build_sample_entity(ann_for(c("S1", "S2")), c("S1", "S2"))
  expect_true(isTRUE(entity %>% quiet() %>% validate()))
  expect_setequal(entity %>% get_data() %>% pull(sample.ID), c("S1", "S2"))
})

test_that("an invented sample ID is rejected and named", {
  expect_error(build_sample_entity(ann_for(c("S1", "S9")), c("S1", "S2")), "S9")
})

test_that("a missing sample ID is rejected and named", {
  expect_error(build_sample_entity(ann_for(c("S1")), c("S1", "S2")), "S2")
})

test_that("a failed first attempt is corrected by the retry", {
  d <- mock_dir(list(annotate = list(ann_for(c("S1", "S9")), ann_for(c("S1", "S2")))))
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    entity <- generate_sample_entity(c("S1", "S2"), "S1 infected, S2 control")
    expect_setequal(entity %>% get_data() %>% pull(sample.ID), c("S1", "S2"))
    expect_length(llm_mocks_exhausted(), 0)
  })
})

test_that("a genuinely entity-invalid first attempt (not a bad ID) is corrected by the retry", {
  # Regression test for gate 1: the first annotation below covers both
  # authoritative IDs (no invented/missing IDs -- gates 2 and 3 would pass),
  # but repeats "S1", which fails the entity's own duplicate-ID-column
  # validator (a genuine stop_if_entity_invalid()-style failure, not a bad
  # sample ID). If gate 1 ever regresses to a non-catchable
  # stop_if_entity_invalid() call in production, this exact shape of failure
  # would kill the process before the retry ran. Under TESTTHAT=true (as
  # here) that regression would still be caught by testthat's stop()-based
  # translation of quit(), so this test alone cannot fully protect against
  # it -- see the comment on gate 1 in sample_annotation.R for the rest of
  # the guard.
  d <- mock_dir(list(annotate = list(ann_for(c("S1", "S2", "S1")), ann_for(c("S1", "S2")))))
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    entity <- generate_sample_entity(c("S1", "S2"), "S1 infected, S2 control")
    expect_setequal(entity %>% get_data() %>% pull(sample.ID), c("S1", "S2"))
    expect_length(llm_mocks_exhausted(), 0)
  })
})

test_that("two failed attempts stop with a transformation error", {
  d <- mock_dir(list(annotate = list(ann_for(c("S1", "S9")), ann_for(c("S1", "S8")))))
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    expect_error(generate_sample_entity(c("S1", "S2"), "info"), "TRANSFORMATION ERROR")
  })
})

test_that("a large sample count adds the AI-processing warning", {
  ids <- sprintf("S%02d", 1:31)
  d <- mock_dir(list(annotate = list(ann_for("X1"), ann_for("X1"))))
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    # DEVIATION (directed by the coordinator, not self-initiated): this call
    # is qualified as testthat::expect_error() rather than the file-scoped
    # expect_error() shim above, because this test wraps its own
    # capture.output() around the call to assert on the stdout text itself.
    # The shim's own internal capture.output() would otherwise swallow the
    # message before this test's outer capture.output() ever saw it. The
    # qualifier changes nothing about what the test asserts -- expect_error
    # and testthat::expect_error are the same function -- it only avoids
    # double-capturing the output.
    out <- capture.output(testthat::expect_error(generate_sample_entity(ids, "info")))
    expect_match(paste(out, collapse = "\n"), "31")
    expect_match(paste(out, collapse = "\n"), "AI-based processing")
  })
})

test_that("the retry prompt carries the previous errors and the ID list", {
  p <- annotation_prompt(c("S1", "S2"), "info", previous_errors = "sample ID 'S9' is not known")
  expect_match(p, "S9", fixed = TRUE)
  expect_match(p, "S1", fixed = TRUE)
})

test_that("DESeq suitability requires a factor beyond label", {
  ok <- build_sample_entity(ann_for(c("S1", "S2")), c("S1", "S2"))
  expect_true(check_deseq_suitability(ok))
})

test_that("label-only annotation is unsuitable for DESeq", {
  ann <- list(
    profileSetName = "test", factors = list(),
    samples = list(list(sampleId = "S1", label = "a", factors = list()),
                   list(sampleId = "S2", label = "b", factors = list()))
  )
  entity <- build_sample_entity(ann, c("S1", "S2"))
  expect_error(check_deseq_suitability(entity), "VALIDATION ERROR")
})

test_that("an all-constant factor is unsuitable for DESeq", {
  entity <- build_sample_entity(ann_for(c("S1", "S2"), c("infected", "infected")),
                                c("S1", "S2"))
  expect_error(check_deseq_suitability(entity))
})

test_that("a single sample is unsuitable for DESeq", {
  entity <- build_sample_entity(ann_for("S1"), "S1")
  expect_error(check_deseq_suitability(entity))
})

test_that("one sample per factor level is suitable", {
  ann <- list(
    profileSetName = "t",
    factors = list(timepoint = list(displayName = "timepoint", unit = "hour")),
    samples = map(as.character(c(1, 2, 3, 4)), ~ list(
      sampleId = paste0("S", .x), label = paste0("t", .x),
      factors = list(timepoint = .x)
    ))
  )
  entity <- build_sample_entity(ann, paste0("S", 1:4))
  expect_true(check_deseq_suitability(entity))
})

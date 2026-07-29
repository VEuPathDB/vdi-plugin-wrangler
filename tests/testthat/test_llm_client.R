original_wd <- Sys.getenv("ORIGINAL_WD")
if (!dir.exists(original_wd) || original_wd == "") skip("ORIGINAL_WD not set")
source(file.path(original_wd, "lib/R/error_helpers.R"))
source(file.path(original_wd, "lib/R/llm_client.R"))

make_mock_dir <- function(contents) {
  d <- tempfile("mockdir_"); dir.create(d)
  writeLines(contents, file.path(d, "llm-mocks.json"))
  d
}

test_that("mocks are ignored unless explicitly allowed", {
  d <- make_mock_dir('{"classify": ["labels_informative"]}')
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = ""), {
    llm_mocks_init(d)
    expect_length(llm_mocks_exhausted(), 0)
  })
})

test_that("queued mock responses are returned in order", {
  d <- make_mock_dir('{"classify": ["labels_informative", "labels_uninformative"]}')
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    expect_equal(llm_text("classify", "m", "s", "u"), "labels_informative")
    expect_equal(llm_text("classify", "m", "s", "u"), "labels_uninformative")
  })
})

test_that("exhausting a mock queue is an error, not a real API call", {
  d <- make_mock_dir('{"classify": ["labels_informative"]}')
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    invisible(llm_text("classify", "m", "s", "u"))
    expect_error(llm_text("classify", "m", "s", "u"), "classify")
  })
})

test_that("llm_json strips markdown fences", {
  d <- make_mock_dir('{"annotate": ["```json\\n{\\"a\\": 1}\\n```"]}')
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    expect_equal(llm_json("annotate", "m", "s", "u")$a, 1)
  })
})

test_that("llm_json accepts a nested list mock", {
  d <- tempfile("mockdir_"); dir.create(d)
  jsonlite::write_json(
    list(annotate = list(list(profileSetName = "x", samples = list()))),
    file.path(d, "llm-mocks.json"), auto_unbox = TRUE
  )
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    expect_equal(llm_json("annotate", "m", "s", "u")$profileSetName, "x")
  })
})

test_that("llm_text raises a silent llm_api_error on an API failure (no STDOUT write)", {
  # Regression test for the bug fixed in Task 8b: llm_text() used to route
  # API failures through stop_unexpected_error(), which writes the
  # user-facing message to STDOUT immediately -- before generate_sample_entity()
  # in lib/R/sample_annotation.R ever gets a chance to decide whether a
  # first-attempt failure is actually terminal (its retry may still recover).
  # The missing-API-key path is used here because it reaches the API-failure
  # branch deterministically, with no network call and no mock involved.
  llm_mocks_init(tempfile()) # clear any queued mocks left over by earlier tests
  withr::with_envvar(c(CLAUDE_API_KEY = ""), {
    result <- NULL
    out <- capture.output(
      result <- tryCatch(llm_text("classify", "m", "s", "u"), error = function(e) e)
    )
    expect_equal(out, character(0))
    expect_s3_class(result, "llm_api_error")
    expect_match(conditionMessage(result), "CLAUDE_API_KEY", fixed = TRUE)
  })
})

test_that("llm_mocks_exhausted reports unconsumed queues", {
  d <- make_mock_dir('{"classify": ["a"], "annotate": ["b"]}')
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    invisible(llm_text("classify", "m", "s", "u"))
    expect_equal(llm_mocks_exhausted(), "annotate")
  })
})

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

test_that("llm_mocks_exhausted reports unconsumed queues", {
  d <- make_mock_dir('{"classify": ["a"], "annotate": ["b"]}')
  withr::with_envvar(c(WRANGLER_ALLOW_LLM_MOCKS = "1"), {
    llm_mocks_init(d)
    invisible(llm_text("classify", "m", "s", "u"))
    expect_equal(llm_mocks_exhausted(), "annotate")
  })
})

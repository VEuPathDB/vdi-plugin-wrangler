#' Generic Claude Messages API client with a test mock registry
#'
#' This module provides a minimal wrapper around the Anthropic Messages API
#' (https://api.anthropic.com/v1/messages) plus a FIFO mock registry that lets
#' tests substitute canned responses instead of making real, paid API calls.
#'
#' This file has no knowledge of any particular use case (e.g. RNA-seq) --
#' it is purely a transport + mocking layer. Domain logic belongs elsewhere.

#' Module-level mock registry
#'
#' A FIFO queue of mock responses per call_name. Populated by
#' \code{llm_mocks_init()} and consumed by \code{llm_text()}.
.llm_mocks <- new.env(parent = emptyenv())

#' Reset and (optionally) load the LLM mock registry
#'
#' Always clears any previously loaded mocks. Only loads
#' \code{llm-mocks.json} from \code{input_dir} when the environment variable
#' \code{WRANGLER_ALLOW_LLM_MOCKS} is exactly \code{"1"} AND the file exists.
#' This means an uploaded \code{llm-mocks.json} can never divert a production
#' run -- mocks are only ever consulted when a test/operator has explicitly
#' opted in via the environment variable.
#'
#' @param input_dir Directory to look for llm-mocks.json in.
#' @return Invisible NULL.
llm_mocks_init <- function(input_dir) {
  rm(list = ls(envir = .llm_mocks), envir = .llm_mocks)

  if (!identical(Sys.getenv("WRANGLER_ALLOW_LLM_MOCKS"), "1")) {
    return(invisible(NULL))
  }

  mocks_file <- file.path(input_dir, "llm-mocks.json")
  if (!file.exists(mocks_file)) {
    return(invisible(NULL))
  }

  mocks <- jsonlite::fromJSON(mocks_file, simplifyVector = FALSE)
  for (call_name in names(mocks)) {
    assign(call_name, mocks[[call_name]], envir = .llm_mocks)
  }

  invisible(NULL)
}

#' Report call_names with unconsumed queued mock responses
#'
#' Used by tests to assert that all queued mocks were actually consumed by
#' the code under test -- an unconsumed queue usually means an expected call
#' never happened.
#'
#' @return Character vector of call_names with at least one queued response
#'   remaining.
llm_mocks_exhausted <- function() {
  call_names <- ls(envir = .llm_mocks)
  unconsumed <- Filter(function(call_name) {
    length(get(call_name, envir = .llm_mocks)) > 0
  }, call_names)
  as.character(unconsumed)
}

#' Pop the next queued mock response for a call_name, if a queue exists
#'
#' @param call_name The call_name to look up.
#' @return A list with elements \code{found} (logical) and \code{value}
#'   (the popped mock value, or NULL).
.llm_mock_pop <- function(call_name) {
  if (!exists(call_name, envir = .llm_mocks, inherits = FALSE)) {
    return(list(found = FALSE, value = NULL))
  }

  queue <- get(call_name, envir = .llm_mocks)
  if (length(queue) == 0) {
    stop(sprintf(
      "llm_text: mock queue for call_name '%s' is exhausted -- refusing to fall through to a real API call",
      call_name
    ))
  }

  value <- queue[[1]]
  assign(call_name, queue[-1], envir = .llm_mocks)
  list(found = TRUE, value = value)
}

#' Strip a leading/trailing markdown code fence from text
#'
#' Handles ```json ... ``` and bare ``` ... ```, with surrounding whitespace.
#'
#' @param text Character scalar, possibly fenced.
#' @return Character scalar with fences removed.
.strip_markdown_fences <- function(text) {
  trimmed <- trimws(text)
  trimmed <- sub("^```[a-zA-Z]*\\s*\\n?", "", trimmed)
  trimmed <- sub("\\n?```\\s*$", "", trimmed)
  trimws(trimmed)
}

#' Raise a classed `llm_api_error` condition for a Claude API failure
#'
#' Every failure path in `llm_text()` that reflects a genuine Claude API
#' problem (missing key, unreachable network, non-2xx status after retries,
#' or a malformed response body) raises this classed condition rather than
#' calling `stop_unexpected_error()` directly.
#'
#' This deliberately does **not** write anything to STDOUT, unlike
#' `stop_unexpected_error()`. `llm_text()` is called from inside
#' `generate_sample_entity()` (see `lib/R/sample_annotation.R`), which wraps
#' each of its two annotation attempts in its own `tryCatch()` so a failed
#' first attempt can be retried. If a first-attempt API failure printed a
#' user-facing "the wrangler received an error from the Claude API" message
#' to STDOUT -- as `stop_unexpected_error()` does -- that message would still
#' reach the uploader (VDI surfaces STDOUT as user feedback) even when the
#' retry goes on to recover and the import succeeds. Raising a plain, silent
#' condition here leaves the STDOUT write to whichever caller determines the
#' failure is actually terminal.
#'
#' Any caller of `llm_text()`/`llm_json()` that is NOT already inside a
#' `tryCatch()` covering this condition must catch `llm_api_error` itself and
#' convert it to a proper `stop_*_error()` call -- otherwise the condition
#' reaches `bin/wrangle.R` (which has no top-level error handler) as a raw,
#' unreported R error with the wrong exit code. Do not "helpfully" route this
#' back through `stop_unexpected_error()` here; that would reintroduce the
#' premature-STDOUT-write bug this exists to prevent.
#'
#' @param message Technical error text -- identical to what used to be
#'   passed as `technical_msg` to `stop_unexpected_error()` at each call site.
.stop_llm_api_error <- function(message) {
  stop(structure(
    class = c("llm_api_error", "error", "condition"),
    list(message = message, call = NULL)
  ))
}

#' Raise a classed `llm_refusal_error` condition for a Claude safety-classifier decline
#'
#' Claude's Messages API reports a safety-classifier decline as a normal HTTP
#' 200 response with `stop_reason: "refusal"` and a `stop_details` object
#' (`category`/`explanation`, either of which may be `null`) -- not as an
#' error, and not necessarily with an empty `content` array. See
#' https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback.
#'
#' This is a subclass of `llm_api_error` so any existing `tryCatch()` that
#' catches `llm_api_error` keeps working unchanged. Callers that want to
#' surface the classifier's stated reason to the uploader -- rather than the
#' generic "could not reach the Claude API" framing, which wrongly implies a
#' transient outage that a later retry might fix -- should catch
#' `llm_refusal_error` specifically, ahead of `llm_api_error`, and read its
#' `category`/`explanation` elements.
#'
#' Strip Anthropic's API-integrator guidance from a refusal explanation
#'
#' `stop_details$explanation` on a refusal sometimes includes a sentence
#' aimed at API integrators (e.g. "API integrators: you can reduce refusals
#' for your users by configuring a fallback model -- see
#' https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback").
#' That sentence is developer-facing guidance, not something a web uploader
#' can act on, so it must not reach user-facing error messages. This drops
#' everything from "API integrators" onward and returns NULL if nothing
#' meaningful is left.
#'
#' @param explanation `stop_details$explanation`, or NULL.
#' @return Sanitized explanation, or NULL if NULL/blank after stripping.
.sanitize_refusal_explanation <- function(explanation) {
  if (is.null(explanation)) {
    return(NULL)
  }
  cleaned <- trimws(sub("API integrators:.*$", "", explanation, perl = TRUE, ignore.case = TRUE))
  if (nchar(cleaned) == 0) NULL else cleaned
}

#' @param category `stop_details$category`, or NULL if uncategorized.
#' @param explanation `stop_details$explanation`, or NULL if uncategorized.
.stop_llm_refusal_error <- function(category, explanation) {
  stop(structure(
    class = c("llm_refusal_error", "llm_api_error", "error", "condition"),
    list(
      message = sprintf(
        "Claude declined to process this request (category: %s): %s",
        if (is.null(category)) "unspecified" else category,
        if (is.null(explanation)) "no explanation given" else explanation
      ),
      call = NULL,
      category = category,
      explanation = explanation
    )
  ))
}

#' Call the Claude Messages API (or return a queued mock), returning raw text
#'
#' @param call_name Logical name for this call site, used for mock lookup and
#'   error messages (e.g. "classify", "annotate"). Purely a routing key --
#'   carries no domain meaning here.
#' @param model The Claude model id, e.g. "claude-opus-5".
#' @param system_prompt The system prompt string.
#' @param user_prompt The user prompt string.
#' @param max_tokens Maximum tokens in the response. Default 4096.
#' @return Length-1 character: the raw assistant text.
llm_text <- function(call_name, model, system_prompt, user_prompt, max_tokens = 4096) {
  mock <- .llm_mock_pop(call_name)
  if (mock$found) {
    value <- mock$value
    # Mirrors the real API's refusal shape (see .stop_llm_refusal_error()) so
    # a test's llm-mocks.json can simulate a guardrail decline by queuing
    # e.g. {"stop_reason": "refusal", "category": "bio", "explanation": "..."}
    # instead of a normal text/JSON reply.
    if (is.list(value) && identical(value$stop_reason, "refusal")) {
      .stop_llm_refusal_error(value$category, value$explanation)
    }
    if (is.character(value)) {
      return(value)
    }
    return(as.character(jsonlite::toJSON(value, auto_unbox = TRUE)))
  }

  # Fail-closed test guard: WRANGLER_ALLOW_LLM_MOCKS=1 only *permits* mocks,
  # it does not *forbid* a real call when no queue exists for this
  # call_name -- a forgotten llm-mocks.json, a typo'd call_name, or a defect
  # letting a "should fail earlier" fixture reach this point would otherwise
  # fall straight through to a real, billable httr::POST(). Set only by the
  # test harness (tests/testthat/test_examples.R), per example, never in
  # production -- see that file for why it must be per-example rather than
  # process-wide (the opt-in `-live` fixtures share this R process with
  # every other fixture). Checked before the API key so it fires even when
  # a real CLAUDE_API_KEY is present in the environment (as it now is for
  # every `make test` run, per docker-compose.yml).
  if (identical(Sys.getenv("WRANGLER_LLM_OFFLINE"), "1")) {
    stop(sprintf(
      paste(
        "llm_text: refusing to make a real Claude API call for call_name",
        "'%s' because WRANGLER_LLM_OFFLINE=1 -- add a queued response for",
        "this call_name to the test's llm-mocks.json"
      ),
      call_name
    ))
  }

  api_key <- Sys.getenv("CLAUDE_API_KEY")
  if (identical(api_key, "")) {
    .stop_llm_api_error("CLAUDE_API_KEY environment variable is not set")
  }

  body <- list(
    model = model,
    max_tokens = max_tokens,
    system = system_prompt,
    messages = list(list(role = "user", content = user_prompt))
  )

  max_attempts <- 3
  last_error <- NULL

  for (attempt in seq_len(max_attempts)) {
    response <- tryCatch(
      httr::POST(
        url = "https://api.anthropic.com/v1/messages",
        httr::add_headers(
          `x-api-key` = api_key,
          `anthropic-version` = "2023-06-01",
          `content-type` = "application/json"
        ),
        body = jsonlite::toJSON(body, auto_unbox = TRUE),
        encode = "raw"
      ),
      error = function(e) e
    )

    if (inherits(response, "error")) {
      last_error <- conditionMessage(response)
      if (attempt < max_attempts) {
        Sys.sleep(2^(attempt - 1))
        next
      }
      .stop_llm_api_error(paste("Network error calling Claude API:", last_error))
    }

    status <- httr::status_code(response)
    if (status >= 200 && status < 300) {
      parsed <- httr::content(response, as = "parsed", type = "application/json", encoding = "UTF-8")
      if (identical(parsed$stop_reason, "refusal")) {
        .stop_llm_refusal_error(parsed$stop_details$category, parsed$stop_details$explanation)
      }
      text <- tryCatch(parsed$content[[1]]$text, error = function(e) NULL)
      if (is.null(text)) {
        .stop_llm_api_error(paste(
          "Claude API response missing content[[1]]$text:",
          as.character(jsonlite::toJSON(parsed, auto_unbox = TRUE))
        ))
      }
      return(text)
    }

    retryable <- (status == 429) || (status >= 500)
    if (retryable && attempt < max_attempts) {
      Sys.sleep(2^(attempt - 1))
      next
    }

    body_text <- httr::content(response, as = "text", encoding = "UTF-8")
    .stop_llm_api_error(sprintf("Claude API returned HTTP %d: %s", status, body_text))
  }

  # Unreachable, but keep R CMD check happy about a return path.
  .stop_llm_api_error("Exhausted retries calling Claude API")
}

#' Call the Claude Messages API and parse the response as JSON
#'
#' Calls \code{llm_text()}, strips any markdown code fence, and parses the
#' result with \code{jsonlite::fromJSON(simplifyVector = FALSE)}.
#'
#' @param call_name Logical name for this call site (see \code{llm_text()}).
#' @param model The Claude model id.
#' @param system_prompt The system prompt string.
#' @param user_prompt The user prompt string.
#' @param max_tokens Maximum tokens in the response. Default 8192.
#' @return A parsed list (nested lists/vectors as produced by
#'   \code{jsonlite::fromJSON} with \code{simplifyVector = FALSE}).
llm_json <- function(call_name, model, system_prompt, user_prompt, max_tokens = 8192) {
  text <- llm_text(call_name, model, system_prompt, user_prompt, max_tokens = max_tokens)
  stripped <- .strip_markdown_fences(text)
  jsonlite::fromJSON(stripped, simplifyVector = FALSE)
}

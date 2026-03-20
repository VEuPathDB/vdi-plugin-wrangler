#' Error Reporting Helpers for VDI Plugin Wrangler
#'
#' These functions formalize error reporting by:
#' - Writing user-friendly messages to STDOUT (captured by VDI for user feedback)
#' - Writing technical details to STDERR via message() (sent to logfiles)
#' - Exiting with proper status codes via quit()
#' - Categorizing errors by type (validation, transformation, incompatible, unexpected)
#'
#' Error types map to exit codes defined in lib/includes.sh:
#' - validation: EXIT_CODE_VALIDATION_ERROR=99
#' - transformation: EXIT_CODE_TRANSFORMATION_ERROR=99
#' - incompatible: EXIT_CODE_INCOMPATIBLE=99
#' - unexpected: EXIT_CODE_UNEXPECTED_ERROR=255

# Define exit codes as constants
EXIT_CODE_VALIDATION_ERROR <- 99
EXIT_CODE_TRANSFORMATION_ERROR <- 99
EXIT_CODE_INCOMPATIBLE <- 99
EXIT_CODE_UNEXPECTED_ERROR <- 255

#' Stop with a validation error
#'
#' Use for errors related to invalid input data, malformed files, missing required
#' fields, duplicate IDs, wrong column names, etc.
#'
#' @param user_msg User-friendly message (written to STDOUT for VDI user feedback)
#' @param technical_msg Technical details (written to STDERR logs). Defaults to user_msg if NULL.
#' @param file Optional file path to include in technical message for debugging
stop_validation_error <- function(user_msg, technical_msg = NULL, file = NULL) {
  # Write user-friendly message to STDOUT
  cat(user_msg, "\n", file = stdout())

  # Build technical message for STDERR
  if (is.null(technical_msg)) {
    technical_msg <- user_msg
  }

  error_msg <- paste0("VALIDATION ERROR: ", technical_msg)
  if (!is.null(file)) {
    error_msg <- paste0(error_msg, "\nFile: ", file)
  }

  # Write technical error to STDERR
  message(error_msg)

  # In test environment, use stop() so errors are catchable
  # In production, use quit() to return proper exit code
  if (identical(Sys.getenv("TESTTHAT"), "true")) {
    stop(error_msg, call. = FALSE)
  } else {
    quit(status = EXIT_CODE_VALIDATION_ERROR, save = "no")
  }
}

#' Stop with a transformation error
#'
#' Use for errors that occur during data transformation, entity creation,
#' or study validation after initial data validation has passed.
#'
#' @param user_msg User-friendly message (written to STDOUT for VDI user feedback)
#' @param technical_msg Technical details (written to STDERR logs). Defaults to user_msg if NULL.
#' @param file Optional file path to include in technical message for debugging
stop_transformation_error <- function(user_msg, technical_msg = NULL, file = NULL) {
  # Write user-friendly message to STDOUT
  cat(user_msg, "\n", file = stdout())

  # Build technical message for STDERR
  if (is.null(technical_msg)) {
    technical_msg <- user_msg
  }

  error_msg <- paste0("TRANSFORMATION ERROR: ", technical_msg)
  if (!is.null(file)) {
    error_msg <- paste0(error_msg, "\nFile: ", file)
  }

  # Write technical error to STDERR
  message(error_msg)

  # In test environment, use stop() so errors are catchable
  # In production, use quit() to return proper exit code
  if (identical(Sys.getenv("TESTTHAT"), "true")) {
    stop(error_msg, call. = FALSE)
  } else {
    quit(status = EXIT_CODE_TRANSFORMATION_ERROR, save = "no")
  }
}

#' Stop with an incompatibility error
#'
#' Use for errors related to missing dependencies, unsupported data categories,
#' or system configuration issues.
#'
#' @param user_msg User-friendly message (written to STDOUT for VDI user feedback)
#' @param technical_msg Technical details (written to STDERR logs). Defaults to user_msg if NULL.
#' @param file Optional file path to include in technical message for debugging
stop_incompatible_error <- function(user_msg, technical_msg = NULL, file = NULL) {
  # Write user-friendly message to STDOUT
  cat(user_msg, "\n", file = stdout())

  # Build technical message for STDERR
  if (is.null(technical_msg)) {
    technical_msg <- user_msg
  }

  error_msg <- paste0("INCOMPATIBLE ERROR: ", technical_msg)
  if (!is.null(file)) {
    error_msg <- paste0(error_msg, "\nFile: ", file)
  }

  # Write technical error to STDERR
  message(error_msg)

  # In test environment, use stop() so errors are catchable
  # In production, use quit() to return proper exit code
  if (identical(Sys.getenv("TESTTHAT"), "true")) {
    stop(error_msg, call. = FALSE)
  } else {
    quit(status = EXIT_CODE_INCOMPATIBLE, save = "no")
  }
}

#' Validate an entity and stop with a transformation error if invalid
#'
#' Runs validate() twice on the failure path: once with format="upload" for the
#' user-facing message (plain language, no R code) and once with format="full"
#' for the technical log (includes R remediation hints).
#' Does nothing if the entity is valid.
#'
#' @param entity An Entity object to validate
stop_if_entity_invalid <- function(entity) {
  upload_msgs <- character(0)
  is_valid <- withCallingHandlers(
    entity %>% validate(format = "upload"),
    warning = function(w) {
      upload_msgs <<- c(upload_msgs, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  if (!is_valid) {
    technical_msgs <- character(0)
    withCallingHandlers(
      entity %>% validate(),
      warning = function(w) {
        technical_msgs <<- c(technical_msgs, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    stop_transformation_error(
      user_msg = paste(
        c("Your data could not be loaded into the database:", upload_msgs),
        collapse = "\n\n"
      ),
      technical_msg = paste(
        c("Entity validation failed:", technical_msgs),
        collapse = "\n\n"
      )
    )
  }
}

#' Stop with an unexpected error
#'
#' Use for truly unexpected errors that shouldn't happen under normal circumstances,
#' such as internal logic errors or system failures.
#'
#' @param user_msg User-friendly message (written to STDOUT for VDI user feedback)
#' @param technical_msg Technical details (written to STDERR logs). Defaults to user_msg if NULL.
#' @param file Optional file path to include in technical message for debugging
stop_unexpected_error <- function(user_msg, technical_msg = NULL, file = NULL) {
  # Write user-friendly message to STDOUT
  cat(user_msg, "\n", file = stdout())

  # Build technical message for STDERR
  if (is.null(technical_msg)) {
    technical_msg <- user_msg
  }

  error_msg <- paste0("UNEXPECTED ERROR: ", technical_msg)
  if (!is.null(file)) {
    error_msg <- paste0(error_msg, "\nFile: ", file)
  }

  # Write technical error to STDERR
  message(error_msg)

  # In test environment, use stop() so errors are catchable
  # In production, use quit() to return proper exit code
  if (identical(Sys.getenv("TESTTHAT"), "true")) {
    stop(error_msg, call. = FALSE)
  } else {
    quit(status = EXIT_CODE_UNEXPECTED_ERROR, save = "no")
  }
}

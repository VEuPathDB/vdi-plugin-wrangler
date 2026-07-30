#' Deterministic Count-File Discovery, Validation and Merge
#'
#' Pure file-handling layer for the `rnaseq-rc` datatype: find the uploaded
#' count file(s) and sample-info file, validate them, read counts to long
#' format, and (for stranded uploads) merge the sense/antisense pair.
#'
#' This module has no awareness of the LLM-based sample-annotation step
#' (see `lib/R/llm_client.R`) and must not depend on it.

# Recognised stems (case-insensitive) mapped to their canonical key in the
# `paths` result of `discover_counts_files()`.
.COUNTS_FILE_KEY_FOR_STEM <- c(
  "sense-counts"       = "sense",
  "antisense-counts"   = "antisense",
  "unstranded-counts"  = "unstranded",
  "sample-info"        = "sample_info"
)

#' Maximum accepted size of the sample-info file, in characters
#'
#' `sample-info` is the only unbounded user-supplied input that reaches a
#' paid Claude API call (see `generate_sample_entity()` in
#' `lib/R/sample_annotation.R`), and on the retry path it is interpolated
#' into two separate Sonnet prompts -- so an unbounded sample-info file is a
#' token-spend vector. 100,000 is deliberately generous, not tight: a very
#' long manuscript Methods section (~5,000 words) is around 30,000
#' characters, so this leaves roughly 3x headroom while still capping any
#' single call at roughly 25k input tokens. Do not tighten this -- the point
#' is to stop abuse, not to constrain legitimate uploads.
SAMPLE_INFO_MAX_CHARS <- 100000L

.COUNTS_FILE_ACCEPTED_NAMES_MSG <- paste(
  "Count files must be named sense-counts and antisense-counts, or",
  "unstranded-counts, with a .txt, .tsv or .csv extension. Sample metadata",
  "must be named sample-info with one of the same extensions."
)

#' Discover and classify count-related files in an input directory
#'
#' Looks for `.txt`/`.tsv`/`.csv` files (any case) whose stem (filename minus
#' extension) matches one of `sense-counts`, `antisense-counts`,
#' `unstranded-counts`, or `sample-info`, matched case-insensitively.
#'
#' @param input_dir Path to the directory containing uploaded files
#' @return list(mode = "stranded"|"unstranded", paths = named character vector).
#'   `paths` always contains `sample_info`, plus either `unstranded`, or
#'   both `sense` and `antisense`.
discover_counts_files <- function(input_dir) {
  all_files <- list.files(input_dir, full.names = FALSE)

  data_file_pattern <- "\\.(txt|tsv|csv)$"
  data_files <- all_files[grepl(data_file_pattern, all_files, ignore.case = TRUE)]

  stems <- tolower(sub(data_file_pattern, "", data_files, ignore.case = TRUE))
  known_stems <- names(.COUNTS_FILE_KEY_FOR_STEM)

  unrecognised <- data_files[!stems %in% known_stems]
  if (length(unrecognised) > 0) {
    stop_validation_error(
      user_msg = paste0(
        "Unrecognised file '", unrecognised[1], "'. ", .COUNTS_FILE_ACCEPTED_NAMES_MSG
      ),
      technical_msg = paste(
        "Unrecognised data file(s) in input directory:",
        paste(unrecognised, collapse = ", ")
      ),
      file = input_dir
    )
  }

  recognised_files <- data_files[stems %in% known_stems]
  recognised_keys <- unname(.COUNTS_FILE_KEY_FOR_STEM[stems[stems %in% known_stems]])

  dup_keys <- unique(recognised_keys[duplicated(recognised_keys)])
  if (length(dup_keys) > 0) {
    offending <- recognised_files[recognised_keys %in% dup_keys]
    stop_validation_error(
      user_msg = paste0(
        "More than one file matches the same count-file name: ",
        paste(offending, collapse = ", "),
        ". Please upload only a single file for each count-file type."
      ),
      technical_msg = paste(
        "Multiple files matched the same stem:", paste(offending, collapse = ", ")
      ),
      file = input_dir
    )
  }

  paths <- setNames(file.path(input_dir, recognised_files), recognised_keys)

  if (!"sample_info" %in% names(paths)) {
    stop_validation_error(
      user_msg = paste(
        "No sample-info file found. Please include a sample-info.txt,",
        ".tsv or .csv file describing your samples."
      ),
      technical_msg = paste("No sample-info.* file found in:", input_dir),
      file = input_dir
    )
  }

  sample_info_lines <- readLines(paths[["sample_info"]], warn = FALSE)
  if (length(sample_info_lines) == 0 || all(trimws(sample_info_lines) == "")) {
    stop_validation_error(
      user_msg = paste(
        "Your sample-info file is empty. Please provide sample metadata",
        "describing your samples."
      ),
      technical_msg = paste("Empty sample-info file:", paths[["sample_info"]]),
      file = paths[["sample_info"]]
    )
  }

  # Measured in bytes (`nchar(..., type = "bytes")`), not R's default
  # "chars" count, to stay correct regardless of the sample-info file's
  # encoding -- this repo has explicit Latin-1/UTF-16 encoding tests
  # elsewhere (tests/testthat/isasimple), so a sample-info file can
  # legitimately be non-ASCII, and a naive character count depends on the
  # content's encoding being correctly declared to be meaningful at all. A
  # byte count needs no such assumption. It is also, if anything, a
  # slightly more conservative proxy for actual token cost than a
  # code-point count would be, since multi-byte text tends to cost more
  # tokens per character than ASCII -- never fewer.
  sample_info_text <- paste(sample_info_lines, collapse = "\n")
  sample_info_size <- nchar(sample_info_text, type = "bytes")
  if (sample_info_size > SAMPLE_INFO_MAX_CHARS) {
    stop_validation_error(
      user_msg = paste0(
        "Your sample-info file is too large (", format(sample_info_size, big.mark = ","),
        " characters). Please keep it to at most ",
        format(SAMPLE_INFO_MAX_CHARS, big.mark = ","),
        " characters -- comfortably enough for a full Methods-section ",
        "description of your samples -- by trimming it down to just the ",
        "sample-level metadata needed to group and label your samples."
      ),
      technical_msg = paste0(
        "sample-info file exceeds the ", SAMPLE_INFO_MAX_CHARS,
        "-character cap: ", sample_info_size, " characters in ",
        paths[["sample_info"]]
      ),
      file = paths[["sample_info"]]
    )
  }

  has_sense <- "sense" %in% names(paths)
  has_antisense <- "antisense" %in% names(paths)
  has_unstranded <- "unstranded" %in% names(paths)

  if (has_unstranded && (has_sense || has_antisense)) {
    stop_validation_error(
      user_msg = paste(
        "Your upload contains both unstranded-counts and stranded",
        "(sense-counts/antisense-counts) files. Please upload only one",
        "style of count file."
      ),
      technical_msg = "Both unstranded and stranded count files present.",
      file = input_dir
    )
  }

  if (has_sense && !has_antisense) {
    stop_validation_error(
      user_msg = paste(
        "Found sense-counts but no antisense-counts file. Stranded count",
        "uploads must include both a sense-counts and an antisense-counts file."
      ),
      technical_msg = "sense-counts present without antisense-counts.",
      file = input_dir
    )
  }

  if (has_antisense && !has_sense) {
    stop_validation_error(
      user_msg = paste(
        "Found antisense-counts but no sense-counts file. Stranded count",
        "uploads must include both a sense-counts and an antisense-counts file."
      ),
      technical_msg = "antisense-counts present without sense-counts.",
      file = input_dir
    )
  }

  if (!has_unstranded && !has_sense) {
    stop_validation_error(
      user_msg = paste(
        "No count file found in your upload. Please include either an",
        "unstranded-counts file, or a sense-counts/antisense-counts pair,",
        "with a .txt, .tsv or .csv extension."
      ),
      technical_msg = paste("No recognised count file found in:", input_dir),
      file = input_dir
    )
  }

  mode <- if (has_unstranded) "unstranded" else "stranded"
  list(mode = mode, paths = paths)
}

#' Read a sample-info file as a single whole-file string
#'
#' @param path Path to the sample-info file
#' @return length-1 character vector containing the whole file, with
#'   newlines preserved between lines
read_sample_info_text <- function(path) {
  lines <- readLines(path, warn = FALSE)
  paste(lines, collapse = "\n")
}

#' Detect the delimiter used by a counts file
#'
#' Reads the first line only: if it contains a tab, the file is tab-delimited,
#' otherwise comma-delimited.
#'
#' @param path Path to the counts file
#' @return "\t" or ","
.detect_counts_delimiter <- function(path) {
  first_line <- readLines(path, n = 1, warn = FALSE)
  if (grepl("\t", first_line, fixed = TRUE)) "\t" else ","
}

#' Read a counts file to long format
#'
#' Column 1 is treated as the gene ID by position (regardless of its header,
#' since production HTSeq files have an empty first header cell). Rows whose
#' gene ID starts with `__` (HTSeq summary rows such as `__no_feature`) are
#' dropped before validation. Remaining data is validated (at least one
#' sample column, at least one gene row, no duplicate gene IDs, every count
#' cell an unsigned integer) and then reshaped straight to long format.
#'
#' @param path Path to a sense-counts, antisense-counts or unstranded-counts file
#' @return tibble with columns `Gene` (chr), `sample.ID` (chr), `Count` (int)
read_counts_long <- function(path) {
  delim <- .detect_counts_delimiter(path)

  # na = character(0): readr's `na` matching (default c("", "NA")) happens
  # on the raw strings *before* type conversion, so it would silently turn
  # blank cells and literal "NA" text into real NA even with an all-character
  # col_types. We want those cells to survive verbatim so our own validation
  # (below) can reject them with a helpful message.
  #
  # Muffle only "vroom_parse_issue": a row with fewer fields than the header
  # (e.g. a trailing count accidentally deleted) makes readr emit this
  # specific warning class, advising the caller to call problems(dat) -- of
  # no use here since dat is never returned to the caller. readr still fills
  # the short row's missing cell with "", which our own validation below
  # rejects with a specific, actionable message naming the offending gene and
  # sample. Deliberately narrow (vs. suppressWarnings()) so any other warning
  # class -- e.g. from a future readr version, or from loosening col_types
  # away from all-character -- still propagates instead of being silently
  # dropped.
  raw <- withCallingHandlers(
    readr::read_delim(
      path,
      delim = delim,
      col_types = readr::cols(.default = "c"),
      name_repair = "minimal",
      trim_ws = FALSE,
      na = character(0)
    ),
    vroom_parse_issue = function(w) invokeRestart("muffleWarning")
  )

  if (ncol(raw) < 1) {
    stop_validation_error(
      user_msg = "Your counts file could not be read. Please check it is a valid tab- or comma-delimited file.",
      technical_msg = paste("No columns read from:", path),
      file = path
    )
  }

  names(raw)[1] <- "Gene"
  raw <- raw[!startsWith(raw$Gene, "__"), , drop = FALSE]

  sample_cols <- setdiff(names(raw), "Gene")
  if (length(sample_cols) == 0) {
    stop_validation_error(
      user_msg = "Your counts file has no sample columns. It must contain a gene ID column plus at least one sample column of counts.",
      technical_msg = paste("No sample columns found in:", path),
      file = path
    )
  }

  if (nrow(raw) == 0) {
    stop_validation_error(
      user_msg = "Your counts file has no gene rows. It must contain at least one row of counts.",
      technical_msg = paste("No gene rows remaining (after dropping '__' rows) in:", path),
      file = path
    )
  }

  if (any(duplicated(raw$Gene))) {
    dupes <- unique(raw$Gene[duplicated(raw$Gene)])
    stop_validation_error(
      user_msg = paste0(
        "Your counts file contains duplicate gene IDs (e.g. '", dupes[1],
        "'). Each gene must appear on exactly one row."
      ),
      technical_msg = paste("Duplicate Gene values in:", path, "-", paste(dupes, collapse = ", ")),
      file = path
    )
  }

  # Work with a plain vector (column-major, matching as.matrix()'s layout)
  # rather than relying on trimws()/grepl() preserving matrix dim attributes.
  count_matrix <- as.matrix(raw[, sample_cols, drop = FALSE])
  n_row <- nrow(count_matrix)
  trimmed_vec <- trimws(as.vector(count_matrix))
  valid_vec <- grepl("^\\d+$", trimmed_vec)
  if (!all(valid_vec)) {
    bad_pos <- which(!valid_vec)[1]
    bad_row <- ((bad_pos - 1) %% n_row) + 1
    bad_col_idx <- ((bad_pos - 1) %/% n_row) + 1
    bad_col <- sample_cols[bad_col_idx]
    bad_value <- count_matrix[bad_row, bad_col_idx]
    stop_validation_error(
      user_msg = paste0(
        "Your counts file contains a non-count value ('", bad_value, "' in sample '",
        bad_col, "', gene '", raw$Gene[bad_row], "'). ",
        "Every count must be a whole, non-negative number with no thousands separators."
      ),
      technical_msg = paste0(
        "Invalid count value '", bad_value, "' at gene '", raw$Gene[bad_row],
        "', sample '", bad_col, "' in: ", path
      ),
      file = path
    )
  }

  long <- tidyr::pivot_longer(raw, -Gene, names_to = "sample.ID", values_to = "Count")
  long$Count <- as.integer(trimws(long$Count))
  long
}

#' Read and merge the discovered counts file(s) into a single tibble
#'
#' Unstranded uploads are simply read to long format. Stranded uploads have
#' their sense and antisense files each read to long format and then merged
#' with a `full_join` (rather than an `inner_join`), followed by an assertion
#' that no row is missing from either side — a mismatched sample or gene set
#' therefore fails loudly instead of being silently dropped.
#'
#' @param discovered Result of `discover_counts_files()`
#' @return tibble. Unstranded: `Gene`, `sample.ID`, `Count`. Stranded: `Gene`,
#'   `sample.ID`, `Sense.Count`, `Antisense.Count`.
read_and_merge_counts <- function(discovered) {
  if (discovered$mode == "unstranded") {
    return(read_counts_long(discovered$paths[["unstranded"]]))
  }

  sense <- read_counts_long(discovered$paths[["sense"]])
  antisense <- read_counts_long(discovered$paths[["antisense"]])

  merged <- dplyr::full_join(
    dplyr::rename(sense, Sense.Count = Count),
    dplyr::rename(antisense, Antisense.Count = Count),
    by = c("Gene", "sample.ID")
  )

  if (any(is.na(merged$Sense.Count)) || any(is.na(merged$Antisense.Count))) {
    missing_sense <- length(unique(merged$sample.ID[is.na(merged$Sense.Count)]))
    missing_antisense <- length(unique(merged$sample.ID[is.na(merged$Antisense.Count)]))
    if (!setequal(unique(sense$sample.ID), unique(antisense$sample.ID))) {
      stop_validation_error(
        user_msg = paste(
          "Your sense-counts and antisense-counts files do not have the same",
          "sample columns. Both files must contain the exact same set of samples."
        ),
        technical_msg = paste(
          "Sample mismatch between sense and antisense counts files.",
          "sense samples missing from antisense:", missing_antisense,
          "; antisense samples missing from sense:", missing_sense
        ),
        file = paste(discovered$paths[["sense"]], discovered$paths[["antisense"]], sep = ", ")
      )
    }
    stop_validation_error(
      user_msg = paste(
        "Your sense-counts and antisense-counts files do not describe the",
        "same set of genes. Both files must contain the exact same gene IDs."
      ),
      technical_msg = "Gene mismatch between sense and antisense counts files: differing gene sets.",
      file = paste(discovered$paths[["sense"]], discovered$paths[["antisense"]], sep = ", ")
    )
  }

  merged
}

#' The authoritative set of sample IDs present in merged counts
#'
#' @param merged Result of `read_and_merge_counts()`
#' @return sorted unique character vector of sample IDs
counts_sample_ids <- function(merged) {
  sort(unique(merged$sample.ID))
}

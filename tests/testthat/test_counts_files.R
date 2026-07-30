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

# Encodes a UTF-8 R string as raw bytes in `encoding` (e.g. "CP1252",
# "ISO-8859-1", "UTF-16LE"), for building non-UTF-8 fixtures byte-for-byte
# without depending on the test process's own native encoding.
encode_as <- function(text, encoding) {
  iconv(text, from = "UTF-8", to = encoding, toRaw = TRUE)[[1]]
}

# Like make_input(), but writes raw bytes -- needed for non-UTF-8 fixtures,
# since writeLines() always writes in the process's native encoding.
make_input_bytes <- function(files_raw) {
  d <- tempfile("counts_bytes_"); dir.create(d)
  for (nm in names(files_raw)) writeBin(files_raw[[nm]], file.path(d, nm))
  d
}

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

test_that("a sample-info file just under the size cap is accepted", {
  # Regression test for finding 4: sample-info is the only unbounded
  # user-supplied input that reaches a paid Claude API call (see
  # generate_sample_entity() in lib/R/sample_annotation.R), so it is capped
  # at discovery time -- before any billable call -- rather than left
  # unbounded. Deliberately runtime-generated (strrep()) rather than a
  # checked-in ~100KB fixture file.
  big <- strrep("a", SAMPLE_INFO_MAX_CHARS - 1)
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sample-info.txt" = big))
  got <- discover_counts_files(d)
  expect_setequal(names(got$paths), c("unstranded", "sample_info"))
})

test_that("a sample-info file over the size cap is rejected, naming the limit", {
  too_big <- strrep("a", SAMPLE_INFO_MAX_CHARS + 1)
  d <- make_input(list("unstranded-counts.tsv" = TSV_OK, "sample-info.txt" = too_big))
  out <- capture.output(testthat::expect_error(discover_counts_files(d), "exceeds"))
  stdout_text <- paste(out, collapse = "\n")
  expect_match(stdout_text, "too large", fixed = TRUE)
  expect_match(stdout_text, format(SAMPLE_INFO_MAX_CHARS, big.mark = ","), fixed = TRUE)
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

# --- Task 10: encoding policy parity ---------------------------------------
#
# read_counts_long() used to call readr::read_delim() with no `locale`,
# silently assuming UTF-8 -- unlike phenotype/stf/isasimple, which get
# study.wrangler's detect_file_encoding() threaded through for free via
# entity_from_file()/entity_from_stf(). These pin that the same non-UTF-8
# bytes that already pass as those datatypes now also pass here.

test_that("an ISO-8859-1 counts file decodes non-ASCII gene IDs", {
  text <- "geneID\tS1\tS2\ngene_ü\t10\t20\ngene_é\t1\t2\n"
  d <- make_input_bytes(list(
    "unstranded-counts.tsv" = encode_as(text, "ISO-8859-1")
  ))
  got <- read_counts_long(file.path(d, "unstranded-counts.tsv"))
  expect_setequal(got$Gene, c("gene_ü", "gene_é"))
})

test_that("a Windows-1252 counts file decodes non-ASCII gene IDs", {
  # euro sign (0x80) is Windows-1252-specific -- undefined in ISO-8859-1 --
  # so this also pins that detect_file_encoding() tells the two apart.
  text <- "geneID\tS1\tS2\ngene_ü\t10\t20\ngene_€\t1\t2\n"
  d <- make_input_bytes(list(
    "unstranded-counts.tsv" = encode_as(text, "CP1252")
  ))
  got <- read_counts_long(file.path(d, "unstranded-counts.tsv"))
  expect_setequal(got$Gene, c("gene_ü", "gene_€"))
})

test_that("a UTF-16 counts file (BOM, alternating NULs) decodes non-ASCII gene IDs", {
  # Regression test: .detect_counts_delimiter() used to read the raw,
  # undecoded bytes to sniff the delimiter. For UTF-16 those bytes don't
  # contain a lone tab byte -- each ASCII byte is interleaved with a NUL --
  # so the sniff silently misdetected comma and the whole parse fell apart
  # further downstream. Greek letters (outside Windows-1252/ISO-8859-1)
  # prove genuine Unicode decoding, not just a Latin-1 special case.
  text <- "geneID\tS1\tS2\ngene_β\t10\t20\ngene_Ω\t1\t2\n"
  # Prepend a UTF-16LE BOM so detect_file_encoding() takes the BOM branch
  # (encode_as() alone doesn't add one).
  utf16_bytes <- c(as.raw(c(0xFF, 0xFE)), encode_as(text, "UTF-16LE"))
  d <- make_input_bytes(list("unstranded-counts.tsv" = utf16_bytes))

  got <- read_counts_long(file.path(d, "unstranded-counts.tsv"))
  expect_setequal(got$Gene, c("gene_β", "gene_Ω"))
})

test_that("read_sample_info_text transcodes Windows-1252 to genuine UTF-8", {
  text <- "sample\tnotes\nS1\tCollected by Müller lab\n"
  d <- make_input_bytes(list("sample-info.txt" = encode_as(text, "CP1252")))
  got <- read_sample_info_text(file.path(d, "sample-info.txt"))
  expect_equal(Encoding(got), "UTF-8")
  expect_true(validEnc(got))
  expect_match(got, "Müller", fixed = TRUE)
})

test_that("read_sample_info_text transcodes UTF-16 to genuine UTF-8", {
  text <- "sample\tnotes\nS1\tCollected by Müller lab\n"
  raw <- encode_as(text, "UTF-16LE")
  d <- make_input_bytes(list("sample-info.txt" = c(as.raw(c(0xFF, 0xFE)), raw)))
  got <- read_sample_info_text(file.path(d, "sample-info.txt"))
  expect_equal(Encoding(got), "UTF-8")
  expect_true(validEnc(got))
  expect_match(got, "Müller", fixed = TRUE)
})

test_that("a transcoded sample-info string survives jsonlite::toJSON verbatim", {
  # Direct proof of the final review's Minor 7: this is exactly what
  # llm_text() (lib/R/llm_client.R) does with the annotation prompt before
  # POSTing it. Before the fix, read_sample_info_text() left this string's
  # encoding as "unknown" over genuinely non-UTF-8 bytes; jsonlite::toJSON()
  # then embedded the raw invalid bytes verbatim as mojibake instead of the
  # real character. Round-tripping through toJSON()/fromJSON() here proves
  # the fixed text survives with the accented character intact, not just
  # that toJSON() doesn't throw.
  text <- "sample\tnotes\nS1\tCollected by Müller lab\n"
  d <- make_input_bytes(list("sample-info.txt" = encode_as(text, "CP1252")))
  got <- read_sample_info_text(file.path(d, "sample-info.txt"))

  body <- list(model = "m", messages = list(list(role = "user", content = got)))
  j <- jsonlite::toJSON(body, auto_unbox = TRUE)
  round_tripped <- jsonlite::fromJSON(j, simplifyVector = FALSE)
  expect_match(round_tripped$messages[[1]]$content, "Müller", fixed = TRUE)
})

test_that("a non-UTF-8 sample-info file does not crash the emptiness check", {
  # Regression test: discover_counts_files() used to check for a blank
  # sample-info file with trimws(sample_info_lines) == "", on the raw,
  # not-yet-decoded bytes. trimws() hard-errors ("input string N is invalid
  # UTF-8") on genuinely non-UTF-8 bytes, rather than just failing the
  # validation check -- an uncaught R error, not a user-facing message. This
  # pins that a non-empty Windows-1252 sample-info file is discovered
  # cleanly instead of crashing before read_sample_info_text() ever runs.
  text <- "sample\tnotes\nS1\tCollected by Müller lab\n"
  d <- make_input_bytes(list(
    "unstranded-counts.tsv" = charToRaw(paste(TSV_OK, collapse = "\n")),
    "sample-info.txt" = encode_as(text, "CP1252")
  ))
  got <- discover_counts_files(d)
  expect_setequal(names(got$paths), c("unstranded", "sample_info"))
})

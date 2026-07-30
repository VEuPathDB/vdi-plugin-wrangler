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

# Writes a manifest for the given role -> filename pairs, matching the
# contract: no header, role<TAB>filename, LF, trailing newline. writeLines()
# gives LF endings and a trailing newline by default, which is what the
# contract requires. Duplicate names are allowed here on purpose -- passing
# the same role twice (e.g. write_manifest(d, "sense" = "a.tsv", "sense" =
# "b.tsv")) is exactly how the duplicate-role test below builds its fixture.
write_manifest <- function(dir, ...) {
  entries <- c(...)
  writeLines(
    paste(names(entries), unname(entries), sep = "\t"),
    file.path(dir, "manifest.tsv")
  )
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
  # Deliberately off the old canonical stem ("unstranded-counts.tsv"): if a
  # leftover stem-matching path ever came back, this would fail instead of
  # silently keeping the suite green.
  d <- make_input(list("HTSeq_run3.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "unstranded" = "HTSeq_run3.tsv", "sample-info" = "sample-info.txt")
  got <- discover_counts_files(d)
  expect_equal(got$mode, "unstranded")
  expect_setequal(names(got$paths), c("unstranded", "sample_info"))
  expect_equal(basename(got$paths[["unstranded"]]), "HTSeq_run3.tsv")
})

test_that("stranded pair is discovered", {
  d <- make_input(list("my_sense.tsv" = TSV_OK, "my_antisense.tsv" = TSV_OK,
                       "sample-info.txt" = INFO_OK))
  write_manifest(d, "sense" = "my_sense.tsv", "antisense" = "my_antisense.tsv",
                 "sample-info" = "sample-info.txt")
  got <- discover_counts_files(d)
  expect_equal(got$mode, "stranded")
  expect_setequal(names(got$paths), c("sense", "antisense", "sample_info"))
  expect_equal(basename(got$paths[["sense"]]), "my_sense.tsv")
  expect_equal(basename(got$paths[["antisense"]]), "my_antisense.tsv")
})

test_that("sample-info text is returned whole", {
  d <- make_input(list("my_counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "unstranded" = "my_counts.tsv", "sample-info" = "sample-info.txt")
  got <- discover_counts_files(d)
  txt <- read_sample_info_text(got$paths[["sample_info"]])
  expect_length(txt, 1)
  expect_match(txt, "infected")
  expect_match(txt, "\n")
})

test_that("sense without antisense is rejected", {
  d <- make_input(list("my_sense.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "sense" = "my_sense.tsv", "sample-info" = "sample-info.txt")
  expect_error(discover_counts_files(d), "without antisense")
})

test_that("antisense without sense is rejected", {
  d <- make_input(list("my_antisense.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "antisense" = "my_antisense.tsv", "sample-info" = "sample-info.txt")
  expect_error(discover_counts_files(d), "without sense")
})

test_that("unstranded alongside stranded is rejected", {
  d <- make_input(list("my_uns.tsv" = TSV_OK, "my_sense.tsv" = TSV_OK,
                       "my_antisense.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "unstranded" = "my_uns.tsv", "sense" = "my_sense.tsv",
                 "antisense" = "my_antisense.tsv", "sample-info" = "sample-info.txt")
  expect_error(discover_counts_files(d), "unstranded and stranded")
})

test_that("no count file at all is rejected", {
  d <- make_input(list("sample-info.txt" = INFO_OK))
  write_manifest(d, "sample-info" = "sample-info.txt")
  expect_error(discover_counts_files(d), "No unstranded or sense/antisense")
})

test_that("missing sample-info is rejected", {
  d <- make_input(list("my_counts.tsv" = TSV_OK))
  write_manifest(d, "unstranded" = "my_counts.tsv")
  expect_error(discover_counts_files(d), "sample-info")
})

test_that("empty sample-info is rejected", {
  d <- make_input(list("my_counts.tsv" = TSV_OK, "sample-info.txt" = character(0)))
  write_manifest(d, "unstranded" = "my_counts.tsv", "sample-info" = "sample-info.txt")
  expect_error(discover_counts_files(d), "sample-info")
})

test_that("a sample-info file just under the size cap is accepted", {
  # Regression test for finding 4: sample-info is the only unbounded
  # user-supplied input that reaches a paid Claude API call (see
  # generate_sample_entity() in lib/R/sample_annotation.R), so it is capped
  # at discovery time -- before any billable call -- rather than left
  # unbounded. Deliberately runtime-generated (strrep()) rather than a
  # checked-in ~100KB fixture file.
  big <- strrep("a", SAMPLE_INFO_MAX_BYTES - 1)
  d <- make_input(list("my_counts.tsv" = TSV_OK, "sample-info.txt" = big))
  write_manifest(d, "unstranded" = "my_counts.tsv", "sample-info" = "sample-info.txt")
  got <- discover_counts_files(d)
  expect_setequal(names(got$paths), c("unstranded", "sample_info"))
})

test_that("a sample-info file over the size cap is rejected, naming the limit", {
  too_big <- strrep("a", SAMPLE_INFO_MAX_BYTES + 1)
  d <- make_input(list("my_counts.tsv" = TSV_OK, "sample-info.txt" = too_big))
  write_manifest(d, "unstranded" = "my_counts.tsv", "sample-info" = "sample-info.txt")
  out <- capture.output(testthat::expect_error(discover_counts_files(d), "exceeds"))
  stdout_text <- paste(out, collapse = "\n")
  expect_match(stdout_text, "too large", fixed = TRUE)
  expect_match(stdout_text, format(SAMPLE_INFO_MAX_BYTES, big.mark = ","), fixed = TRUE)
})

test_that("an unreferenced extra file is rejected", {
  # Premise change from the pre-manifest suite: this test used to assert
  # that a file named "counts.tsv" was rejected for having an unrecognised
  # name. Under the manifest scheme a file called counts.tsv is perfectly
  # valid *if the manifest lists it* -- filenames no longer carry meaning.
  # What's actually rejected now is a data file the manifest doesn't
  # mention at all, regardless of what it's called.
  d <- make_input(list("my_counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK,
                       "extra_stray.tsv" = TSV_OK))
  write_manifest(d, "unstranded" = "my_counts.tsv", "sample-info" = "sample-info.txt")
  expect_error(discover_counts_files(d), "not listed in the manifest")
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
    "my_sense.tsv"     = c("geneID\tS1\tS2", "g1\t10\t20", "g2\t1\t2"),
    "my_antisense.tsv" = c("geneID\tS1\tS2", "g1\t3\t4",   "g2\t5\t6"),
    "sample-info.txt" = INFO_OK
  ))
  write_manifest(d, "sense" = "my_sense.tsv", "antisense" = "my_antisense.tsv",
                 "sample-info" = "sample-info.txt")
  merged <- read_and_merge_counts(discover_counts_files(d))
  expect_named(merged, c("Gene", "sample.ID", "Sense.Count", "Antisense.Count"))
  expect_equal(nrow(merged), 4)
  expect_equal(counts_sample_ids(merged), c("S1", "S2"))
})

test_that("mismatched sample columns are rejected", {
  d <- make_input(list(
    "my_sense.tsv"     = c("geneID\tS1\tS2", "g1\t10\t20"),
    "my_antisense.tsv" = c("geneID\tS1",     "g1\t3"),
    "sample-info.txt" = INFO_OK
  ))
  write_manifest(d, "sense" = "my_sense.tsv", "antisense" = "my_antisense.tsv",
                 "sample-info" = "sample-info.txt")
  expect_error(read_and_merge_counts(discover_counts_files(d)), "sample")
})

test_that("mismatched gene sets are rejected", {
  d <- make_input(list(
    "my_sense.tsv"     = c("geneID\tS1", "g1\t10", "g2\t1"),
    "my_antisense.tsv" = c("geneID\tS1", "g1\t3"),
    "sample-info.txt" = INFO_OK
  ))
  write_manifest(d, "sense" = "my_sense.tsv", "antisense" = "my_antisense.tsv",
                 "sample-info" = "sample-info.txt")
  expect_error(read_and_merge_counts(discover_counts_files(d)), "gene")
})

test_that("unstranded merge keeps a single Count column", {
  d <- make_input(list("my_counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "unstranded" = "my_counts.tsv", "sample-info" = "sample-info.txt")
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
    "my_counts.tsv" = charToRaw(paste(TSV_OK, collapse = "\n")),
    "sample-info.txt" = encode_as(text, "CP1252")
  ))
  write_manifest(d, "unstranded" = "my_counts.tsv", "sample-info" = "sample-info.txt")
  got <- discover_counts_files(d)
  expect_setequal(names(got$paths), c("unstranded", "sample_info"))
})

# --- Task 3: manifest-driven discovery and its failure modes ---------------
#
# discover_counts_files() now requires a manifest.tsv declaring each file's
# role instead of matching fixed filename stems, so uploaded files keep their
# original names. Every manifest structural fault below shares one identical
# user_msg (a generic "contact the helpdesk" message written to stdout via
# cat()) -- see .MANIFEST_FAULT_USER_MSG in counts_files.R -- so the
# discriminating assertion has to be on technical_msg, i.e. a plain
# expect_error() regex, not the captured stdout.

test_that("rejects a missing manifest", {
  d <- make_input(list("my_counts.tsv" = TSV_OK))
  expect_error(discover_counts_files(d), "No manifest.tsv")
})

test_that("rejects a manifest line with no tab", {
  d <- make_input(list("my_counts.tsv" = TSV_OK))
  writeLines("unstranded my_counts.tsv", file.path(d, "manifest.tsv"))
  expect_error(discover_counts_files(d), "no tab separator")
})

test_that("rejects an unknown role", {
  d <- make_input(list("my_counts.tsv" = TSV_OK, "si.txt" = INFO_OK))
  write_manifest(d, "spliced" = "my_counts.tsv", "sample-info" = "si.txt")
  expect_error(discover_counts_files(d), "unknown role")
})

test_that("rejects a duplicate role", {
  d <- make_input(list("a.tsv" = TSV_OK, "b.tsv" = TSV_OK))
  write_manifest(d, "sense" = "a.tsv", "sense" = "b.tsv")
  expect_error(discover_counts_files(d), "duplicate role")
})

test_that("rejects a dangling manifest reference", {
  d <- make_input(list("sample-info.txt" = INFO_OK))
  write_manifest(d, "unstranded" = "absent.tsv", "sample-info" = "sample-info.txt")
  expect_error(discover_counts_files(d), "not present")
})

test_that("accepts a filename containing spaces", {
  # This is the case a naive strsplit(line, "\\s+") would break: splitting
  # the manifest line on the FIRST tab only, rather than on whitespace, is
  # exactly what makes spaces in filenames safe.
  d <- make_input(list("my counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "unstranded" = "my counts.tsv", "sample-info" = "sample-info.txt")
  got <- discover_counts_files(d)
  expect_equal(basename(got$paths[["unstranded"]]), "my counts.tsv")
})

test_that("a .tab extension is accepted", {
  # ".tab" is newly accepted alongside .txt/.tsv/.csv.
  d <- make_input(list("my_counts.tab" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "unstranded" = "my_counts.tab", "sample-info" = "sample-info.txt")
  got <- discover_counts_files(d)
  expect_equal(basename(got$paths[["unstranded"]]), "my_counts.tab")
})

test_that("a manifest line ending in a tab (empty filename) is rejected", {
  d <- make_input(list("my_counts.tsv" = TSV_OK))
  writeLines("unstranded\t", file.path(d, "manifest.tsv"))
  expect_error(discover_counts_files(d), "empty filename")
})

test_that("the same file listed under two roles is rejected", {
  # Left undetected, this would silently produce a study where
  # Sense.Count == Antisense.Count on every row -- a real
  # scientific-correctness failure, not merely a cosmetic one.
  d <- make_input(list("counts.tsv" = TSV_OK, "sample-info.txt" = INFO_OK))
  write_manifest(d, "sense" = "counts.tsv", "antisense" = "counts.tsv",
                 "sample-info" = "sample-info.txt")
  expect_error(discover_counts_files(d), "more than one role")
})

test_that("a manifest containing invalid UTF-8 fails cleanly, not with a crash", {
  # Regression test for a Task 2 review finding: without the explicit
  # validUTF8() guard in .parse_manifest(), an invalid byte here degrades
  # regexpr(..., fixed = TRUE) silently to -1 (misreported as "no tab
  # separator"), or makes nchar() hard-error outright -- an uncaught R abort,
  # not a validation error. A manifest is UTF-8 by contract (we generate it),
  # so invalid bytes indicate a structural fault, not a content fault. Built
  # with writeBin(), since a Latin-1 0xE9 byte can't be produced by
  # writeLines() writing in the process's native encoding.
  bad_line <- c(charToRaw("unstranded\tHTSeq_run"), as.raw(0xE9), charToRaw(".tsv\n"))
  d <- make_input_bytes(list("manifest.tsv" = bad_line))
  expect_error(discover_counts_files(d), "invalid UTF-8")
})

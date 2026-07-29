#' Sample Annotation Generation, Validation Gates and DESeq-Suitability Check
#'
#' This is the only LLM-dependent step in the `rnaseq-rc` pipeline: it turns
#' the authoritative union of sample IDs (from the count files, deterministic
#' -- see `lib/R/counts_files.R`) plus a free-form sample-metadata file (a
#' table, a transposed table, prose, or an article methods paragraph) into a
#' validated `sample` Entity, via a one-shot Claude prompt with a single
#' retry.
#'
#' Depends on `lib/R/llm_client.R` (the transport + mock layer) and
#' `lib/R/annotations_to_stf.R` (the JSON-to-STF conversion). This file must
#' not reimplement anything from either.

#' Classify a set of sample IDs as informative or uninformative
#'
#' Some sample IDs already encode useful metadata (e.g. `male_3h_rep1`);
#' others are opaque codes (e.g. `S001`) that require an explicit mapping in
#' the sample-info file. Whether a set of IDs is informative can't be
#' determined reliably without semantic interpretation, so this delegates to
#' a small, cheap model.
#'
#' Any reply other than the literal string `"labels_informative"` is treated
#' as `"labels_uninformative"` -- the safe direction, since it is the one
#' that demands an explicit ID-to-metadata mapping be checked for.
#'
#' @param sample_ids character vector of sample IDs from the count files
#' @return `"labels_informative"` or `"labels_uninformative"`
classify_sample_ids <- function(sample_ids) {
  system_prompt <- paste(
    "You classify bulk RNA-seq sample identifiers for an automated data",
    "pipeline. Reply with exactly one word: labels_informative or",
    "labels_uninformative. No other text."
  )

  user_prompt <- paste0(
    "Here are the sample IDs from a bulk RNA-seq count file:\n\n",
    paste(sample_ids, collapse = ", "),
    "\n\n",
    "Do these IDs, by themselves, already encode meaningful experimental ",
    "information (for example genotype, treatment, tissue, timepoint, or ",
    "replicate structure), such that a human could group and label samples ",
    "from the IDs alone? Answer labels_informative if so. Answer ",
    "labels_uninformative if the IDs are opaque codes, accession numbers, or ",
    "serial numbers that carry no interpretable meaning on their own and ",
    "would require an explicit mapping to metadata elsewhere."
  )

  reply <- trimws(llm_text(
    "classify_labels",
    model = "claude-haiku-4-5-20251001",
    system_prompt = system_prompt,
    user_prompt = user_prompt
  ))

  if (identical(reply, "labels_informative")) {
    "labels_informative"
  } else {
    "labels_uninformative"
  }
}

#' Check that every sample ID appears somewhere in the sample-info text
#'
#' Deterministic check used when `classify_sample_ids()` decides the sample
#' IDs are opaque: in that case the sample-info file must explicitly mention
#' every one of them, or there is nothing for the annotation step to anchor
#' on.
#'
#' @param sample_ids character vector of authoritative sample IDs
#' @param sample_info_text the whole sample-info file, as one string
#' @return invisible `TRUE`, or `stop_validation_error()` naming the missing IDs
check_ids_present_in_sample_info <- function(sample_ids, sample_info_text) {
  present <- vapply(
    sample_ids,
    function(id) grepl(id, sample_info_text, fixed = TRUE),
    logical(1)
  )
  missing <- sample_ids[!present]

  if (length(missing) > 0) {
    stop_validation_error(
      user_msg = paste0(
        "Your sample-info file does not mention the following sample ID(s) ",
        "found in your count files: ", paste(missing, collapse = ", "),
        ". Because these IDs do not appear informative on their own, please ",
        "make sure every sample ID is explicitly mentioned in your sample ",
        "metadata."
      ),
      technical_msg = paste(
        "Sample ID(s) present in count files but absent from sample-info text:",
        paste(missing, collapse = ", ")
      )
    )
  }

  invisible(TRUE)
}

#' Build the prompt used to generate (or correct) the sample annotation JSON
#'
#' Ported from `dataset-curator`'s
#' `skills/curate-bulk-rnaseq/resources/step-2-analyze-samples.md`, trimmed
#' to what this pipeline needs: no `runs`/technical-replicate grouping (the
#' count files already fix the sample IDs), no `bioproject`/`strandedness`
#' (out of scope for this step).
#'
#' @param sample_ids character vector of authoritative sample IDs -- the
#'   model must use these values verbatim as `sampleId`
#' @param sample_info_text the whole sample-info file, as one string
#' @param previous_errors optional character scalar: the failure message(s)
#'   from a previous attempt, to be corrected this time
#' @return length-1 character: the user prompt
annotation_prompt <- function(sample_ids, sample_info_text, previous_errors = NULL) {
  id_list <- paste(sample_ids, collapse = ", ")

  correction_section <- ""
  if (!is.null(previous_errors)) {
    correction_section <- paste0(
      "\n\n## Your previous attempt failed\n\n",
      "Your previous response was rejected for the following reason(s):\n\n",
      previous_errors,
      "\n\nCorrect these problems in your new response. In particular, ",
      "double-check that every `sampleId` is copied verbatim from the ",
      "authoritative list below -- do not invent, abbreviate, reorder, or ",
      "reformat any sample ID.\n"
    )
  }

  paste0(
    "You are preparing a sample-annotation file for a bulk RNA-seq dataset. ",
    "You are given (1) the authoritative list of sample IDs taken from the ",
    "uploaded count files, and (2) a free-form sample-metadata file supplied ",
    "by the person who uploaded the data. That metadata file may be a ",
    "horizontal or transposed (vertical) table, in TSV or CSV form, plain ",
    "prose describing the samples, or a methods paragraph copied from an ",
    "article. Your job is to turn it into structured JSON describing each ",
    "sample and the experimental factors that distinguish them.\n\n",
    "## Authoritative sample IDs\n\n",
    "Every sample below must appear exactly once in your `samples` array, ",
    "and every `sampleId` value must be copied **verbatim** from this list ",
    "(same spelling, same case, same punctuation). Do not invent new IDs, ",
    "and do not omit any of these:\n\n",
    id_list,
    "\n\n## Supplied sample metadata\n\n",
    sample_info_text,
    "\n\n## Step 1: Identify experimental factors\n\n",
    "Examine the supplied metadata to find attributes that (a) have ",
    "different values across samples, and (b) are biologically meaningful. ",
    "Include factors such as infection, treatment, condition, tissue, ",
    "cell_type, genotype, strain, timepoint, age, developmental_stage, and ",
    "sex. Exclude purely technical metadata such as file names, run/lane ",
    "identifiers, sequencing instrument, or upload timestamps. An attribute ",
    "that has the same value for every sample is not a factor and must not ",
    "appear in `factors` or in any sample's `factors` object.\n\n",
    "## Step 2: Write factor definitions\n\n",
    "For each factor, populate:\n\n",
    "- `displayName` (required): a short, human-readable label. Lowercase ",
    "preferred. As a default, replace underscores with spaces (e.g. ",
    "`developmental_stage` -> \"developmental stage\").\n",
    "- `definition` (required): a short noun-phrase (at most 80 characters, ",
    "no trailing period) describing what the factor measures, written for a ",
    "biologist. Do not just repeat the key name, and do not write a generic ",
    "catch-all like \"sample condition\".\n",
    "- `unit` (optional): include only when factor values are measurements ",
    "(e.g. \"24h\", \"7 days\", \"0.5 mg/kg\"). Use a singular, non-abbreviated, ",
    "SI-friendly, US-spelled unit name such as \"hour\", \"day\", \"microgram\", ",
    "or \"millimolar\" -- never abbreviations like \"h\", \"hrs\", or \"mM\". For ",
    "factors that count discrete things (organisms, cells, colonies), use ",
    "\"count\". Omit `unit` entirely for categorical values such as ",
    "\"infected\", \"liver\", or \"wild-type\".\n\n",
    "**Strip units from values**: whenever a factor has a `unit`, remove the ",
    "unit suffix from every occurrence of that factor's value in `samples[].",
    "factors` -- the unit is already captured once, formally, in the factor ",
    "definition. For example, with `unit: \"hour\"`, a raw value of \"24h\" ",
    "becomes \"24\", and \"48 hours\" becomes \"48\".\n\n",
    "## Step 3: Write each sample's label and factors\n\n",
    "For every authoritative sample ID, produce one entry in `samples` with:\n\n",
    "- `sampleId`: copied verbatim from the authoritative list above.\n",
    "- `label`: a short, human-readable label suitable for a graph axis, ",
    "combining only the factor values that vary (e.g. \"Infected - 24h\"). ",
    "**Never include replicate numbers in a label** -- biological replicates ",
    "of the same condition must share the same label.\n",
    "- `factors`: an object mapping each factor key to that sample's ",
    "(unit-stripped) value. Omit a factor entirely for a sample if it does ",
    "not apply.\n\n",
    "## Output format\n\n",
    "Respond with **JSON only** -- no markdown code fence, no commentary, no ",
    "explanation before or after the JSON. The JSON must have exactly this ",
    "shape:\n\n",
    "{\n",
    "  \"profileSetName\": \"Short display name for this dataset\",\n",
    "  \"factors\": {\n",
    "    \"<factor_key>\": {\n",
    "      \"displayName\": \"...\",\n",
    "      \"definition\": \"...\",\n",
    "      \"unit\": \"...\" (optional)\n",
    "    }\n",
    "  },\n",
    "  \"samples\": [\n",
    "    {\n",
    "      \"sampleId\": \"<verbatim from the authoritative list>\",\n",
    "      \"label\": \"...\",\n",
    "      \"factors\": { \"<factor_key>\": \"<value>\" }\n",
    "    }\n",
    "  ]\n",
    "}",
    correction_section
  )
}

#' Write an annotation list to STF, read it back, and run the validation gates
#'
#' Gates, in order:
#'
#' 1. `stop_if_entity_invalid(entity)` -- standard sample-entity validation.
#' 2. Every generated `sample.ID` must be a member of `authoritative_ids`.
#' 3. Every `authoritative_ids` value must be present in the entity.
#'
#' Gates 2 and 3 name the offending IDs: their failure messages are fed back
#' into the retry prompt by `generate_sample_entity()`, so a generic
#' "sample IDs do not match" message would give the model nothing to act on.
#'
#' @param annotations parsed annotation list (see `annotations_to_stf()`)
#' @param authoritative_ids character vector: the union of sample IDs found
#'   in the uploaded count files
#' @return a `sample` Entity, valid and gated against `authoritative_ids`
build_sample_entity <- function(annotations, authoritative_ids) {
  stf_dir <- tempfile("sample_stf_")
  dir.create(stf_dir)

  tsv_path <- annotations_to_stf(annotations, stf_dir)
  entity <- entity_from_stf(tsv_path)

  stop_if_entity_invalid(entity)

  generated_ids <- entity %>% get_data() %>% pull(sample.ID)

  invented <- setdiff(generated_ids, authoritative_ids)
  if (length(invented) > 0) {
    stop(sprintf(
      "The generated sample annotation includes sample ID(s) that are not present in the uploaded count files: %s",
      paste(invented, collapse = ", ")
    ))
  }

  missing <- setdiff(authoritative_ids, generated_ids)
  if (length(missing) > 0) {
    stop(sprintf(
      "The generated sample annotation is missing sample ID(s) that are present in the uploaded count files: %s",
      paste(missing, collapse = ", ")
    ))
  }

  entity %>% set_variable_metadata("label", is_featured = TRUE, display_order = 1)
}

#' Generate a validated sample entity from sample IDs and free-form metadata
#'
#' Calls `llm_json("annotate", ...)` with Sonnet, tries `build_sample_entity()`,
#' and -- if that fails -- retries exactly once with the first attempt's
#' failure message appended to the prompt via `annotation_prompt(...,
#' previous_errors = ...)`. Both attempts are guarded: an error from the
#' retry (including an exhausted mock queue) is caught and reported the same
#' way as an error from the first attempt, rather than propagating as a raw
#' R error.
#'
#' @param sample_ids character vector: the authoritative union of sample IDs
#'   from the uploaded count files
#' @param sample_info_text the whole sample-info file, as one string
#' @return a validated `sample` Entity, or `stop_transformation_error()`
generate_sample_entity <- function(sample_ids, sample_info_text) {
  system_prompt <- paste(
    "You are an expert bioinformatics data curator. You turn free-form",
    "RNA-seq sample metadata into strict JSON sample annotations for an",
    "automated pipeline. You always respond with JSON only."
  )

  attempt_1 <- tryCatch(
    {
      annotations <- llm_json(
        "annotate",
        model = "claude-sonnet-5",
        system_prompt = system_prompt,
        user_prompt = annotation_prompt(sample_ids, sample_info_text)
      )
      build_sample_entity(annotations, sample_ids)
    },
    error = function(e) e
  )

  if (!inherits(attempt_1, "error")) {
    return(attempt_1)
  }

  attempt_2 <- tryCatch(
    {
      annotations <- llm_json(
        "annotate",
        model = "claude-sonnet-5",
        system_prompt = system_prompt,
        user_prompt = annotation_prompt(
          sample_ids, sample_info_text,
          previous_errors = conditionMessage(attempt_1)
        )
      )
      build_sample_entity(annotations, sample_ids)
    },
    error = function(e) e
  )

  if (!inherits(attempt_2, "error")) {
    return(attempt_2)
  }

  many_samples_warning <- ""
  if (length(sample_ids) > 30) {
    many_samples_warning <- sprintf(
      " This dataset contains a lot of samples (%d), which can challenge our AI-based processing.",
      length(sample_ids)
    )
  }

  stop_transformation_error(
    user_msg = paste0(
      "We were unable to automatically generate a valid sample annotation ",
      "from your uploaded sample metadata, even after a second attempt.",
      many_samples_warning
    ),
    technical_msg = paste(
      "First attempt error:", conditionMessage(attempt_1),
      "\nSecond attempt error:", conditionMessage(attempt_2)
    )
  )
}

#' Check whether a validated sample entity supports a differential-expression contrast
#'
#' A sample entity can be perfectly valid STF and still be useless for
#' DESeq: e.g. an annotation carrying only `sample.ID` and `label` (`label`
#' conflates whatever factors vary and cannot itself define a contrast), an
#' all-constant factor, or a single-sample dataset. This check is
#' deliberately not type-aware -- a numeric factor with one sample per value
#' (e.g. `timepoint: 1,2,3,4`) is accepted, since it can still be grouped
#' into a contrast downstream.
#'
#' Suitable iff `n_samples >= 2` and at least one variable other than the ID
#' column and `label` has at least 2 distinct non-missing values.
#'
#' @param entity a `sample` Entity (as returned by `build_sample_entity()`
#'   or `generate_sample_entity()`)
#' @return invisible `TRUE`, or `stop_validation_error()`
check_deseq_suitability <- function(entity) {
  data <- entity %>% get_data()
  n_samples <- nrow(data)

  vars <- entity %>% get_variable_metadata() %>% pull(variable)
  vars <- setdiff(vars, "label")

  has_usable_factor <- any(vapply(vars, function(v) {
    values <- data[[v]]
    values <- values[!is.na(values)]
    length(unique(values)) >= 2
  }, logical(1)))

  if (n_samples >= 2 && has_usable_factor) {
    return(invisible(TRUE))
  }

  stop_validation_error(
    user_msg = paste(
      "Your sample metadata does not define a factor suitable for",
      "differential expression analysis. Besides a sample ID and a display",
      "label, please describe at least one experimental factor (e.g.",
      "treatment, genotype, timepoint, tissue) that takes at least two",
      "different values across at least two samples."
    ),
    technical_msg = sprintf(
      "DESeq-suitability check failed: n_samples = %d, usable factor variables among {%s} = %s",
      n_samples, paste(vars, collapse = ", "), has_usable_factor
    )
  )
}

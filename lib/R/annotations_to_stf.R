#' Annotation JSON to STF Converter
#'
#' Converts an already-parsed sample-annotation list (produced upstream by an
#' LLM from a free-form sample-metadata file, then parsed as JSON) into a
#' study-wrangler STF file pair: `entity-sample.tsv` and `entity-sample.yaml`,
#' ready for `study.wrangler::entity_from_stf()` to read back as a `sample`
#' entity.
#'
#' R port of `dataset-curator`'s
#' `skills/sample-annotations-to-stf/scripts/sample-annotations-to-stf.js`,
#' with two deliberate deviations: the YAML is serialised via
#' `yaml::as.yaml()` rather than string concatenation (the JS emits
#' `display_name: ${value}` unquoted, which breaks on a colon in an
#' LLM-written `definition`), and the `SRA.ID.s.` column is omitted since
#' user uploads have no SRA accessions.
#'
#' This module has no awareness of the LLM step (see `lib/R/llm_client.R`)
#' or the counts-file step (see `lib/R/counts_files.R`) and must not depend
#' on either.

#' Convert a factor key to an STF column name
#'
#' Spaces become dots, matching study-wrangler's STF column-naming convention.
#'
#' @param key character scalar
#' @return character scalar
.to_stf_column_name <- function(key) {
  gsub("\\s+", ".", key)
}

#' Infer an STF `data_type`/`data_shape` pair from a vector of raw values
#'
#' Ignores empty strings and `NA` when classifying. If every non-empty value
#' matches `^-?\d+$` the result is `integer`/`continuous`; else if every
#' value is numeric (including exponent notation) it's `number`/`continuous`;
#' else if every value looks like `YYYY-MM-DD` it's `date`/`continuous`;
#' otherwise `string`/`categorical`. With no non-empty values at all, the
#' result defaults to `string`/`categorical`.
#'
#' @param values character vector of raw values
#' @return list(data_type = ..., data_shape = ...)
infer_stf_type <- function(values) {
  non_empty <- values[!is.na(values) & values != ""]

  if (length(non_empty) == 0) {
    return(list(data_type = "string", data_shape = "categorical"))
  }
  if (all(grepl("^-?\\d+$", non_empty))) {
    return(list(data_type = "integer", data_shape = "continuous"))
  }
  if (all(grepl("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$", non_empty))) {
    return(list(data_type = "number", data_shape = "continuous"))
  }
  if (all(grepl("^\\d{4}-\\d{2}-\\d{2}$", non_empty))) {
    return(list(data_type = "date", data_shape = "continuous"))
  }
  list(data_type = "string", data_shape = "categorical")
}

#' Write a parsed sample-annotation list to a study-wrangler STF file pair
#'
#' Writes `entity-sample.tsv` and `entity-sample.yaml` into `output_dir`.
#' The TSV has one row per sample, with a `sample.ID \\ Descriptors` header
#' cell marking the ID column, a `label` column, and one dotted column per
#' annotation factor. The YAML declares a `sample` entity with a matching
#' `id_columns` entry and one `variables` entry per TSV column (`label` is
#' always `string`/`categorical`; each factor's type is inferred from its
#' values via `infer_stf_type()`).
#'
#' @param annotations parsed annotation list: `profileSetName`, `factors`
#'   (named list of `displayName`/`definition`/`unit`), `samples` (list of
#'   `sampleId`/`label`/`factors`)
#' @param output_dir directory to write the STF pair into (must already exist)
#' @return path to the written TSV file, invisibly
annotations_to_stf <- function(annotations, output_dir) {
  factors <- annotations$factors
  samples <- annotations$samples
  factor_keys <- names(factors)
  factor_cols <- vapply(factor_keys, .to_stf_column_name, character(1), USE.NAMES = FALSE)

  # One character vector per factor key, one value per sample (NA where a
  # sample doesn't carry that factor). Built once and shared between the
  # TSV rows and the YAML type inference below.
  factor_values <- setNames(
    lapply(factor_keys, function(key) {
      vapply(samples, function(s) {
        val <- s$factors[[key]]
        if (is.null(val)) NA_character_ else as.character(val)
      }, character(1))
    }),
    factor_keys
  )

  header <- c("sample.ID \\\\ Descriptors", "label", factor_cols)

  row_strings <- vapply(seq_along(samples), function(i) {
    s <- samples[[i]]
    row_factor_vals <- vapply(factor_keys, function(key) {
      v <- factor_values[[key]][i]
      if (is.na(v)) "" else v
    }, character(1))
    paste(c(s$sampleId, s$label, row_factor_vals), collapse = "\t")
  }, character(1))

  tsv_path <- file.path(output_dir, "entity-sample.tsv")
  writeLines(c(paste(header, collapse = "\t"), row_strings), tsv_path)

  label_variable <- list(
    variable = "label",
    provider_label = list("label"),
    display_name = "label",
    data_type = "string",
    data_shape = "categorical"
  )

  factor_variables <- lapply(factor_keys, function(key) {
    f <- factors[[key]]
    inferred <- infer_stf_type(factor_values[[key]])
    v <- list(
      variable = .to_stf_column_name(key),
      provider_label = list(key),
      display_name = if (!is.null(f$displayName)) f$displayName else key
    )
    if (!is.null(f$definition)) v$definition <- f$definition
    v$data_type <- inferred$data_type
    v$data_shape <- inferred$data_shape
    if (!is.null(f$unit)) v$unit <- f$unit
    v
  })

  yaml_list <- list(
    name = "sample",
    display_name = "Sample",
    display_name_plural = "Samples",
    id_columns = list(list(id_column = "sample.ID", entity_name = "sample")),
    variables = c(list(label_variable), factor_variables),
    categories = list(),
    collections = list()
  )

  yaml_path <- file.path(output_dir, "entity-sample.yaml")
  writeLines(yaml::as.yaml(yaml_list), yaml_path)

  invisible(tsv_path)
}

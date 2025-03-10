#!/usr/bin/Rscript

library(tidyverse)
library(study.wrangler)

# Get command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Ensure we have the expected number of arguments
if (length(args) != 2) {
  stop("Usage: wrangle.R <INPUT_DIR> <OUTPUT_DIR>", call. = FALSE)
}

input_dir <- args[1]
output_dir <- args[2]

# Validate that directories exist
if (!dir.exists(input_dir)) {
  stop(paste("Error: input_dir does not exist:", input_dir), call. = FALSE)
}
if (!dir.exists(output_dir)) {
  stop(paste("Error: output_dir does not exist:", output_dir), call. = FALSE)
}

#
# figure out the category
#

### TO DO: handle default fallback better ###
category <- "phenotype" # default
meta_json_path <- file.path(input_dir, "meta.json")
if (file.exists(meta_json_path)) {
  metadata <- jsonlite::read_json(meta_json_path)
  if (!is.null(metadata$category)) {
    category <- metadata$category
  }
} else {
  warning(paste0("WARNING: No metadata file found in: ", meta_json_path, "\nUsing default category: ", category), call. = FALSE)
}

#
# Construct the expected script path: /lib/R/wrangle-<CATEGORY>.R
#
script_path <- file.path("lib/R", paste0("wrangle-", category, ".R"))

# Check if the script exists before sourcing
if (!file.exists(script_path)) {
  stop(paste("Error: No wrangling script found for category:", category, "\nExpected:", script_path), call. = FALSE)
}

# Load the wrangle function dynamically
source(script_path)

# Ensure `wrangle()` is defined after sourcing
if (!exists("wrangle", mode = "function")) {
  stop(paste("Error: Script", script_path, "did not define a function named 'wrangle'"), call. = FALSE)
}

# Execute the wrangling function
study <- wrangle(input_dir)

# dump the database artifacts
if (study %>% validate()) {
  study %>% export_to_vdi(output_dir)
} else {
  stop(paste("Error: Script", script_path, "did not return a valid study from ", input_dir), call. = FALSE)
}

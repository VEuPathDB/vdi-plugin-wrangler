#!/usr/bin/Rscript

suppressPackageStartupMessages({
  library(tidyverse)
  library(study.wrangler)
})

# Load error reporting helpers
source("lib/R/error_helpers.R")

# Configure validation to use both baseline and EDA profiles
set_config(validation.profiles = c("baseline", "eda"))

# Get command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Ensure we have the expected number of arguments
if (length(args) != 2) {
  stop_unexpected_error(
    user_msg = "Internal error: Incorrect arguments passed to wrangle script. Please contact support.",
    technical_msg = "Usage: wrangle.R <INPUT_DIR> <OUTPUT_DIR>"
  )
}

input_dir <- args[1]
output_dir <- args[2]

# Validate that directories exist
if (!dir.exists(input_dir)) {
  stop_unexpected_error(
    user_msg = "Internal error: Input directory not found. Please contact support.",
    technical_msg = paste("Error: input_dir does not exist:", input_dir),
    file = input_dir
  )
}
if (!dir.exists(output_dir)) {
  stop_unexpected_error(
    user_msg = "Internal error: Output directory not found. Please contact support.",
    technical_msg = paste("Error: output_dir does not exist:", output_dir),
    file = output_dir
  )
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
  stop_incompatible_error(
    user_msg = paste("The data category '", category, "' is not supported by this plugin. Please check your data type.", sep = ""),
    technical_msg = paste("Error: No wrangling script found for category:", category, "\nExpected:", script_path),
    file = script_path
  )
}

# Load the wrangle function dynamically
source(script_path)

# Ensure `wrangle()` is defined after sourcing
if (!exists("wrangle", mode = "function")) {
  stop_unexpected_error(
    user_msg = "Internal error: Wrangling script is malformed. Please contact support.",
    technical_msg = paste("Error: Script", script_path, "did not define a function named 'wrangle'"),
    file = script_path
  )
}

# determine study name as either $VDI_IMPORT_ID or the input directory path
study_name <- Sys.getenv("VDI_IMPORT_ID", unset = input_dir)

# Execute the wrangling function
study <- wrangle(input_dir) %>% set_study_name(study_name)

# dump the database artifacts
if (study %>% validate()) {
  study %>% export_to_vdi(output_dir)
} else {
  stop_transformation_error(
    user_msg = "Data processing failed during final validation. Please check that your data file is properly formatted.",
    technical_msg = paste("Error: Script", script_path, "did not return a valid study from", input_dir),
    file = input_dir
  )
}

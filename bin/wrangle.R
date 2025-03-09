#!/usr/bin/Rscript

library(glue) ### TO DO - update study.wrangler to import these where needed
library(tidyverse)
library(study.wrangler)

# Get command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Ensure we have the expected number of arguments
if (length(args) != 3) {
  stop("Usage: wrangle.R <CATEGORY> <INPUT_DIR> <OUTPUT_DIR>", call. = FALSE)
}

CATEGORY <- args[1]
INPUT_DIR <- args[2]
OUTPUT_DIR <- args[3]

# Validate that directories exist
if (!dir.exists(INPUT_DIR)) {
  stop(paste("Error: INPUT_DIR does not exist:", INPUT_DIR), call. = FALSE)
}

if (!dir.exists(OUTPUT_DIR)) {
  stop(paste("Error: OUTPUT_DIR does not exist:", OUTPUT_DIR), call. = FALSE)
}


#
# Construct the expected script path: /lib/R/wrangle-<CATEGORY>.R
#
script_path <- file.path("lib/R", paste0("wrangle-", CATEGORY, ".R"))

# Check if the script exists before sourcing
if (!file.exists(script_path)) {
  stop(paste("Error: No wrangling script found for CATEGORY:", CATEGORY, "\nExpected:", script_path), call. = FALSE)
}

# Load the wrangle function dynamically
source(script_path)

# Ensure `wrangle()` is defined after sourcing
if (!exists("wrangle", mode = "function")) {
  stop(paste("Error: Script", script_path, "did not define a function named 'wrangle'"), call. = FALSE)
}

# Execute the wrangling function
study <- wrangle(INPUT_DIR)

# dump the database artifacts
if (study %>% validate()) {
  study %>% export_to_vdi(OUTPUT_DIR)
} else {
  stop(paste("Error: Script", script_path, "did not return a valid study from ", INPUT_DIR), call. = FALSE)
}
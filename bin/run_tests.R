#!/usr/bin/Rscript

# Capture original working directory because test scripts need it
Sys.setenv(ORIGINAL_WD = getwd())  

testthat::test_dir("tests/testthat")

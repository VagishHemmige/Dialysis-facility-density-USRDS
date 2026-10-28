# Checks that the model written out on the models page (quarto/models.qmd,
# "One model written out") is the model the code fits for Table 2, Model 3,
# with albumin and hemoglobin. Uses only constants from setup.R; no data.
# Run from the project root: testthat::test_file("tests/test-model-example.R")

library(testthat)
library(tidyverse)

root <- if (file.exists("R/setup.R")) "." else ".."
setup <- parse(file.path(root, "R/setup.R"))
walk(setup, \(expression) {
  if (!str_starts(deparse(expression)[1], "library\\(")) eval(expression, globalenv())
})
source(file.path(root, "R/functions.R"))

test_that("the models page shows the formula the code builds for Table 2, Model 3", {
  page <- read_lines(file.path(root, "quarto/models.qmd"))
  start <- which(str_detect(page, "^fit <- glmmTMB\\($"))
  end <- which(str_detect(page, "^  data = patient_groups"))
  expect_length(start, 1)
  expect_length(end, 1)

  shown <- page[(start + 1):(end - 1)] |>
    str_remove("#.*$") |>
    str_flatten(" ") |>
    str_remove(",\\s*$") |>
    as.formula()

  built <- mixed_formula(
    "early_start",
    "density_category",
    c(model_3_covariates, model_2_laboratory)
  )

  expect_identical(attr(terms(shown), "term.labels"), attr(terms(built), "term.labels"))
  expect_identical(all.vars(shown)[1], "early_start")
})

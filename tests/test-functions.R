# Tests for R/functions.R on synthetic data with known answers.
# Run from the project root: testthat::test_file("tests/test-functions.R")
# All data here are synthetic.

library(testthat)
library(tidyverse)
library(lme4)
# test_file() runs from tests/; sourcing works from either folder
source(if (file.exists("R/functions.R")) "R/functions.R" else "../R/functions.R")

test_that("any_yes treats missing and unknown as not present", {
  expect_equal(any_yes(c("YES", "NO", NA, "UNKNOWN")), c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(any_yes(c("NO", "NO"), c("YES", NA)), c(TRUE, FALSE))
})

test_that("insurance follows the original hierarchy", {
  out <- derive_insurance(
    none      = c("YES", "NO", "NO", "NO", "NO", "NO", "NO"),
    medicaid  = c("YES", "YES", "NO", "NO", "NO", "NO", "NO"),
    medicare  = c("NO", "YES", "YES", "NO", "NO", "NO", "NO"),
    advantage = c("NO", "NO", "NO", "YES", "NO", "NO", "NO"),
    group     = c("NO", "NO", "YES", "NO", "YES", "NO", "NO"),
    va        = c("NO", "NO", "NO", "NO", "NO", "YES", "NO"),
    other     = c("NO", "NO", "NO", "NO", "NO", "NO", "NO")
  )
  expect_equal(out, c("No insurance", "Medicaid", "Medicare or managed Medicare",
                      "Medicare or managed Medicare", "Commercial", "Other (including VA)", NA))
})

test_that("nephrology care keeps unknown as a level", {
  out <- derive_nephrology_care(c("NO", "YES", "Yes", "UNKNOWN", NA))
  expect_equal(as.character(out), c("No nephrology care", "Some nephrology care",
                                    "Some nephrology care", "Unknown", "Unknown"))
})

test_that("regions are assigned by state name", {
  regions <- list(South = c("TEXAS"), Pacific = c("HAWAII"))
  expect_equal(assign_region(c("Texas", "HAWAII", "GUAM", NA), regions),
               c("South", "Pacific", NA, NA))
})

test_that("Dartmouth codes become missing, never positive", {
  expect_equal(clean_dartmouth_codes(c("12.5", "-88888", "-99999", "0"), c(-88888, -99999)),
               c(12.5, NA, NA, 0))
})

test_that("ZIP codes keep leading zeros", {
  expect_equal(standardize_zip(c("501", "2134", "10467", "1046", "", NA, "123456")),
               c("00501", "02134", "10467", "01046", NA, NA, NA))
})

test_that("select_by_pattern requires exactly one match", {
  df <- tibble(`HSA num` = 1, `Eye exam %` = 1, `HbA1c % (2015)` = 1, `HbA1c count` = 1)
  expect_equal(unname(select_by_pattern(df, c(eye = "eye"), "test")), "Eye exam %")
  expect_error(select_by_pattern(df, c(a1c = "a1c"), "test"), "matched 2 columns")
  expect_error(select_by_pattern(df, c(beds = "bed"), "test"), "matched 0 columns")
})

test_that("ACS label check catches a changed variable", {
  expected <- tibble(name = "zip_population", variable = "S0601_C01_001", label_pattern = "Total population")
  good <- tibble(year = c(2011, 2012), name = "S0601_C01_001", label = "Estimate!!Total!!Total population")
  expect_silent(check_acs_labels(good, expected))
  bad <- mutate(good, label = c("Estimate!!Total!!Total population", "Estimate!!Total!!AGE"))
  expect_error(check_acs_labels(bad, expected), "2012 S0601_C01_001")
  absent <- good[1, ] |> bind_rows(tibble(year = 2013, name = "S0601_C01_999", label = "x"))
  expect_error(check_acs_labels(absent, expected), "2013 S0601_C01_001: variable not in that year")
})

test_that("density categories put 0 alone and include upper bounds", {
  cuts <- c(1.36, 1.95, 2.76)
  out <- categorize_density(c(0, 0.5, 1.36, 1.37, 1.95, 2.76, 2.77, NA), cuts)
  expect_equal(as.integer(out), c(1, 2, 2, 3, 3, 4, 5, NA))
  expect_equal(levels(out), c("0", ">0-1.36", ">1.36-1.95", ">1.95-2.76", ">2.76"))
})

test_that("mixed_formula builds a random-intercept formula", {
  f <- mixed_formula("y", "x", c("a", "b"))
  expect_equal(deparse(f), "y ~ x + a + b + (1 | hsanum)")
})

test_that("density_odds_ratios recovers a known odds ratio", {
  set.seed(1)
  n <- 20000
  sim <- tibble(
    hsanum = sample(1:200, n, replace = TRUE),
    density_category = factor(sample(c("low", "high"), n, replace = TRUE), levels = c("low", "high"))
  ) |>
    mutate(
      u = rnorm(200, 0, 0.3)[hsanum],
      early_start = rbinom(n, 1, plogis(-0.5 + log(2) * (density_category == "high") + u))
    )
  # The models use glmmTMB; lme4::glmer is checked too, as the alternative
  fits <- list(
    glmmTMB = glmmTMB::glmmTMB(early_start ~ density_category + (1 | hsanum), data = sim, family = binomial),
    glmer = glmer(early_start ~ density_category + (1 | hsanum), data = sim, family = binomial)
  )
  for (m in fits) {
    out <- density_odds_ratios(m, model_name = "synthetic")
    expect_equal(nrow(out), 1)
    expect_equal(out$model, "synthetic")
    expect_equal(out$n, n)
    expect_true(out$conf_low < 2 && out$conf_high > 2)
  }
})

test_that("variance_shares sum to one", {
  set.seed(2)
  sim <- tibble(hsanum = rep(1:50, each = 40)) |>
    mutate(egfr = 9 + rnorm(50, 0, 1)[hsanum] + rnorm(n(), 0, 3))
  shares <- variance_shares(lmer(egfr ~ 1 + (1 | hsanum), data = sim))
  expect_equal(sum(shares$share), 1)
  expect_equal(shares$level, c("hsanum", "Residual"))
})

test_that("classify_codes batches codes and asks again for skipped codes", {
  codes <- tibble(code = sprintf("C%02d", 1:5), description = "synthetic")
  calls <- 0
  # A fake provider that skips C03 the first time it sees it
  seen <- character()
  fake_ask <- function(batch) {
    calls <<- calls + 1
    answer <- batch |>
      filter(code != "C03" | "C03" %in% seen) |>
      transmute(code, category = "Other", reason = "synthetic")
    seen <<- c(seen, batch$code)
    answer
  }
  out <- classify_codes(codes, fake_ask, batch_size = 2)
  expect_equal(calls, 4)
  expect_setequal(out$code, codes$code)
  expect_equal(nrow(out), 5)
})

test_that("check_votes stops on missing, unknown, repeated or invalid answers", {
  codes <- tibble(code = c("A", "B"))
  good <- tibble(code = c("A", "B"), category = c("Diabetes", "Other"))
  expect_identical(check_votes(good, codes, c("Diabetes", "Other"), "fake"), good)
  expect_error(check_votes(good[1, ], codes, c("Diabetes", "Other"), "fake"), "1 code\\(s\\) missing")
  expect_error(check_votes(bind_rows(good, good[1, ]), codes, c("Diabetes", "Other"), "fake"), "1 repeated")
  expect_error(check_votes(mutate(good, category = "Gout"), codes, c("Diabetes", "Other"), "fake"),
               "2 with a category")
})

test_that("cached_votes asks once and then reads the saved file", {
  path <- file.path(tempfile(), "fake.csv")
  calls <- 0
  classify <- function(partial_path) {
    calls <<- calls + 1
    tibble(code = "A", category = "Other", reason = "r")
  }
  first <- cached_votes(path, classify)
  second <- cached_votes(path, classify)
  expect_equal(calls, 1)
  expect_equal(second$code, first$code)
})

test_that("an interrupted classification resumes from the batches already saved", {
  dir <- tempfile()
  path <- file.path(dir, "fake.csv")
  partial_path <- file.path(dir, "fake.partial.csv")
  codes <- tibble(code = sprintf("C%02d", 1:7), description = "synthetic")
  asked <- character()
  answer <- function(batch) {
    asked <<- c(asked, batch$code)
    transmute(batch, code, category = "Other", reason = "synthetic")
  }
  # A fake provider that fails on its third batch, as a timeout would
  failing_ask <- function(batch) {
    if ("C05" %in% batch$code) stop("synthetic timeout")
    answer(batch)
  }
  classify_with <- function(ask) {
    function(partial_path) classify_codes(codes, ask, batch_size = 2, partial_path = partial_path)
  }

  expect_error(cached_votes(path, classify_with(failing_ask)), "synthetic timeout")
  expect_false(file.exists(path))
  expect_equal(read_csv(partial_path, col_types = cols(.default = col_character()))$code,
               sprintf("C%02d", 1:4))

  asked <- character()
  out <- cached_votes(path, classify_with(answer))
  expect_equal(asked, sprintf("C%02d", 5:7))
  expect_setequal(out$code, codes$code)
  expect_equal(nrow(out), 7)
  expect_true(file.exists(path))
  expect_false(file.exists(partial_path))
})

test_that("ensemble_agreement accepts a category given by enough providers", {
  codes <- tibble(code = c("A", "B", "C", "D"), description = c("a", "b", "c", "d"))
  votes <- tribble(
    ~code, ~provider, ~category, ~reason,
    "A", "p1", "Diabetes", "r", "A", "p2", "Diabetes", "r", "A", "p3", "Diabetes", "r",
    "B", "p1", "Diabetes", "r", "B", "p2", "Other", "r", "B", "p3", "Diabetes", "r",
    "C", "p1", "Other", "r", "C", "p2", "Other", "r",
    "D", "p1", "Diabetes", "r", "D", "p2", "Other", "r", "D", "p3", "Glomerulonephritis", "r"
  )
  majority <- ensemble_agreement(votes, codes, min_agreement = 2)
  expect_equal(majority$code, c("A", "B", "C", "D"))
  expect_equal(majority$unanimous, c(TRUE, FALSE, FALSE, FALSE))
  expect_equal(majority$model_category, c("Diabetes", "Diabetes", "Other", NA))

  all_three <- ensemble_agreement(votes, codes, min_agreement = 3)
  expect_equal(all_three$model_category, c("Diabetes", NA, NA, NA))
})

test_that("local_model_report counts valid, missing, invalid and repeated answers", {
  codes <- tibble(code = c("A", "B", "C", "D"))
  accepted <- tibble(code = c("A", "B", "C", "D"),
                     model_category = c("Diabetes", "Other", NA, "Other"))
  votes <- tribble(
    ~provider, ~code, ~category,
    # p1: A right, B wrong, C has no accepted category, D twice, plus junk
    "p1", "A", "Diabetes", "p1", "B", "Diabetes", "p1", "C", "Other",
    "p1", "D", "Other", "p1", "D", "Diabetes", "p1", "\"A\"", "Other", "p1", "{code}", "Other",
    # p2: answers only A, correctly
    "p2", "A", "Diabetes"
  )
  out <- local_model_report(votes, codes, accepted) |> arrange(provider)
  expect_equal(out$codes_answered, c(3L, 1L))
  expect_equal(out$codes_missing, c(0L, 3L))
  expect_equal(out$answers_not_in_list, c(2L, 0L))
  expect_equal(out$codes_repeated, c(1L, 0L))
  expect_equal(out$compared_with_accepted, c(2L, 1L))
  expect_equal(out$agrees_with_accepted, c(1L, 1L))
  expect_equal(out$share_agreeing, c(0.5, 1))
})

test_that("HSA population counts a shared ZCTA once", {
  hsa <- tibble(zip = c("00501", "00544", "11742", "10467"), year = 2015L,
                hsanum = c(1L, 1L, 1L, 2L))
  zcta <- tibble(zip = c("00501", "00544", "11742", "10467"), year = 2015L,
                 zcta = c("11742", "11742", "11742", "10467"))
  pop <- tibble(zcta = c("11742", "10467"), year = 2015L, zip_population = c(1000, 500))
  out <- hsa_population_from_zcta(hsa, zcta, pop) |> arrange(hsanum)
  expect_equal(out$hsa_population, c(1000, 500))
})

test_that("ZIP codes missing from the ZCTA crosswalk add nothing", {
  hsa <- tibble(zip = c("10467", "99999"), year = 2015L, hsanum = 2L)
  zcta <- tibble(zip = "10467", year = 2015L, zcta = "10467")
  pop <- tibble(zcta = "10467", year = 2015L, zip_population = 500)
  expect_equal(hsa_population_from_zcta(hsa, zcta, pop)$hsa_population, 500)
})

test_that("assert_unique stops on duplicated keys and passes data through", {
  df <- tibble(zip = c("10467", "10467"), year = c(2015, 2016))
  expect_identical(assert_unique(df, zip, year), df)
  expect_error(assert_unique(df, zip), "appear more than once")
})

test_that("first_non_missing takes the first column with a value", {
  df <- tibble(PROVUSRD_DIAL = c("A", NA, NA), PROVUSRD = c(1, 2, NA))
  expect_equal(first_non_missing(df), c("A", "2", NA))
  expect_equal(
    tibble(x = 1:3) |> mutate(id = first_non_missing(pick(any_of("absent")))) |> pull(id),
    rep(NA_character_, 3)
  )
})

test_that("density_effects reports differences, not ratios, for a linear model", {
  set.seed(4)
  n <- 3000
  sim <- tibble(
    hsanum = sample(1:100, n, replace = TRUE),
    density_category = factor(sample(c("low", "high"), n, replace = TRUE), levels = c("low", "high"))
  ) |>
    mutate(egfr = 9 + 0.5 * (density_category == "high") + rnorm(100, 0, 1)[hsanum] + rnorm(n, 0, 3))
  fit <- glmmTMB::glmmTMB(egfr ~ density_category + (1 | hsanum), data = sim, family = gaussian())
  out <- density_effects(fit, exponentiate = FALSE)
  expect_equal(nrow(out), 1)
  expect_true(out$conf_low < 0.5 && out$conf_high > 0.5)
  expect_equal(out$n, n)
})

test_that("format_estimates_table keeps one row per model and term, without the variable name", {
  skip_if_not_installed("gt")
  estimates <- tibble(
    block = "Synthetic block",
    model = c("Model 1", "Model 1"),
    term = c("density_category2", "density_category3"),
    estimate = c(1.234, 2.345),
    conf_low = c(1.1, 2.1),
    conf_high = c(1.4, 2.6),
    p_value = c(0.01, 0.5),
    n = 100L
  )
  out <- format_estimates_table(estimates, "Synthetic title", "OR")
  expect_s3_class(out, "gt_tbl")
  expect_equal(gt::extract_cells(out, term), c("2", "3"))
  expect_equal(gt::extract_cells(out, estimate), c("1.23", "2.35"))
})

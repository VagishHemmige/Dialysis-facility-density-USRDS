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
  m <- glmer(early_start ~ density_category + (1 | hsanum), data = sim, family = binomial)
  out <- density_odds_ratios(m, model_name = "synthetic")
  expect_equal(nrow(out), 1)
  expect_equal(out$model, "synthetic")
  expect_equal(out$n, n)
  expect_true(out$conf_low < 2 && out$conf_high > 2)
})

test_that("variance_shares sum to one", {
  set.seed(2)
  sim <- tibble(hsanum = rep(1:50, each = 40)) |>
    mutate(egfr = 9 + rnorm(50, 0, 1)[hsanum] + rnorm(n(), 0, 3))
  shares <- variance_shares(lmer(egfr ~ 1 + (1 | hsanum), data = sim))
  expect_equal(sum(shares$share), 1)
  expect_equal(shares$level, c("hsanum", "Residual"))
})

test_that("classify_codes batches codes and labels the provider", {
  codes <- tibble(code = sprintf("C%02d", 1:5), description = "synthetic")
  calls <- 0
  fake_chat <- function() {
    calls <<- calls + 1
    list(chat_structured = function(prompt, type) {
      batch <- regmatches(prompt, gregexpr("C\\d{2}", prompt))[[1]]
      data.frame(code = batch, category = "Other", reason = "synthetic")
    })
  }
  out <- classify_codes(codes, fake_chat, function(b) paste(b$code, collapse = " "),
                        type = NULL, batch_size = 2, provider = "fake")
  expect_equal(calls, 3)
  expect_equal(out$code, codes$code)
  expect_true(all(out$provider == "fake"))
})

test_that("ensemble_agreement accepts only unanimous codes", {
  codes <- tibble(code = c("A", "B", "C"), description = c("a", "b", "c"))
  votes <- tribble(
    ~code, ~provider, ~category, ~reason,
    "A", "p1", "Diabetes", "r", "A", "p2", "Diabetes", "r", "A", "p3", "Diabetes", "r",
    "B", "p1", "Diabetes", "r", "B", "p2", "Other", "r", "B", "p3", "Diabetes", "r",
    "C", "p1", "Other", "r", "C", "p2", "Other", "r"
  )
  out <- ensemble_agreement(votes, codes)
  expect_equal(out$code, c("A", "B", "C"))
  expect_equal(out$unanimous, c(TRUE, FALSE, FALSE))
  expect_equal(out$model_category, c("Diabetes", NA, NA))
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

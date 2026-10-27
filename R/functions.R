# Purpose: reusable helper functions. Each takes its inputs as arguments.
# Needs: setup.R (packages only). Produces: functions only.
# Tested on synthetic data in tests/test-functions.R.

## ---- fn-any-yes
# TRUE when any of the given 2728 yes/no fields is "YES" (format $YNUFMT).
# Missing or unknown counts as not present, as on the form.
any_yes <- function(...) {
  list(...) |>
    map(\(field) str_to_upper(field) %in% "YES") |>
    reduce(`|`)
}

## ---- fn-derive-insurance
# Insurance hierarchy from the original code: none; else Medicaid; else Medicare
# (including Medicare Advantage); else employer group; else other (including VA).
# Returns NA when no coverage field is marked yes.
derive_insurance <- function(none, medicaid, medicare, advantage, group, va, other) {
  case_when(
    any_yes(none) ~ "No insurance",
    any_yes(medicaid) ~ "Medicaid",
    any_yes(medicare, advantage) ~ "Medicare or managed Medicare",
    any_yes(group) ~ "Commercial",
    any_yes(va, other) ~ "Other (including VA)",
    .default = NA_character_
  )
}

## ---- fn-derive-nephrology-care
# Pre-kidney-failure nephrology care from NEPHCARE (format YN9FMT) and
# NEPHCARERANGE (format RANGE). Unknown is kept as its own level so that
# models do not drop patients, matching the published sample sizes.
derive_nephrology_care <- function(nephcare, nephcare_range) {
  nephcare <- str_to_upper(nephcare)
  nephcare_range <- str_to_upper(nephcare_range)

  case_when(
    nephcare %in% "NO" ~ "None",
    nephcare %in% "YES" & nephcare_range %in% "< 6 MONTHS" ~ "< 6 months",
    nephcare %in% "YES" & nephcare_range %in% "6-12 MONTHS" ~ "6 to 12 months",
    nephcare %in% "YES" & nephcare_range %in% "> 12 MONTHS" ~ "> 12 months",
    nephcare %in% "YES" ~ "Yes, duration unknown",
    .default = "Unknown"
  ) |>
    factor(levels = c("None", "< 6 months", "6 to 12 months", "> 12 months",
                      "Yes, duration unknown", "Unknown"))
}

## ---- fn-assign-region
# Census region of a state name (uppercase, as labelled by $STATFIP).
# `regions` is a named list: region name = vector of state names.
assign_region <- function(state, regions) {
  region_lookup <- enframe(regions, name = "region", value = "state") |>
    unnest_longer(state)

  tibble(state = str_to_upper(state)) |>
    left_join(region_lookup, by = "state", relationship = "many-to-one") |>
    pull(region)
}

## ---- fn-clean-dartmouth-codes
# Dartmouth Atlas uses negative codes for small or suppressed values; they
# become NA rather than numbers.
clean_dartmouth_codes <- function(x, codes) {
  x <- suppressWarnings(as.numeric(x))
  if_else(x %in% codes, NA_real_, x)
}

## ---- fn-select-by-pattern
# For each named pattern, the one column of `df` whose name matches it
# (ignoring case). Stops with the candidates when a pattern matches none or
# several. Returns a named character vector: measure = column name.
select_by_pattern <- function(df, patterns, source_name) {
  imap_chr(patterns, function(pattern, measure) {
    hits <- str_subset(names(df), regex(pattern, ignore_case = TRUE))

    if (length(hits) != 1) {
      stop(str_glue(
        "{source_name}: the pattern for '{measure}' ({pattern}) matched ",
        "{length(hits)} columns: {str_flatten_comma(hits)}. ",
        "Edit the pattern in R/setup.R."
      ), call. = FALSE)
    }

    hits
  })
}

## ---- fn-read-header-table
# Read a spreadsheet whose header is not on the first row: the header is the
# first row with a cell matching `header_pattern` (for example "HSA").
read_header_table <- function(path, header_pattern, sheet = 1) {
  header_row <- read_excel(path, sheet = sheet, col_names = FALSE, col_types = "text",
                           .name_repair = "minimal") |>
    rename_with(\(names) str_c("column_", seq_along(names))) |>
    mutate(row = row_number()) |>
    filter(if_any(-row, \(cell) str_detect(cell, regex(header_pattern, ignore_case = TRUE)))) |>
    pull(row) |>
    first()

  if (is.na(header_row)) {
    stop(str_glue("No header row matching '{header_pattern}' in {path}."), call. = FALSE)
  }

  read_excel(path, sheet = sheet, skip = header_row - 1, .name_repair = "unique_quiet")
}

## ---- fn-standardize-zip
# 5-character ZIP code, restoring leading zeros dropped by spreadsheets
# (for example 501 becomes 00501). Anything else becomes NA.
standardize_zip <- function(zip) {
  zip <- str_remove_all(zip, "[^0-9]")

  case_when(
    str_length(zip) %in% 3:4 ~ str_pad(zip, width = 5, side = "left", pad = "0"),
    str_length(zip) == 5 ~ zip,
    .default = NA_character_
  )
}

## ---- fn-first-non-missing
# Row by row, the first non-missing value across the columns of `data`, as
# character. All missing when `data` has no columns. Used where a release has
# one of several alternative columns (for example the provider ID).
first_non_missing <- function(data) {
  data |>
    map(as.character) |>
    reduce(coalesce, .init = NA_character_)
}

## ---- fn-assert-unique
# Stop if any combination of the given columns appears more than once.
# Returns the data unchanged, so it can sit in a pipeline.
assert_unique <- function(data, ...) {
  duplicates <- data |>
    count(...) |>
    filter(n > 1)

  if (nrow(duplicates) > 0) {
    stop(str_glue("{nrow(duplicates)} key value(s) appear more than once."), call. = FALSE)
  }

  invisible(data)
}

## ---- fn-check-acs-labels
# Stop if any year's ACS variable label does not match its expected pattern,
# or a variable is missing from a year. `labels` has columns year, name
# (variable code) and label; `expected` has variable and label_pattern.
check_acs_labels <- function(labels, expected) {
  checked <- expected |>
    inner_join(labels, by = join_by(variable == name), relationship = "one-to-many") |>
    mutate(ok = str_detect(label, label_pattern))

  mismatched <- checked |>
    filter(!ok) |>
    mutate(problem = str_glue("{year} {variable}: '{label}' does not match '{label_pattern}'"))

  absent <- expected |>
    cross_join(distinct(labels, year)) |>
    anti_join(checked, by = join_by(variable, year)) |>
    mutate(problem = str_glue("{year} {variable}: variable not in that year's table"))

  problems <- c(mismatched$problem, absent$problem)

  if (length(problems) > 0) {
    stop("ACS variable check failed:\n", str_flatten(problems, "\n"), call. = FALSE)
  }

  invisible(checked)
}

## ---- fn-density-categories
# Five exposure categories: 0, then (0, q1], (q1, q2], (q2, q3], above q3.
density_category_labels <- function(cutpoints, digits = 2) {
  q <- format(round(cutpoints, digits), nsmall = digits, trim = TRUE)

  c(
    "0",
    str_c(">0-", q[1]),
    str_c(">", q[1], "-", q[2]),
    str_c(">", q[2], "-", q[3]),
    str_c(">", q[3])
  )
}

categorize_density <- function(density, cutpoints, digits = 2) {
  stopifnot(length(cutpoints) == 3, !is.unsorted(cutpoints))

  category <- case_when(
    is.na(density) ~ NA_integer_,
    density == 0 ~ 1L,
    density <= cutpoints[1] ~ 2L,
    density <= cutpoints[2] ~ 3L,
    density <= cutpoints[3] ~ 4L,
    .default = 5L
  )

  factor(category, levels = 1:5, labels = density_category_labels(cutpoints, digits))
}

## ---- fn-egfr-within-limit
# The eGFR restriction (analysis-plan.md section 4, open decision #D2):
# at or below the limit when `inclusive`, otherwise strictly below.
egfr_within_limit <- function(egfr, maximum, inclusive) {
  if (inclusive) {
    egfr <= maximum
  } else {
    egfr < maximum
  }
}

## ---- fn-density-odds-ratios
# Odds ratios (95% Wald CI, p value) for the density terms of a fitted model,
# with the number of patients the model used.
density_odds_ratios <- function(model, term_pattern = "^density_category", model_name = NA_character_) {
  # Computed before transmute(), where the new `model` column would mask the fit
  n_used <- nobs(model)

  broom.mixed::tidy(model, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) |>
    filter(str_detect(term, term_pattern)) |>
    transmute(
      model = model_name,
      term,
      odds_ratio = estimate,
      conf_low = conf.low,
      conf_high = conf.high,
      p_value = p.value,
      n = n_used
    )
}

## ---- fn-model-formula
# outcome ~ exposure + covariates + (1 | cluster)
mixed_formula <- function(outcome, exposure, covariates, cluster = "hsanum") {
  terms <- c(exposure, covariates, str_glue("(1 | {cluster})"))
  reformulate(terms, response = outcome)
}

## ---- fn-variance-share
# Share of total variance at each random-effect level of a linear mixed model.
variance_shares <- function(model) {
  lme4::VarCorr(model) |>
    as.data.frame() |>
    as_tibble() |>
    transmute(level = grp, variance = vcov, share = vcov / sum(vcov))
}

## ---- fn-cause-code-system
# The coding system of a USRDS primary-cause code ($PD96DET): ICD-10-CM (a
# letter then digits), ICD-9-CM (digits), a USRDS variant of an ICD-9-CM code
# (digits then a letter), or a USRDS code for a missing or unknown cause
# (all zeros, eights or nines, or no digits, such as 00000Z, 99999Z, *****, U).
cause_code_system <- function(code) {
  case_when(
    str_detect(code, "^(0+|8+|9+)[A-Z]?$") | !str_detect(code, "[0-9]") ~
      "USRDS code for a missing or unknown cause",
    str_detect(code, "^[A-Z][0-9]") ~ "ICD-10-CM",
    str_detect(code, "^[0-9]+$") ~ "ICD-9-CM",
    str_detect(code, "^[0-9]+[A-Z]$") ~ "ICD-9-CM, USRDS variant",
    .default = "USRDS code for a missing or unknown cause"
  )
}

## ---- fn-classify-codes
# Classify codes with one model, in batches. `ask` is that provider's function:
# it takes a batch of codes (with every column of `codes`) and returns one row
# per code with code, category and reason. Codes the model skipped are asked
# once more.
classify_codes <- function(codes, ask, batch_size) {
  ask_in_batches <- function(codes) {
    codes |>
      mutate(batch = (row_number() - 1) %/% batch_size) |>
      group_split(batch, .keep = FALSE) |>
      map(ask) |>
      list_rbind() |>
      transmute(
        code = as.character(code),
        category = as.character(category),
        reason = as.character(reason)
      )
  }

  answers <- ask_in_batches(codes)
  skipped <- anti_join(codes, answers, by = "code")

  if (nrow(skipped) > 0) {
    answers <- bind_rows(answers, ask_in_batches(skipped))
  }

  answers
}

## ---- fn-check-votes
# Stop unless one model answered every code exactly once, asked about no code
# that was not given, and used only the allowed categories. Returns the votes.
check_votes <- function(votes, codes, categories, provider) {
  missing <- anti_join(codes, votes, by = "code")
  unknown <- anti_join(votes, codes, by = "code")
  repeated <- votes |>
    count(code) |>
    filter(n > 1)
  wrong_category <- votes |>
    filter(!category %in% categories)

  if (nrow(missing) + nrow(unknown) + nrow(repeated) + nrow(wrong_category) > 0) {
    stop(str_glue(
      "{provider}: {nrow(missing)} code(s) missing, {nrow(unknown)} not asked about, ",
      "{nrow(repeated)} repeated, {nrow(wrong_category)} with a category not in the list."
    ), call. = FALSE)
  }

  invisible(votes)
}

## ---- fn-cached-votes
# One provider's answers, saved to `path` the first time so that a rerun does
# not pay for them again. `classify` is called only when the file does not
# exist; delete the file to ask that provider again.
cached_votes <- function(path, classify) {
  if (file.exists(path)) {
    return(read_csv(path, col_types = cols(.default = col_character())))
  }

  votes <- classify()
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_csv(votes, path, na = "")
  votes
}

## ---- fn-ensemble-agreement
# One row per code: each provider's category and reason, whether every
# provider answered and all agree, and the accepted category when they do.
ensemble_agreement <- function(votes, codes) {
  n_providers_total <- n_distinct(votes$provider)

  agreement <- votes |>
    summarize(
      n_providers = n(),
      n_categories = n_distinct(category),
      first_category = first(category),
      .by = code
    ) |>
    mutate(
      unanimous = n_providers == n_providers_total & n_categories == 1,
      model_category = if_else(unanimous, first_category, NA_character_)
    ) |>
    select(code, n_providers, unanimous, model_category)

  each_provider <- votes |>
    select(code, provider, category, reason) |>
    pivot_wider(names_from = provider, values_from = c(category, reason))

  codes |>
    left_join(each_provider, by = "code", relationship = "one-to-one") |>
    left_join(agreement, by = "code", relationship = "one-to-one")
}

## ---- fn-hsa-population
# HSA population from ZCTA populations. Several ZIP codes can share one ZCTA,
# so each ZCTA is counted once per HSA and year; summing over ZIP codes would
# count a shared ZCTA's population more than once. ZCTAs without ACS data
# contribute nothing.
hsa_population_from_zcta <- function(hsa_crosswalk, zcta_crosswalk, zcta_population) {
  hsa_crosswalk |>
    select(zip, year, hsanum) |>
    inner_join(zcta_crosswalk, by = join_by(zip, year), relationship = "one-to-one") |>
    distinct(year, hsanum, zcta) |>
    left_join(zcta_population, by = join_by(zcta, year), relationship = "many-to-one") |>
    summarize(hsa_population = sum(zip_population, na.rm = TRUE), .by = c(year, hsanum))
}

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
# Access to pre-kidney-failure nephrology care from NEPHCARE (format YN9FMT),
# as in the paper's Table 1 and Model 3. Unknown or blank is its own level, so
# the models keep these patients, as the published sample sizes show.
derive_nephrology_care <- function(nephcare) {
  nephcare <- str_to_upper(nephcare)

  case_when(
    nephcare %in% "YES" ~ "Some nephrology care",
    nephcare %in% "NO" ~ "No nephrology care",
    .default = "Unknown"
  ) |>
    factor(levels = c("No nephrology care", "Some nephrology care", "Unknown"))
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
  if (length(cutpoints) != 3 || is.unsorted(cutpoints)) {
    stop("Density cut points must be three values in increasing order.", call. = FALSE)
  }

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

## ---- fn-density-odds-ratios
# The density terms of a fitted model, with 95% Wald confidence intervals, p
# values and the number of patients the model used. Logistic models report
# odds ratios (exponentiate = TRUE); linear models report differences.
density_effects <- function(model, term_pattern = "^density_category",
                            model_name = NA_character_, exponentiate = TRUE) {
  # Computed before transmute(), where the new `model` column would mask the fit
  n_used <- nobs(model)

  broom.mixed::tidy(model, effects = "fixed", conf.int = TRUE, exponentiate = exponentiate) |>
    filter(str_detect(term, term_pattern)) |>
    transmute(
      model = model_name,
      term,
      estimate,
      conf_low = conf.low,
      conf_high = conf.high,
      p_value = p.value,
      n = n_used
    )
}

density_odds_ratios <- function(model, term_pattern = "^density_category",
                                model_name = NA_character_) {
  density_effects(model, term_pattern, model_name, exponentiate = TRUE) |>
    rename(odds_ratio = estimate)
}

## ---- fn-format-estimates-table
# A gt table of density estimates: rows grouped by block, one row per model
# and density term, with the variable name removed from each term.
format_estimates_table <- function(df, title, estimate_label) {
  df |>
    mutate(term = str_remove(term, "^(density_category|hsa_center_density)")) |>
    select(block, model, term, estimate, conf_low, conf_high, p_value, n) |>
    gt::gt(groupname_col = "block") |>
    gt::fmt_number(c(estimate, conf_low, conf_high), decimals = 2) |>
    gt::fmt_number(p_value, decimals = 3) |>
    gt::fmt_integer(n) |>
    gt::cols_label(
      model = "Model",
      term = "Density category",
      estimate = estimate_label,
      conf_low = "95% CI low",
      conf_high = "95% CI high",
      p_value = "P",
      n = "N"
    ) |>
    gt::tab_header(title = title)
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

## ---- fn-classify-codes
# Classify codes with one model, in batches. `ask` is that provider's function:
# it takes a batch of codes (code, description) and returns one row per code
# with code, category and reason. Codes the model skipped are asked once more.
# With a `label` (the provider's name), each batch reports its progress, since
# a batch can take a minute or more. With a `partial_path`, each batch's
# answers are added to that file as soon as the batch finishes, and a rerun
# after an interruption reads them back and asks only the codes not yet
# answered.
classify_codes <- function(codes, ask, batch_size, label = NULL, partial_path = NULL) {
  report <- function(...) {
    if (!is.null(label)) message(label, ": ", ...)
  }

  save_batch <- function(answer) {
    if (is.null(partial_path)) {
      return(invisible(answer))
    }
    write_csv(answer, partial_path, na = "", append = file.exists(partial_path))
  }

  ask_in_batches <- function(codes, round) {
    batches <- codes |>
      select(code, description) |>
      mutate(batch = (row_number() - 1) %/% batch_size) |>
      group_split(batch, .keep = FALSE)

    batches |>
      imap(\(batch, i) {
        report(str_glue("{round}batch {i} of {length(batches)} ({nrow(batch)} codes)"))
        answer <- ask(batch) |>
          transmute(
            code = as.character(code),
            category = as.character(category),
            reason = as.character(reason)
          )
        save_batch(answer)
        answer
      }) |>
      list_rbind()
  }

  started <- Sys.time()
  answered_before <- if (!is.null(partial_path) && file.exists(partial_path)) {
    read_csv(partial_path, col_types = cols(.default = col_character())) |>
      as_tibble()
  } else {
    tibble(code = character(), category = character(), reason = character())
  }

  if (nrow(answered_before) > 0) {
    report(str_glue(
      "{n_distinct(answered_before$code)} code(s) already answered in an earlier run; ",
      "asking the rest"
    ))
  }

  answers <- bind_rows(
    answered_before,
    ask_in_batches(anti_join(codes, answered_before, by = "code"), round = "")
  )
  skipped <- anti_join(codes, answers, by = "code")

  if (nrow(skipped) > 0) {
    report(str_glue("{nrow(skipped)} code(s) skipped; asking once more"))
    answers <- bind_rows(answers, ask_in_batches(skipped, round = "second try, "))
  }

  report(str_glue(
    "{nrow(answers)} answers in ",
    "{round(as.numeric(difftime(Sys.time(), started, units = 'mins')), 1)} minutes"
  ))
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
# exist; delete the file to ask that provider again. `classify` is given the
# path of a file for answers saved batch by batch (`path` with .partial before
# .csv), which is deleted once the complete answers are saved. The caller
# checks the answers (check_votes()) whether they are new or read back.
cached_votes <- function(path, classify) {
  if (file.exists(path)) {
    message("Reading saved answers: ", path)
    return(read_csv(path, col_types = cols(.default = col_character())))
  }

  partial_path <- str_replace(path, "\\.csv$", ".partial.csv")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  message("No saved answers; asking the model: ", basename(path))
  votes <- classify(partial_path)
  write_csv(votes, path, na = "")
  if (file.exists(partial_path)) {
    file.remove(partial_path)
  }
  message("Saved: ", path)
  votes
}

## ---- fn-ensemble-agreement
# One row per code: each provider's category and reason, how many providers
# answered, whether all agree, and the accepted category. A category is
# accepted when at least `min_agreement` providers give it.
ensemble_agreement <- function(votes, codes, min_agreement) {
  n_providers_total <- n_distinct(votes$provider)

  top_category <- votes |>
    count(code, category, name = "n_agreeing") |>
    slice_max(n_agreeing, n = 1, with_ties = FALSE, by = code)

  agreement <- votes |>
    summarize(n_providers = n(), n_categories = n_distinct(category), .by = code) |>
    left_join(top_category, by = "code", relationship = "one-to-one") |>
    mutate(
      unanimous = n_providers == n_providers_total & n_categories == 1,
      model_category = if_else(n_agreeing >= min_agreement, category, NA_character_)
    ) |>
    select(code, n_providers, n_agreeing, unanimous, model_category)

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

## ---- fn-map-panel
# One map panel of HSAs filled by a numeric column; HSAs with no value are grey.
map_panel <- function(map, fill, title, legend) {
  ggplot(map) +
    geom_sf(aes(fill = .data[[fill]]), color = NA) +
    scale_fill_viridis_c(name = legend, na.value = "grey85") +
    coord_sf(crs = 5070) +
    labs(title = title) +
    theme_void()
}

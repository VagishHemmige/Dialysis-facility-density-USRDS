# Purpose: reusable helper functions. Each takes its inputs as arguments.
# Needs: setup.R (packages only). Produces: functions only.
# Tested on synthetic data in tests/test-functions.R.

## ---- fn-any-yes
# TRUE when any of the given 2728 yes/no fields is "YES" (format $YNUFMT).
# Missing or unknown counts as not present, as on the form.
any_yes <- function(...) {
  fields <- list(...)
  Reduce(`|`, lapply(fields, function(x) !is.na(x) & toupper(as.character(x)) == "YES"))
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
    TRUE ~ NA_character_
  )
}

## ---- fn-derive-nephrology-care
# Pre-kidney-failure nephrology care from NEPHCARE (format YN9FMT) and
# NEPHCARERANGE (format RANGE). Unknown is kept as its own level so that
# models do not drop patients, matching the published sample sizes.
derive_nephrology_care <- function(nephcare, nephcare_range) {
  nephcare <- toupper(as.character(nephcare))
  nephcare_range <- toupper(as.character(nephcare_range))
  factor(
    case_when(
      nephcare == "NO" ~ "None",
      nephcare == "YES" & nephcare_range == "< 6 MONTHS" ~ "< 6 months",
      nephcare == "YES" & nephcare_range == "6-12 MONTHS" ~ "6 to 12 months",
      nephcare == "YES" & nephcare_range == "> 12 MONTHS" ~ "> 12 months",
      nephcare == "YES" ~ "Yes, duration unknown",
      TRUE ~ "Unknown"
    ),
    levels = c("None", "< 6 months", "6 to 12 months", "> 12 months",
               "Yes, duration unknown", "Unknown")
  )
}

## ---- fn-assign-region
# Census region of a state name (uppercase, as labelled by $STATFIP).
assign_region <- function(state, regions) {
  state <- toupper(as.character(state))
  out <- rep(NA_character_, length(state))
  for (region in names(regions)) out[state %in% regions[[region]]] <- region
  out
}

## ---- fn-clean-dartmouth-codes
# Dartmouth Atlas uses negative codes for small or suppressed values.
clean_dartmouth_codes <- function(x, codes) {
  x <- suppressWarnings(as.numeric(x))
  x[x %in% codes] <- NA_real_
  x
}

## ---- fn-select-by-pattern
# Find exactly one column of `df` matching each pattern; stop with the
# candidates otherwise. Returns a named character vector of column names.
select_by_pattern <- function(df, patterns, source_name) {
  found <- vapply(names(patterns), function(measure) {
    hits <- grep(patterns[[measure]], names(df), ignore.case = TRUE, value = TRUE)
    if (length(hits) != 1) {
      stop(
        sprintf(
          "%s: pattern for '%s' (%s) matched %d columns: %s. Edit the pattern in R/setup.R.",
          source_name, measure, patterns[[measure]], length(hits),
          paste(if (length(hits)) hits else "(none)", collapse = ", ")
        ),
        call. = FALSE
      )
    }
    hits
  }, character(1))
  found
}

## ---- fn-read-header-table
# Read a spreadsheet whose header is not on the first row: the header is the
# first row with a cell matching `header_pattern` (for example "HSA").
read_header_table <- function(path, header_pattern, sheet = 1) {
  raw <- read_excel(path, sheet = sheet, col_names = FALSE, .name_repair = "minimal")
  header_row <- which(apply(raw, 1, function(r) any(grepl(header_pattern, r, ignore.case = TRUE))))[1]
  if (is.na(header_row)) stop("No header row matching '", header_pattern, "' in ", path, call. = FALSE)
  read_excel(path, sheet = sheet, skip = header_row - 1, .name_repair = "unique_quiet")
}

## ---- fn-standardize-zip
# 5-character ZIP code, restoring leading zeros dropped by spreadsheets.
standardize_zip <- function(zip) {
  zip <- gsub("[^0-9]", "", as.character(zip))
  zip[nchar(zip) %in% 3:4] <- formatC(as.integer(zip[nchar(zip) %in% 3:4]), width = 5, flag = "0")
  zip[!nchar(zip) %in% 5] <- NA_character_
  zip
}

## ---- fn-check-acs-labels
# Stop if any year's ACS variable label does not match the expected pattern.
# `labels` has columns year, name (variable code) and label.
check_acs_labels <- function(labels, expected) {
  checked <- expected |>
    inner_join(labels, by = c("variable" = "name"), relationship = "one-to-many") |>
    mutate(ok = mapply(grepl, label_pattern, label))
  missing_years <- setdiff(unique(labels$year), unique(checked$year))
  bad <- filter(checked, !ok)
  absent <- expected |>
    cross_join(distinct(labels, year)) |>
    anti_join(checked, by = c("variable", "year"))
  if (nrow(bad) > 0 || nrow(absent) > 0) {
    msg <- c(
      if (nrow(bad) > 0) sprintf("%s %s: '%s' does not match '%s'",
                                 bad$year, bad$variable, bad$label, bad$label_pattern),
      if (nrow(absent) > 0) sprintf("%s %s: variable not in that year's table",
                                    absent$year, absent$variable)
    )
    stop("ACS variable check failed:\n", paste(msg, collapse = "\n"), call. = FALSE)
  }
  invisible(checked)
}

## ---- fn-density-categories
# Five exposure categories: 0, then (0, q1], (q1, q2], (q2, q3], above q3.
density_category_labels <- function(cutpoints, digits = 2) {
  q <- formatC(cutpoints, format = "f", digits = digits)
  c("0", paste0(">0-", q[1]), paste0(">", q[1], "-", q[2]),
    paste0(">", q[2], "-", q[3]), paste0(">", q[3]))
}

categorize_density <- function(density, cutpoints, digits = 2) {
  stopifnot(length(cutpoints) == 3, !is.unsorted(cutpoints))
  category <- case_when(
    is.na(density) ~ NA_integer_,
    density == 0 ~ 1L,
    density <= cutpoints[1] ~ 2L,
    density <= cutpoints[2] ~ 3L,
    density <= cutpoints[3] ~ 4L,
    TRUE ~ 5L
  )
  factor(category, levels = 1:5, labels = density_category_labels(cutpoints, digits))
}

## ---- fn-density-odds-ratios
# Odds ratios (95% Wald CI, p value) for the density terms of a fitted model.
density_odds_ratios <- function(model, term_pattern = "^density_category", model_name = NULL) {
  # Computed before transmute(), where a new `model` column would mask the fit
  n_used <- stats::nobs(model)
  label <- if (is.null(model_name)) NA_character_ else model_name
  broom.mixed::tidy(model, effects = "fixed", conf.int = TRUE, exponentiate = TRUE) |>
    filter(grepl(term_pattern, term)) |>
    transmute(
      model = label,
      term,
      odds_ratio = estimate,
      conf_low = conf.low,
      conf_high = conf.high,
      p_value = p.value,
      n = n_used
    )
}

## ---- fn-model-formula
# Outcome ~ exposure + covariates + (1 | cluster)
mixed_formula <- function(outcome, exposure, covariates, cluster = "hsanum") {
  stats::reformulate(c(exposure, covariates, paste0("(1 | ", cluster, ")")), response = outcome)
}

## ---- fn-variance-share
# Share of total variance at each random-effect level of a linear mixed model.
variance_shares <- function(model) {
  vc <- as.data.frame(lme4::VarCorr(model))
  tibble(level = vc$grp, variance = vc$vcov, share = vc$vcov / sum(vc$vcov))
}

## ---- fn-classify-codes
# Ask one chat model to classify codes in batches; returns one row per code.
# `chat_fn` creates a fresh chat for each batch (for example a call to
# ellmer::chat_anthropic()), so batches do not share conversation history.
classify_codes <- function(codes, chat_fn, prompt_fn, type, batch_size, provider) {
  batches <- split(codes, ceiling(seq_len(nrow(codes)) / batch_size))
  map(batches, function(batch) {
    chat <- chat_fn()
    result <- chat$chat_structured(prompt_fn(batch), type = type)
    as_tibble(result)
  }) |>
    list_rbind() |>
    transmute(code = as.character(code), category = as.character(category),
              reason = as.character(reason), provider = provider)
}

## ---- fn-ensemble-agreement
# Combine one row per code and provider into one row per code: each provider's
# category, whether all agree, and the accepted category when unanimous.
ensemble_agreement <- function(votes, codes) {
  wide <- votes |>
    select(code, provider, category, reason) |>
    pivot_wider(names_from = provider, values_from = c(category, reason))
  category_cols <- grep("^category_", names(wide), value = TRUE)
  wide |>
    mutate(
      n_providers = rowSums(!is.na(pick(all_of(category_cols)))),
      unanimous = n_providers == length(category_cols) &
        apply(pick(all_of(category_cols)), 1, function(r) length(unique(r)) == 1),
      model_category = if_else(unanimous, .data[[category_cols[1]]], NA_character_)
    ) |>
    right_join(codes, by = "code") |>
    relocate(code, description)
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

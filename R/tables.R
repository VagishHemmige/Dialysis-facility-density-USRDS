# Purpose: build Table 1 and the regression tables, and export them to tables/.
# Needs: cohort with density_category (define_exposure.R); model estimates
#   (models.R, or models/model_estimates.rds); tables_dir (setup.R).
# Produces: table_1 (gtsummary) and HTML files in tables/ (gitignored until
#   the outputs are checked against the paper and cleared for release).

## ---- build-table-1
table_1_variables <- c(
  "age", "sex", "race", "hispanic",
  "heart_failure", "coronary_disease", "diabetes", "cerebrovascular_disease",
  "cancer", "immobility", "alcohol_or_drug",
  "nephrology_care", "albumin", "hemoglobin", "access_type", "insurance",
  "esrd_cause", "zip_percent_black", "zip_percent_poverty",
  "hsa_ambulatory_sensitive_discharges", "hsa_percent_mammogram",
  "hsa_percent_hba1c", "hsa_percent_eye_exam", "profit_centers_area", "rural_urban"
)

table_1 <- cohort |>
  select(density_category, all_of(table_1_variables)) |>
  tbl_summary(
    by = density_category,
    statistic = list(all_continuous() ~ "{mean} ({sd})"),
    digits = list(all_continuous() ~ 1),
    missing = "ifany"
  ) |>
  # Classical one-way ANOVA, as the paper says (var.equal = TRUE; the default
  # of oneway.test() is Welch's test). Decided by Vagish Hemmige, 28 October 2026.
  add_p(
    test = list(all_continuous() ~ "oneway.test", all_categorical() ~ "chisq.test"),
    test.args = all_continuous() ~ list(var.equal = TRUE)
  ) |>
  modify_spanning_header(all_stat_cols() ~ "**HSA facility density per 100,000 population**")

## ---- build-regression-tables
# The estimates from this session if models.R has just run, otherwise the
# saved ones
estimates <- if (exists("model_estimates")) {
  model_estimates
} else {
  readRDS(file.path("models", "model_estimates.rds"))
}

# One gt table per published table (format_estimates_table() in functions.R).
# Logistic models give odds ratios; eTable 3 gives differences in eGFR.
published_titles <- tribble(
  ~table,     ~title,                                                                                   ~estimate_label,
  "Table 2",  "Odds of starting hemodialysis at eGFR ≥ 10 by HSA facility density",                     "OR",
  "eTable 1", "Odds of starting hemodialysis at eGFR ≥ 10, stratified by race",                         "OR",
  "eTable 2", "Odds of starting hemodialysis at eGFR ≥ 10 per unit of HSA facility density",            "OR",
  "eTable 3", "Difference in eGFR at dialysis start by HSA facility density",                           "Difference in eGFR"
)

published_tables <- published_titles |>
  pmap(function(table, title, estimate_label) {
    estimates$published |>
      filter(table == .env$table) |>
      format_estimates_table(title, estimate_label)
  }) |>
  set_names(published_titles$table)

table_egfr_range <- estimates$egfr_range |>
  rename(estimate = odds_ratio) |>
  mutate(block = "Original R code, not in the paper") |>
  format_estimates_table("Model 3 excluding eGFR of 5 or below", "OR")

## ---- export-tables
dir.create(tables_dir, showWarnings = FALSE)
# File name = table
output_tables <- list(
  "table_1.html" = as_gt(table_1),
  "table_2.html" = published_tables[["Table 2"]],
  "etable_1_race.html" = published_tables[["eTable 1"]],
  "etable_2_continuous.html" = published_tables[["eTable 2"]],
  "etable_3_linear.html" = published_tables[["eTable 3"]],
  "egfr_range.html" = table_egfr_range
)

iwalk(output_tables, function(table, file_name) {
  gtsave(table, file.path(tables_dir, file_name))
})

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
  "nephrology_care_any", "albumin", "hemoglobin", "access_type", "insurance",
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
  add_p(test = list(all_continuous() ~ "oneway.test", all_categorical() ~ "chisq.test")) |>
  modify_spanning_header(all_stat_cols() ~ "**HSA facility density per 100,000 population**")

## ---- build-regression-tables
# The estimates from this session if models.R has just run, otherwise the
# saved ones
estimates <- if (exists("model_estimates")) {
  model_estimates
} else {
  readRDS(file.path("models", "model_estimates.rds"))
}

format_or_table <- function(df, title) {
  df |>
    mutate(term = str_remove(term, "^density_category")) |>
    gt(groupname_col = "model") |>
    fmt_number(c(odds_ratio, conf_low, conf_high), decimals = 2) |>
    fmt_number(p_value, decimals = 3) |>
    fmt_integer(n) |>
    cols_label(
      term = "Density category",
      odds_ratio = "OR",
      conf_low = "95% CI low",
      conf_high = "95% CI high",
      p_value = "P",
      n = "N"
    ) |>
    tab_header(title = title)
}

table_2 <- estimates$table_2 |>
  format_or_table("Odds of starting hemodialysis at eGFR > 10 by HSA facility density")

table_sensitivity <- bind_rows(estimates$sensitivity, estimates$egfr_range) |>
  format_or_table("Sensitivity analyses")

table_race <- estimates$race |>
  format_or_table("Models stratified by race (eTable 1)")

## ---- export-tables
dir.create(tables_dir, showWarnings = FALSE)
# File name = table
output_tables <- list(
  "table_1.html" = as_gt(table_1),
  "table_2.html" = table_2,
  "table_sensitivity.html" = table_sensitivity,
  "etable_1_race.html" = table_race
)

iwalk(output_tables, function(table, file_name) {
  gtsave(table, file.path(tables_dir, file_name))
})

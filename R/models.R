# Purpose: fit the models behind Table 2 and eTables 1 to 3
#   (analysis-plan.md sections 8 and 9).
# Needs: cohort with density_category (define_exposure.R); model constants and
#   covariate sets (setup.R); density_odds_ratios(), mixed_formula(),
#   variance_shares() (functions.R).
# Produces: table_2_estimates, sensitivity_estimates, race_estimates,
#   linear_estimates, variance_decomposition, imputation_estimates.
# Fitting takes hours on the full cohort; models are saved in the ignored
#   models/ folder so tables.R can be rerun without refitting.

## ---- prepare-model-data
model_data <- cohort |>
  mutate(
    year = factor(year),
    density_category = relevel(density_category, ref = levels(density_category)[1])
  )

fit_logistic <- function(data, exposure, covariates) {
  glmer(mixed_formula("early_start", exposure, covariates), data = data,
        family = binomial, nAGQ = glmer_nagq,
        control = glmerControl(optimizer = "bobyqa"))
}

## ---- fit-table-2-models
# Models 1 to 3; Models 2 and 3 with and without albumin and hemoglobin.
table_2_specs <- tribble(
  ~model,                         ~covariates,
  "Model 1",                      model_1_covariates,
  "Model 2 (with albumin, Hb)",   c(model_2_covariates, model_2_laboratory),
  "Model 3 (with albumin, Hb)",   c(model_3_covariates, model_2_laboratory),
  "Model 2 (without albumin, Hb)", model_2_covariates,
  "Model 3 (without albumin, Hb)", model_3_covariates
)

table_2_models <- map(set_names(table_2_specs$covariates, table_2_specs$model),
                      ~ fit_logistic(model_data, "density_category", .x))

table_2_estimates <- imap(table_2_models, ~ density_odds_ratios(.x, model_name = .y)) |>
  list_rbind()

## ---- fit-sensitivity-models
# Without HSAs with 0 facilities (reference: category 2), and with density as
# a continuous exposure.
no_zero_data <- model_data |>
  filter(density_category != levels(density_category)[1]) |>
  mutate(density_category = droplevels(density_category))

sensitivity_estimates <- bind_rows(
  imap(set_names(table_2_specs$covariates[c(1, 4, 5)], table_2_specs$model[c(1, 4, 5)]),
       ~ density_odds_ratios(fit_logistic(no_zero_data, "density_category", .x),
                             model_name = paste(.y, "- without 0-facility HSAs"))) |>
    list_rbind(),
  imap(set_names(table_2_specs$covariates[c(1, 5)], table_2_specs$model[c(1, 5)]),
       ~ density_odds_ratios(fit_logistic(model_data, "hsa_center_density", .x),
                             term_pattern = "^hsa_center_density$",
                             model_name = paste(.y, "- continuous density"))) |>
    list_rbind()
)

## ---- fit-race-stratified-models
race_estimates <- map(c("White", "Black"), function(r) {
  stratum <- filter(model_data, race == r)
  covariates <- setdiff(model_3_covariates, "race")
  bind_rows(
    density_odds_ratios(fit_logistic(stratum, "density_category", setdiff(model_1_covariates, "race")),
                        model_name = paste(r, "- Model 1")),
    density_odds_ratios(fit_logistic(stratum, "density_category", covariates),
                        model_name = paste(r, "- Model 3 (without albumin, Hb)"))
  )
}) |>
  list_rbind()

## ---- fit-linear-models
# Continuous eGFR with the categorical exposure (eTable 2).
linear_estimates <- map(set_names(table_2_specs$covariates[c(1, 5)], table_2_specs$model[c(1, 5)]),
                        function(covariates) {
  lmer(mixed_formula("egfr", "density_category", covariates), data = model_data) |>
    broom.mixed::tidy(effects = "fixed", conf.int = TRUE) |>
    filter(grepl("^density_category", term))
}) |>
  list_rbind(names_to = "model")

## ---- fit-variance-decomposition
# Share of the variance of eGFR at the HSA and facility levels (null models).
variance_decomposition <- bind_rows(
  variance_shares(lmer(egfr ~ 1 + (1 | hsanum), data = model_data)) |>
    mutate(model = "HSA"),
  variance_shares(lmer(egfr ~ 1 + (1 | hsanum / dialysis_provider),
                       data = filter(model_data, !is.na(dialysis_provider)))) |>
    mutate(model = "HSA and facility (nested)")
)

## ---- fit-egfr-range-sensitivity
egfr_range_estimates <- model_data |>
  filter(egfr > sensitivity_egfr_range[1], egfr < sensitivity_egfr_range[2]) |>
  fit_logistic("density_category", model_3_covariates) |>
  density_odds_ratios(model_name = "Model 3 (without albumin, Hb) - eGFR 5 to 25")

## ---- fit-imputation-models
# Multiple imputation of albumin and hemoglobin by chained equations
# (open decision #D7: the imputation model below is provisional).
imputation_vars <- c("early_start", "density_category", "hsanum",
                     model_3_covariates, model_2_laboratory)
imputation_method <- make.method(select(model_data, all_of(imputation_vars)))
imputation_method[setdiff(names(imputation_method), model_2_laboratory)] <- ""
imputation_predictors <- make.predictorMatrix(select(model_data, all_of(imputation_vars)))
imputation_predictors[, "hsanum"] <- 0

imputed <- mice(select(model_data, all_of(imputation_vars)),
                m = imputation_count, method = imputation_method,
                predictorMatrix = imputation_predictors,
                seed = imputation_seed, printFlag = FALSE)

imputation_estimates <- with(imputed, glmer(
  mixed_formula("early_start", "density_category", c(model_3_covariates, model_2_laboratory)),
  family = binomial, nAGQ = glmer_nagq, control = glmerControl(optimizer = "bobyqa")
)) |>
  pool() |>
  summary(conf.int = TRUE, exponentiate = TRUE) |>
  as_tibble() |>
  filter(grepl("^density_category", term))

## ---- save-models
dir.create("models", showWarnings = FALSE)
saveRDS(
  list(table_2 = table_2_estimates, sensitivity = sensitivity_estimates,
       race = race_estimates, linear = linear_estimates,
       variance = variance_decomposition, egfr_range = egfr_range_estimates,
       imputation = imputation_estimates,
       usrds_version = as.character(packageVersion("usRds"))),
  file.path("models", "model_estimates.rds")
)

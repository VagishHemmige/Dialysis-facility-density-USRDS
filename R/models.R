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
  glmer(
    mixed_formula("early_start", exposure, covariates),
    data = data,
    family = binomial,
    nAGQ = glmer_nagq,
    control = glmerControl(optimizer = "bobyqa")
  )
}

## ---- fit-table-2-models
# Models 1 to 3; Models 2 and 3 with and without albumin and hemoglobin.
# One row per model: its name and its covariates.
table_2_specs <- tribble(
  ~model,                          ~covariates,
  "Model 1",                       model_1_covariates,
  "Model 2 (with albumin, Hb)",    c(model_2_covariates, model_2_laboratory),
  "Model 3 (with albumin, Hb)",    c(model_3_covariates, model_2_laboratory),
  "Model 2 (without albumin, Hb)", model_2_covariates,
  "Model 3 (without albumin, Hb)", model_3_covariates
)

table_2_estimates <- table_2_specs |>
  pmap(function(model, covariates) {
    model_data |>
      fit_logistic("density_category", covariates) |>
      density_odds_ratios(model_name = model)
  }) |>
  list_rbind()

## ---- fit-sensitivity-models
# Without HSAs with 0 facilities (reference: category 2), and with density as
# a continuous exposure.
no_zero_data <- model_data |>
  filter(density_category != levels(density_category)[1]) |>
  mutate(density_category = droplevels(density_category))

no_zero_estimates <- table_2_specs |>
  filter(model %in% c("Model 1", "Model 2 (without albumin, Hb)", "Model 3 (without albumin, Hb)")) |>
  pmap(function(model, covariates) {
    no_zero_data |>
      fit_logistic("density_category", covariates) |>
      density_odds_ratios(model_name = str_glue("{model} - without 0-facility HSAs"))
  }) |>
  list_rbind()

continuous_estimates <- table_2_specs |>
  filter(model %in% c("Model 1", "Model 3 (without albumin, Hb)")) |>
  pmap(function(model, covariates) {
    model_data |>
      fit_logistic("hsa_center_density", covariates) |>
      density_odds_ratios(
        term_pattern = "^hsa_center_density$",
        model_name = str_glue("{model} - continuous density")
      )
  }) |>
  list_rbind()

sensitivity_estimates <- bind_rows(no_zero_estimates, continuous_estimates)

## ---- fit-race-stratified-models
# Models 1 and 3 within White and within Black patients, without race as a
# covariate.
race_estimates <- c("White", "Black") |>
  map(function(race_group) {
    stratum <- filter(model_data, race == race_group)

    model_1 <- stratum |>
      fit_logistic("density_category", setdiff(model_1_covariates, "race")) |>
      density_odds_ratios(model_name = str_glue("{race_group} - Model 1"))

    model_3 <- stratum |>
      fit_logistic("density_category", setdiff(model_3_covariates, "race")) |>
      density_odds_ratios(model_name = str_glue("{race_group} - Model 3 (without albumin, Hb)"))

    bind_rows(model_1, model_3)
  }) |>
  list_rbind()

## ---- fit-linear-models
# Continuous eGFR with the categorical exposure (eTable 2).
linear_estimates <- table_2_specs |>
  filter(model %in% c("Model 1", "Model 3 (without albumin, Hb)")) |>
  pmap(function(model, covariates) {
    lmer(mixed_formula("egfr", "density_category", covariates), data = model_data) |>
      broom.mixed::tidy(effects = "fixed", conf.int = TRUE) |>
      filter(str_detect(term, "^density_category")) |>
      mutate(model = model, .before = 1)
  }) |>
  list_rbind()

## ---- fit-variance-decomposition
# Share of the variance of eGFR at the HSA and facility levels (null models).
hsa_variance <- lmer(egfr ~ 1 + (1 | hsanum), data = model_data) |>
  variance_shares() |>
  mutate(model = "HSA")

facility_variance <- lmer(
  egfr ~ 1 + (1 | hsanum / dialysis_provider),
  data = filter(model_data, !is.na(dialysis_provider))
) |>
  variance_shares() |>
  mutate(model = "HSA and facility (nested)")

variance_decomposition <- bind_rows(hsa_variance, facility_variance)

## ---- fit-egfr-range-sensitivity
egfr_range_estimates <- model_data |>
  filter(egfr > sensitivity_egfr_range[1], egfr < sensitivity_egfr_range[2]) |>
  fit_logistic("density_category", model_3_covariates) |>
  density_odds_ratios(model_name = "Model 3 (without albumin, Hb) - eGFR 5 to 25")

## ---- fit-imputation-models
# Multiple imputation of albumin and hemoglobin by chained equations
# (open decision #D7: the imputation model below is provisional).
imputation_vars <- c(
  "early_start", "density_category", "hsanum",
  model_3_covariates, model_2_laboratory
)
imputation_data <- select(model_data, all_of(imputation_vars))

# Only albumin and hemoglobin are imputed; the HSA is not used as a predictor
imputation_method <- make.method(imputation_data)
imputation_method[!names(imputation_method) %in% model_2_laboratory] <- ""

imputation_predictors <- make.predictorMatrix(imputation_data)
imputation_predictors[, "hsanum"] <- 0

imputed <- mice(
  imputation_data,
  m = imputation_count,
  method = imputation_method,
  predictorMatrix = imputation_predictors,
  seed = imputation_seed,
  printFlag = FALSE
)

imputation_formula <- mixed_formula(
  "early_start", "density_category", c(model_3_covariates, model_2_laboratory)
)

imputation_estimates <- imputed |>
  with(glmer(
    imputation_formula,
    family = binomial,
    nAGQ = glmer_nagq,
    control = glmerControl(optimizer = "bobyqa")
  )) |>
  pool() |>
  summary(conf.int = TRUE, exponentiate = TRUE) |>
  as_tibble() |>
  filter(str_detect(term, "^density_category"))

## ---- save-models
dir.create("models", showWarnings = FALSE)
model_estimates <- list(
  table_2 = table_2_estimates,
  sensitivity = sensitivity_estimates,
  race = race_estimates,
  linear = linear_estimates,
  variance = variance_decomposition,
  egfr_range = egfr_range_estimates,
  imputation = imputation_estimates,
  usrds_version = as.character(packageVersion("usRds"))
)
saveRDS(model_estimates, file.path("models", "model_estimates.rds"))

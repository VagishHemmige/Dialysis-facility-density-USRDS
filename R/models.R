# Purpose: fit the models behind Table 2 and eTables 1 to 3
#   (analysis-plan.md sections 8 and 9).
# Needs: cohort with density_category (define_exposure.R); model constants and
#   covariate sets (setup.R); density_odds_ratios(), mixed_formula(),
#   variance_shares() (functions.R).
# Produces: published_estimates (every model in Table 2 and eTables 1 to 3),
#   variance_decomposition, egfr_range_estimates; model_estimates (all three,
#   saved to models/).
# Fitting takes hours on the full cohort; models are saved in the ignored
#   models/ folder so tables.R can be rerun without refitting.

## ---- prepare-model-data
model_data <- cohort |>
  mutate(
    dialysis_year = factor(dialysis_year),
    density_category = relevel(density_category, ref = levels(density_category)[1])
  )

# Mixed-effects logistic regression with a random intercept for HSA.
# Difference from the paper: the paper fit these models in Stata 15, whose
# default is adaptive Gauss-Hermite quadrature with 7 points; here glmmTMB
# uses the Laplace approximation (1 point). On synthetic data the two gave the
# same odds ratios to two decimals, because each HSA has many patients, and
# glmmTMB converged without rescaling and about 30 times faster than
# lme4::glmer (decided by Vagish Hemmige, 27 October 2026).
fit_logistic <- function(data, exposure, covariates) {
  glmmTMB(
    mixed_formula("early_start", exposure, covariates),
    data = data,
    family = binomial
  )
}

## ---- define-published-models
# Every model the paper and its supplement report, one row per column of a
# published table: the table, the block of rows it sits in, the outcome
# (early start, or eGFR for eTable 3), the exposure (density category, or
# continuous density for eTable 2), the patients, whether Models 2 and 3
# include albumin and hemoglobin, and whether those two are multiply imputed.
# Model 1 never includes albumin or hemoglobin and is fit on all patients of
# its group, as in Table 2, where it is the same in both blocks.
published_rows <- function(table, block, outcome, exposure, patients, labs,
                           imputed = FALSE) {
  tibble(
    table, block, outcome, exposure, patients, labs, imputed,
    model = c("Model 1", "Model 2", "Model 3")
  )
}

published_models <- bind_rows(
  published_rows("Table 2", "With albumin and hemoglobin",
                 "early_start", "density_category", "All", labs = TRUE),
  published_rows("Table 2", "Without albumin and hemoglobin",
                 "early_start", "density_category", "All", labs = FALSE),
  published_rows("Table 2", "Without HSAs with 0 facilities",
                 "early_start", "density_category", "Without 0-facility HSAs", labs = FALSE),
  published_rows("eTable 1", "Black individuals",
                 "early_start", "density_category", "Black", labs = TRUE),
  published_rows("eTable 1", "White individuals",
                 "early_start", "density_category", "White", labs = TRUE),
  published_rows("eTable 2", "With albumin and hemoglobin",
                 "early_start", "hsa_center_density", "All", labs = TRUE),
  published_rows("eTable 2", "Without albumin and hemoglobin",
                 "early_start", "hsa_center_density", "All", labs = FALSE),
  published_rows("eTable 2", "Albumin and hemoglobin multiply imputed",
                 "early_start", "hsa_center_density", "All", labs = TRUE, imputed = TRUE),
  published_rows("eTable 2", "Black individuals, without albumin and hemoglobin",
                 "early_start", "hsa_center_density", "Black", labs = FALSE),
  published_rows("eTable 2", "White individuals, without albumin and hemoglobin",
                 "early_start", "hsa_center_density", "White", labs = FALSE),
  published_rows("eTable 3", "With albumin and hemoglobin",
                 "egfr", "density_category", "All", labs = TRUE),
  published_rows("eTable 3", "Without HSAs with 0 facilities, with albumin and hemoglobin",
                 "egfr", "density_category", "Without 0-facility HSAs", labs = TRUE)
)

# The covariates of each model; race is left out within a race group
model_covariates <- function(model, labs, patients) {
  covariates <- switch(
    model,
    "Model 1" = model_1_covariates,
    "Model 2" = model_2_covariates,
    "Model 3" = model_3_covariates
  )

  if (labs && model != "Model 1") {
    covariates <- c(covariates, model_2_laboratory)
  }
  if (patients %in% c("White", "Black")) {
    covariates <- setdiff(covariates, "race")
  }
  covariates
}

published_models <- published_models |>
  mutate(covariates = pmap(list(model, labs, patients), model_covariates))

# The patients of each group
patient_groups <- list(
  "All" = model_data,
  "White" = filter(model_data, race == "White"),
  "Black" = filter(model_data, race == "Black"),
  "Without 0-facility HSAs" = model_data |>
    filter(density_category != levels(density_category)[1]) |>
    mutate(density_category = droplevels(density_category))
)

## ---- impute-albumin-hemoglobin
# Multiple imputation of albumin and hemoglobin by chained equations, as the
# paper describes (10 imputations), used for the eTable 2 block that reports
# it. Only albumin and hemoglobin are imputed, by predictive mean matching,
# from the outcome, the density category and the Model 3 covariates. HSA is
# not a predictor (3,400 levels), and continuous density is carried along but
# not used as a predictor, because it duplicates the density category.
imputation_vars <- c(
  "early_start", "density_category", "hsa_center_density", "hsanum",
  model_3_covariates, model_2_laboratory
)
imputation_data <- select(model_data, all_of(imputation_vars))

imputation_method <- make.method(imputation_data)
imputation_method[!names(imputation_method) %in% model_2_laboratory] <- ""

imputation_predictors <- make.predictorMatrix(imputation_data)
imputation_predictors[, c("hsanum", "hsa_center_density")] <- 0

imputed_sets <- mice(
  imputation_data,
  m = imputation_count,
  method = imputation_method,
  predictorMatrix = imputation_predictors,
  seed = imputation_seed,
  printFlag = FALSE
)

## ---- fit-published-models
# One fit per distinct model; a model that appears in two blocks (Model 1 in
# both blocks of Table 2, for example) is fit once. Logistic models report
# odds ratios; the linear models of eTable 3 report differences in eGFR.
fit_published_model <- function(outcome, exposure, patients, imputed, covariates) {
  # `imputed` (TRUE or FALSE) says whether to use the imputed data sets,
  # imputed_sets
  model_family <- if (outcome == "early_start") binomial() else gaussian()
  formula <- mixed_formula(outcome, exposure, covariates)
  term_pattern <- str_glue("^{exposure}")
  logistic <- outcome == "early_start"

  if (!imputed) {
    fit <- glmmTMB(formula, data = patient_groups[[patients]], family = model_family)
    return(density_effects(fit, term_pattern, exponentiate = logistic))
  }

  # Each completed data set is fitted explicitly and the fits are pooled by
  # Rubin's rules; with(imputed_sets, ...) would not find the variables of a
  # formula built by mixed_formula()
  imputed_sets |>
    mice::complete(action = "all") |>
    map(\(completed) glmmTMB(formula, data = completed, family = model_family)) |>
    as.mira() |>
    pool() |>
    summary(conf.int = TRUE, exponentiate = logistic) |>
    as_tibble() |>
    filter(str_detect(term, term_pattern)) |>
    transmute(
      model = NA_character_,
      term = as.character(term),
      estimate,
      conf_low = `2.5 %`,
      conf_high = `97.5 %`,
      p_value = p.value,
      n = nrow(imputation_data)
    )
}

published_models <- published_models |>
  mutate(fit_key = map_chr(
    transpose(pick(outcome, exposure, patients, imputed, covariates)),
    rlang::hash
  ))

published_fits <- published_models |>
  distinct(fit_key, .keep_all = TRUE) |>
  mutate(result = pmap(
    list(outcome, exposure, patients, imputed, covariates),
    fit_published_model
  )) |>
  select(fit_key, result)

published_estimates <- published_models |>
  left_join(published_fits, by = "fit_key", relationship = "many-to-one") |>
  select(table, block, model, outcome, exposure, result) |>
  unnest(result, names_sep = "_") |>
  select(
    table, block, model, outcome, exposure,
    term = result_term,
    estimate = result_estimate,
    conf_low = result_conf_low,
    conf_high = result_conf_high,
    p_value = result_p_value,
    n = result_n
  )

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
# From the original R code, not in the paper: Model 3 among patients with eGFR
# between 5 and 25. The cohort already has eGFR of 20 or below, so in effect
# this excludes patients with eGFR of 5 or below.
egfr_range_estimates <- model_data |>
  filter(egfr > sensitivity_egfr_range[1], egfr < sensitivity_egfr_range[2]) |>
  fit_logistic("density_category", model_3_covariates) |>
  density_odds_ratios(model_name = "Model 3 (without albumin, Hb) - excluding eGFR of 5 or below")

## ---- save-models
dir.create("models", showWarnings = FALSE)
model_estimates <- list(
  published = published_estimates,
  variance = variance_decomposition,
  egfr_range = egfr_range_estimates,
  usrds_version = as.character(packageVersion("usRds"))
)
saveRDS(model_estimates, file.path("models", "model_estimates.rds"))

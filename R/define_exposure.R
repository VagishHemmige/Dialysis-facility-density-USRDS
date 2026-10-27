# Purpose: categorize HSA facility density using cut points from the final
#   cohort (analysis-plan.md section 5).
# Needs: cohort (create_cohort.R); density_percentiles (setup.R).
# Produces: density_cutpoints; cohort with density_category.

## ---- compute-cutpoints
# Percentiles of density among all patients in the cohort, zeros included,
# as in the original code. The paper reports 1.36, 1.95 and 2.76.
density_cutpoints <- unname(quantile(cohort$hsa_center_density, probs = density_percentiles))

# If a quarter or more of patients live in HSAs with no facility, the first cut
# point is 0 and category 2 would be empty; stop rather than report it.
if (density_cutpoints[1] <= 0 || anyDuplicated(density_cutpoints) > 0) {
  stop("Density cut points are not distinct and positive: ",
       paste(round(density_cutpoints, 2), collapse = ", "), call. = FALSE)
}

## ---- categorize-density
cohort <- cohort |>
  mutate(density_category = categorize_density(hsa_center_density, density_cutpoints)) |>
  set_variable_labels(density_category = "HSA facility density per 100,000 population (category)")

stopifnot(!anyNA(cohort$density_category))

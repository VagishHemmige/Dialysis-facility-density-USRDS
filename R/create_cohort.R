# Purpose: build the analytic cohort with flowchart. Every exclusion is one
#   fc_filter() step, in the order of analysis-plan.md section 4, so the
#   flow diagram and the cohort come from the same code.
# Needs: linked_forms (link_area_data.R); constants from setup.R.
# Produces: cohort_fc (the flowchart object) and cohort (one row per patient,
#   the data from the final step).

## ---- define-flowchart-labels
egfr_label <- paste0("eGFR recorded and ", if (egfr_maximum_inclusive) "≤ " else "< ",
                     egfr_maximum, " mL/min/1.73 m²")
year_label <- paste0("Medical Evidence form dated ", min(study_years), "–", max(study_years))

## ---- build-flowchart
cohort_fc <- linked_forms |>
  as_fc(label = "USRDS Medical Evidence forms") |>
  fc_filter(first_form, label = "First form per patient",
            show_exc = TRUE, label_exc = "Second or later dialysis episode") |>
  fc_filter(year %in% study_years, label = year_label, show_exc = TRUE) |>
  fc_filter(age >= minimum_age, label = paste0("Age ≥ ", minimum_age, " years"), show_exc = TRUE) |>
  fc_filter(DIALTYP == "HEMO", label = "Hemodialysis", show_exc = TRUE) |>
  fc_filter(DIALSET %in% dialysis_settings_kept,
            label = paste("Dialysis setting:", paste(str_to_lower(dialysis_settings_kept), collapse = " or ")),
            show_exc = TRUE) |>
  fc_filter(!is.na(insurance), label = "Insurance recorded", show_exc = TRUE) |>
  fc_filter(!is.na(access_type), label = "Access type recorded", show_exc = TRUE) |>
  fc_filter(!is.na(sex), label = "Sex recorded", show_exc = TRUE) |>
  fc_filter(!is.na(egfr) & (if (egfr_maximum_inclusive) egfr <= egfr_maximum else egfr < egfr_maximum),
            label = egfr_label, show_exc = TRUE) |>
  fc_filter(has_residence, label = "Residential ZIP code on the dialysis start date", show_exc = TRUE) |>
  fc_filter(has_acs, label = "ACS data for the ZIP code and year", show_exc = TRUE) |>
  fc_filter(has_facility_snapshot & year == dialysis_year,
            label = "Facility data for the dialysis start date, same year as the form",
            show_exc = TRUE) |>
  fc_filter(has_hsa, label = "ZIP code in a Health Service Area", show_exc = TRUE) |>
  fc_filter(!is.na(region) & !state %in% noncontiguous_states,
            label = "Contiguous US or District of Columbia", show_exc = TRUE) |>
  fc_filter(!is.na(race) & !is.na(hispanic), label = "Race and Hispanic ethnicity recorded",
            show_exc = TRUE) |>
  fc_filter(has_complete_acs & has_ruca, label = "Complete ACS and RUCA data for the ZIP code",
            show_exc = TRUE)

## ---- extract-cohort
cohort <- fc_view(cohort_fc, what = "data")

stopifnot(
  !anyDuplicated(cohort$USRDS_ID),
  all(cohort$hsanum == cohort$hsanum_dialysis_date)
)

# Purpose: load the USRDS Medical Evidence and Residence files through usRds
#   and derive patient-level analysis variables. No one is excluded here;
#   exclusions happen in create_cohort.R.
# Needs: setup.R, functions.R; USRDS_WD set with usRds::set_USRDS_wd().
# Produces: medevid_forms (one row per Medical Evidence form, with derived
#   variables, the first-form flag and the residence on the dialysis date).
# Restricted data: run only by an authorized person.

## ---- load-medevid
# usRds applies the USRDS value labels (Appendix C), so codes become their
# documented meanings (for example DIALSET 1 = "HOME"). PDIS is kept as the
# raw code, because several codes share a description and the cause mapping
# is by code.
medevid_columns <- c(
  "USRDS_ID", "MEFDATE", "DIALDAT", "INC_AGE", "SEX", "RACE", "ETHN",
  "DIALTYP", "DIALSET", "GFR_EPI", "SERCR", "ALBUM", "HEGLB", "WEIGHT", "HEIGHT",
  "ACCESSTYPE", "NEPHCARE", "NEPHCARERANGE", "PDIS", "CDTYPE",
  "PROVUSRD", "PROVUSRD_DIAL"
)

# Loaded whole, then narrowed: the provider ID column is PROVUSRD in older
# releases and PROVUSRD_DIAL in the 2024 Researcher's Guide.
medevid_raw <- load_usrds_file("MEDEVID", factor_labels = FALSE) |>
  select(any_of(medevid_columns), starts_with("MEDCOV_"), starts_with("COMO_"))
for (col in c("PROVUSRD", "PROVUSRD_DIAL")) {
  if (!col %in% names(medevid_raw)) medevid_raw[[col]] <- NA
}

medevid_labelled <- medevid_raw |>
  select(-PDIS) |>
  apply_usrds_factors(file_key = "MEDEVID") |>
  mutate(PDIS = str_trim(as.character(medevid_raw$PDIS)))

## ---- derive-patient-variables
medevid_forms <- medevid_labelled |>
  arrange(USRDS_ID, MEFDATE) |>
  mutate(
    form_order = row_number(),
    .by = USRDS_ID
  ) |>
  mutate(
    first_form = form_order == 1,
    year = as.integer(year(MEFDATE)),
    dialysis_year = as.integer(year(DIALDAT)),
    age = INC_AGE,
    sex = factor(str_to_title(as.character(SEX)), levels = c("Male", "Female")),
    race_detailed = as.character(RACE),
    race = factor(case_when(
      RACE == "WHITE" ~ "White",
      RACE == "BLACK" ~ "Black",
      RACE == "ASIAN" ~ "Asian",
      RACE == "AMERICAN INDIAN/ALASKAN NATIVE" ~ "Native American",
      RACE == "PACIFIC ISLANDER" ~ "Pacific Islander",
      # Open decision #D6: how these were grouped in the published tables
      RACE == "MIDEAST" ~ "Middle Eastern",
      RACE == "INDIAN SUBCO" ~ "South Asian",
      RACE == "OTHER/MULTI-RACIAL" ~ "Other",
      TRUE ~ NA_character_
    ), levels = c("White", "Black", "Asian", "Native American", "Pacific Islander",
                  "Middle Eastern", "South Asian", "Other")),
    hispanic = factor(case_when(
      ETHN %in% c("HISPANIC-MEXICAN", "HISPANIC OTHER", "HISPANIC NON-SPECIFIED") ~ "Hispanic",
      ETHN == "NON-HISPANIC" ~ "Non-Hispanic",
      TRUE ~ NA_character_
    ), levels = c("Non-Hispanic", "Hispanic")),
    egfr = GFR_EPI,
    early_start = as.integer(egfr > early_egfr_threshold),
    albumin = ALBUM,
    hemoglobin = HEGLB,
    access_type = factor(case_when(
      ACCESSTYPE == "AVF" ~ "Arteriovenous fistula",
      ACCESSTYPE == "GRAFT" ~ "Arteriovenous graft",
      ACCESSTYPE == "CATH" ~ "Catheter",
      ACCESSTYPE == "OTHER" ~ "Other",
      TRUE ~ NA_character_
    ), levels = c("Catheter", "Arteriovenous fistula", "Arteriovenous graft", "Other")),
    nephrology_care = derive_nephrology_care(NEPHCARE, NEPHCARERANGE),
    nephrology_care_any = factor(case_when(
      nephrology_care == "None" ~ "No nephrology care",
      nephrology_care == "Unknown" ~ "Unknown",
      TRUE ~ "Some nephrology care"
    ), levels = c("No nephrology care", "Some nephrology care", "Unknown")),
    insurance = factor(
      derive_insurance(MEDCOV_NONE, MEDCOV_MDCD, MEDCOV_MDCR, MEDCOV_ADVANTAGE,
                       MEDCOV_GROUP, MEDCOV_DVA, MEDCOV_OTHER),
      levels = c("Medicare or managed Medicare", "No insurance", "Medicaid",
                 "Commercial", "Other (including VA)")
    ),
    heart_failure = as.integer(any_yes(COMO_CHF)),
    coronary_disease = as.integer(any_yes(COMO_ASHD)),
    diabetes = as.integer(any_yes(COMO_DM_INS, COMO_DM_ORAL, COMO_DM_NOMEDS, COMO_DM_RET)),
    cerebrovascular_disease = as.integer(any_yes(COMO_CVATIA)),
    cancer = as.integer(any_yes(COMO_CANC)),
    alcohol_or_drug = as.integer(any_yes(COMO_ALCHO, COMO_DRUG)),
    immobility = as.integer(any_yes(COMO_INAMB, COMO_NEEDASST, COMO_INTRANS)),
    institutionalized = as.integer(any_yes(COMO_INST, COMO_INST_AL, COMO_INST_NURS, COMO_INST_OTH)),
    dialysis_provider = coalesce(as.character(PROVUSRD_DIAL), as.character(PROVUSRD))
  )

## ---- load-residence
residence <- load_usrds_file(
  "RESIDENC",
  factor_labels = TRUE,
  col_select = c("USRDS_ID", "ZIPCODE", "BEGRES", "ENDRES", "STATE")
) |>
  mutate(ZIPCODE = standardize_zip(ZIPCODE))

## ---- match-residence-to-dialysis-date
# The residence period that contains the date of dialysis start. Patients with
# no such period, or more than one, get no residence here and are excluded in
# create_cohort.R.
residence_on_dialysis_date <- medevid_forms |>
  filter(first_form) |>
  select(USRDS_ID, DIALDAT) |>
  inner_join(
    residence,
    by = join_by(USRDS_ID, between(DIALDAT, BEGRES, ENDRES)),
    relationship = "one-to-many"
  ) |>
  mutate(n_periods = n(), .by = USRDS_ID) |>
  filter(n_periods == 1) |>
  transmute(USRDS_ID, zip = ZIPCODE, state = toupper(as.character(STATE)))

medevid_forms <- medevid_forms |>
  left_join(residence_on_dialysis_date, by = "USRDS_ID", relationship = "many-to-one") |>
  mutate(
    region = assign_region(state, census_regions),
    has_residence = !is.na(zip)
  )

stopifnot(nrow(medevid_forms) == nrow(medevid_raw))

## ---- label-patient-variables
medevid_forms <- set_variable_labels(
  medevid_forms,
  first_form = "First Medical Evidence form for the patient",
  year = "Year of the Medical Evidence form (MEFDATE)",
  dialysis_year = "Year of the start of regular chronic dialysis (DIALDAT)",
  age = "Age at incidence, years",
  sex = "Sex",
  race = "Race",
  hispanic = "Hispanic ethnicity",
  egfr = "eGFR at initiation (CKD-EPI), mL/min/1.73 m2",
  early_start = "eGFR above 10 mL/min/1.73 m2 at initiation",
  albumin = "Serum albumin, g/dL",
  hemoglobin = "Serum hemoglobin, g/dL",
  access_type = "Access used at first outpatient dialysis",
  nephrology_care = "Pre-kidney-failure nephrology care (duration)",
  nephrology_care_any = "Access to pre-kidney-failure nephrology care",
  insurance = "Insurance",
  heart_failure = "Heart failure",
  coronary_disease = "Coronary disease",
  diabetes = "Diabetes",
  cerebrovascular_disease = "Cerebrovascular disease",
  cancer = "Cancer",
  alcohol_or_drug = "Alcohol or drug dependence",
  immobility = "Immobility",
  institutionalized = "Institutionalized",
  dialysis_provider = "USRDS provider ID of the dialysis facility",
  zip = "Residential ZIP code on the date of dialysis start",
  state = "Residential state on the date of dialysis start",
  region = "Census region of residence"
)

rm(medevid_raw, medevid_labelled, residence, residence_on_dialysis_date)

# Purpose: attach area-level data to each patient's first Medical Evidence form:
#   CMS facility counts on the date of dialysis start (usRds), ACS ZIP code
#   data, HSA, HSA population and benchmarks, RUCA type, cause of kidney
#   failure; and compute HSA facility density. No one is excluded here.
# Needs: medevid_forms (prepare_patients.R); zcta_crosswalk, acs_zcta, hsa_crosswalk,
#   hsa_population, ruca_zip, hsa_benchmarks (download_public_data.R);
#   esrd_cause_mapping_file (setup.R).
# Produces: linked_forms (medevid_forms with area variables and
#   availability flags used by create_cohort.R).

## ---- read-cause-mapping
# The reviewed mapping of every $PD96DET code (R/classify_esrd_causes.R).
if (!file.exists(esrd_cause_mapping_file)) {
  stop(str_glue(
    "Missing {esrd_cause_mapping_file}. Run R/classify_esrd_causes.R and review it first."
  ), call. = FALSE)
}
esrd_cause_mapping <- esrd_cause_mapping_file |>
  read_csv(col_types = cols(.default = col_character())) |>
  transmute(PDIS = code, esrd_cause = final_category) |>
  assert_unique(PDIS)

unreviewed_codes <- esrd_cause_mapping |>
  filter(!esrd_cause %in% esrd_cause_categories)

if (nrow(unreviewed_codes) > 0) {
  stop(str_glue(
    "{nrow(unreviewed_codes)} code(s) in {esrd_cause_mapping_file} have no final_category ",
    "from esrd_cause_categories (setup.R)."
  ), call. = FALSE)
}

## ---- attach-facility-counts
# usRds finds the CMS release current on each patient's dialysis start date and
# counts facilities in the patient's ZIP code and in the HSA that ZIP code
# belongs to in that calendar year. This replaces the original code's
# expansion of every facility file to one row per ZIP code per day.
facility_crosswalk <- select(hsa_crosswalk, zip, year, hsanum)

first_forms <- medevid_forms |>
  filter(first_form, has_residence) |>
  select(USRDS_ID, DIALDAT, zip) |>
  add_dialysis_facility_counts(
    date_var = "DIALDAT",
    zip_var = "zip",
    area_crosswalk = facility_crosswalk,
    area_id = "hsanum"
  ) |>
  rename(hsanum_dialysis_date = hsanum) |>
  select(-DIALDAT, -zip)

## ---- attach-area-data
# All area data are matched to the year dialysis started, the same year as the
# facility counts. The original code used the year of the form for these and
# kept only patients whose two years matched (decided 27 October 2026).
linked_forms <- medevid_forms |>
  left_join(first_forms, by = "USRDS_ID", relationship = "many-to-one") |>
  left_join(
    zcta_crosswalk,
    by = join_by(zip, dialysis_year == year),
    relationship = "many-to-one"
  ) |>
  left_join(
    acs_zcta,
    by = join_by(zcta, dialysis_year == year),
    relationship = "many-to-one"
  ) |>
  left_join(
    facility_crosswalk,
    by = join_by(zip, dialysis_year == year),
    relationship = "many-to-one"
  ) |>
  left_join(
    hsa_population,
    by = join_by(dialysis_year == year, hsanum),
    relationship = "many-to-one"
  ) |>
  left_join(hsa_benchmarks, by = "hsanum", relationship = "many-to-one") |>
  left_join(select(ruca_zip, zip, ruca1, rural_urban), by = "zip", relationship = "many-to-one") |>
  left_join(esrd_cause_mapping, by = "PDIS", relationship = "many-to-one") |>
  mutate(
    # Codes not in the mapping (blank, unknown or unreconcilable) are "Other",
    # as in the original code
    esrd_cause = factor(coalesce(esrd_cause, "Other"), levels = esrd_cause_categories)
  )

# The joins must not add or drop forms
if (nrow(linked_forms) != nrow(medevid_forms)) {
  stop("Linking area data changed the number of Medical Evidence forms.", call. = FALSE)
}

## ---- compute-density
# Facilities per 100,000 HSA residents on the date of dialysis start.
linked_forms <- linked_forms |>
  mutate(
    hsa_center_density = centers_area / hsa_population * density_per_population,
    hsa_station_density = stations_area / hsa_population * density_per_population,
    has_zcta = !is.na(zcta),
    has_acs = !is.na(zip_population),
    has_facility_snapshot = !is.na(facility_snapshot_date),
    has_hsa = !is.na(hsanum) & !is.na(hsa_center_density) & is.finite(hsa_center_density),
    has_complete_acs = if_all(all_of(acs_variables$name), \(x) !is.na(x)),
    has_ruca = !is.na(ruca1) & ruca1 != ruca_not_coded
  ) |>
  set_variable_labels(
    centers_zip = "Dialysis facilities in the ZIP code on the date of dialysis start",
    stations_zip = "Dialysis stations in the ZIP code on the date of dialysis start",
    centers_area = "Dialysis facilities in the HSA on the date of dialysis start",
    stations_area = "Dialysis stations in the HSA on the date of dialysis start",
    profit_centers_area = "For-profit dialysis facilities in the HSA on the date of dialysis start",
    nonprofit_centers_area = "Non-profit dialysis facilities in the HSA on the date of dialysis start",
    zcta = "ZCTA of the residential ZIP code (UDS Mapper crosswalk, dialysis start year)",
    hsanum = "Dartmouth Atlas HSA (crosswalk for the dialysis start year)",
    hsa_population = "HSA population (sum of ACS ZCTA populations, dialysis start year)",
    hsa_center_density = "HSA dialysis facilities per 100,000 residents",
    hsa_station_density = "HSA dialysis stations per 100,000 residents",
    rural_urban = "Rural-urban type (primary RUCA code, 2010)",
    esrd_cause = "Presumed cause of kidney failure"
  )

rm(first_forms, facility_crosswalk, esrd_cause_mapping, unreviewed_codes)

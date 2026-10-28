# Purpose: download and prepare every public area-level source.
# Needs: setup.R constants; functions.R helpers; a Census API key
#   (tidycensus::census_api_key(..., install = TRUE)).
# Produces: zcta_crosswalk, acs_zcta, hsa_crosswalk, hsa_population, ruca_zip,
#   hsa_benchmarks, hsa_boundaries. Downloads are cached in data-raw/
#   (gitignored); delete a file there to download it again.
# Uses no USRDS data.

## ---- download-public-files
dir.create(public_data_dir, showWarnings = FALSE)

# Download a file into data-raw/ unless it is already there; return its path.
download_once <- function(url, file_name) {
  path <- file.path(public_data_dir, file_name)
  if (!file.exists(path)) {
    download.file(url, path, mode = "wb", quiet = TRUE)
  }
  path
}

crosswalk_files <- map_chr(dartmouth_crosswalk_urls, \(url) download_once(url, basename(url)))
boundary_zip <- download_once(dartmouth_hsa_boundary_url, basename(dartmouth_hsa_boundary_url))
primary_care_file <- download_once(dartmouth_primary_care_url, basename(dartmouth_primary_care_url))
capacity_file <- download_once(dartmouth_capacity_url, basename(dartmouth_capacity_url))
ruca_file <- download_once(ruca_zip_url, "ruca-2010-zip.xlsx")

## ---- read-hsa-crosswalk
# One row per ZIP code and year. 2011-2017 files are .xls; 2018-2019 are
# zipped .csv. The ZIP code column is named zipcodeYY in every year.
read_crosswalk <- function(path, year) {
  crosswalk <- if (str_detect(path, "\\.zip$")) {
    read_csv(path, col_types = cols(.default = col_character()))
  } else {
    read_excel(path, col_types = "text")
  }

  crosswalk |>
    rename_with(str_to_lower) |>
    select(zip = starts_with("zipcode"), hsanum, hsastate) |>
    transmute(
      zip = standardize_zip(zip),
      year = as.integer(year),
      hsanum = as.integer(hsanum),
      hsa_state = str_to_upper(hsastate)
    )
}

hsa_crosswalk <- crosswalk_files |>
  imap(read_crosswalk) |>
  list_rbind() |>
  filter(!is.na(zip)) |>
  assert_unique(zip, year)

## ---- read-zcta-crosswalk
# ZIP code to ZCTA, by year, from the UDS Mapper crosswalks bundled in zippeR.
# About a fifth of ZIP codes (mostly PO box and large-volume ZIP codes) belong
# to a ZCTA with a different number. The original code intended this step but
# never applied it, matching ZIP codes to ZCTAs directly.
zcta_crosswalk <- study_years |>
  map(function(y) {
    zi_load_crosswalk(zip_source = "UDS", year = y) |>
      rename_with(str_to_upper) |>
      transmute(zip = standardize_zip(ZIP), year = as.integer(y), zcta = standardize_zip(ZCTA))
  }) |>
  list_rbind() |>
  filter(!is.na(zip), !is.na(zcta)) |>
  assert_unique(zip, year)

## ---- download-acs
# ZCTA estimates from ACS 5-year table S0601 for each study year. Each year's
# variable labels are checked first, because subject-table codes can change.
# The ZCTA code is the last five characters of GEOID: tidycensus 2.0.0 strips
# the two-digit state prefix from ZCTA GEOIDs only for 2013 and later, so for
# 2011-2012 GEOID may still begin with the state code.
acs_labels <- study_years |>
  map(function(y) {
    load_variables(y, "acs5/subject", cache = TRUE) |>
      filter(name %in% acs_variables$variable) |>
      transmute(year = y, name, label)
  }) |>
  list_rbind()

check_acs_labels(acs_labels, acs_variables)

acs_zcta <- study_years |>
  map(function(y) {
    get_acs(
      geography = "zcta",
      variables = set_names(acs_variables$variable, acs_variables$name),
      year = y,
      survey = "acs5",
      cache_table = TRUE
    ) |>
      transmute(zcta = str_sub(GEOID, -5), year = y, variable, estimate)
  }) |>
  list_rbind() |>
  pivot_wider(names_from = variable, values_from = estimate) |>
  assert_unique(zcta, year)

## ---- compute-hsa-population
# HSA population: the population of the ZCTAs of the ZIP codes the Dartmouth
# crosswalk assigns to the HSA that year, each ZCTA counted once.
hsa_population <- hsa_population_from_zcta(
  hsa_crosswalk,
  zcta_crosswalk,
  select(acs_zcta, zcta, year, zip_population)
)

## ---- read-ruca
# Primary RUCA code of each ZIP code (2010 file), grouped into four types.
ruca_zip <- read_excel(ruca_file, sheet = "Data", col_types = "text") |>
  rename_with(str_to_upper) |>
  transmute(zip = standardize_zip(ZIP_CODE), ruca1 = as.numeric(RUCA1)) |>
  left_join(ruca_groups, by = "ruca1", relationship = "many-to-one") |>
  mutate(rural_urban = factor(rural_urban, levels = unique(ruca_groups$rural_urban))) |>
  assert_unique(zip)

## ---- read-dartmouth-benchmarks
# HSA primary care measures (2015) and hospital resources (2012). The measure
# columns are found by the patterns in setup.R; -88888 and -99999 become NA.
read_dartmouth_hsa <- function(path, patterns) {
  table <- read_header_table(path, header_pattern = "^HSA")
  id_column <- select_by_pattern(table, c(hsanum = "^hsa[ _.]?(num|id|code)?$"), basename(path))
  measure_columns <- select_by_pattern(table, patterns, basename(path))

  table |>
    select(all_of(id_column), all_of(measure_columns)) |>
    mutate(
      hsanum = as.integer(hsanum),
      across(-hsanum, \(x) clean_dartmouth_codes(x, dartmouth_missing_codes))
    ) |>
    filter(!is.na(hsanum))
}

hsa_benchmarks <- full_join(
  read_dartmouth_hsa(primary_care_file, dartmouth_primary_care_measures),
  read_dartmouth_hsa(capacity_file, dartmouth_capacity_measures),
  by = "hsanum",
  relationship = "one-to-one"
)

## ---- read-hsa-boundaries
# HSA boundaries for maps (figures.R only).
boundary_dir <- file.path(public_data_dir, "hsa_boundaries")
if (!dir.exists(boundary_dir)) {
  unzip(boundary_zip, exdir = boundary_dir)
}

hsa_boundaries <- list.files(boundary_dir, pattern = "\\.shp$", full.names = TRUE, recursive = TRUE) |>
  first() |>
  read_sf() |>
  rename_with(str_to_lower) |>
  transmute(hsanum = as.integer(hsa93)) |>
  st_make_valid()

## ---- label-area-variables
acs_zcta <- acs_zcta |>
  set_variable_labels(
    zip_population = "ZCTA total population (ACS 5-year)",
    zip_percent_female = "ZCTA % female (ACS 5-year)",
    zip_percent_white = "ZCTA % White (ACS 5-year)",
    zip_percent_black = "ZCTA % Black (ACS 5-year)",
    zip_percent_asian = "ZCTA % Asian (ACS 5-year)",
    zip_percent_hispanic = "ZCTA % Hispanic (ACS 5-year)",
    zip_median_income = "ZCTA median household income, dollars (ACS 5-year)",
    zip_percent_poverty = "ZCTA % below poverty level (ACS 5-year)"
  )

hsa_benchmarks <- hsa_benchmarks |>
  set_variable_labels(
    hsa_ambulatory_sensitive_discharges = "HSA discharges for ambulatory-sensitive conditions per 1,000 enrollees (2015)",
    hsa_leg_amputations = "HSA leg amputations per 1,000 Medicare enrollees with diabetes (2015)",
    hsa_percent_eye_exam = "HSA % of enrollees with diabetes with an annual eye exam (2015)",
    hsa_percent_hba1c = "HSA % of enrollees with diabetes with HbA1c testing (2015)",
    hsa_percent_mammogram = "HSA % of women with a mammogram in 2 years (2015)",
    hsa_acute_care_beds = "HSA acute care hospital beds per 1,000 residents (2012)",
    hsa_hospital_fte = "HSA hospital FTE employees per 1,000 residents (2012)"
  )

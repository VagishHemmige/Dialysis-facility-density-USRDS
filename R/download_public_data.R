# Purpose: download and prepare every public area-level source.
# Needs: setup.R constants; functions.R helpers; a Census API key
#   (tidycensus::census_api_key(..., install = TRUE)).
# Produces: acs_zcta, hsa_crosswalk, hsa_population, ruca_zip,
#   hsa_benchmarks, hsa_boundaries. Downloads are cached in data-raw/
#   (gitignored); delete a file there to download it again.
# Uses no USRDS data.

## ---- download-public-files
dir.create(public_data_dir, showWarnings = FALSE)

download_once <- function(url, dest) {
  dest <- file.path(public_data_dir, dest)
  if (!file.exists(dest)) utils::download.file(url, dest, mode = "wb", quiet = TRUE)
  dest
}

crosswalk_files <- imap_chr(dartmouth_crosswalk_urls, function(url, year) {
  download_once(url, basename(url))
})
boundary_zip <- download_once(dartmouth_hsa_boundary_url, basename(dartmouth_hsa_boundary_url))
primary_care_file <- download_once(dartmouth_primary_care_url, basename(dartmouth_primary_care_url))
capacity_file <- download_once(dartmouth_capacity_url, basename(dartmouth_capacity_url))
ruca_file <- download_once(ruca_zip_url, "ruca-2010-zip.xlsx")

## ---- read-hsa-crosswalk
# One row per ZIP code and year. 2011-2017 files are .xls; 2018-2019 are
# zipped .csv. The ZIP column is named zipcodeYY in every year.
read_crosswalk <- function(path, year) {
  df <- if (grepl("\\.zip$", path)) {
    read_csv(path, col_types = cols(.default = col_character()))
  } else {
    read_excel(path, col_types = "text")
  }
  names(df) <- tolower(names(df))
  zip_col <- grep("^zipcode", names(df), value = TRUE)
  stopifnot(length(zip_col) == 1, all(c("hsanum", "hsastate") %in% names(df)))
  tibble(
    zip = standardize_zip(df[[zip_col]]),
    year = as.integer(year),
    hsanum = as.integer(df$hsanum),
    hsa_state = toupper(df$hsastate)
  )
}

hsa_crosswalk <- imap(crosswalk_files, read_crosswalk) |>
  list_rbind() |>
  filter(!is.na(zip))

stopifnot(!anyDuplicated(hsa_crosswalk[c("zip", "year")]))

## ---- download-acs
# ZCTA estimates from ACS 5-year table S0601 for each study year. The ZCTA
# code is read from the NAME field ("ZCTA5 12345"), as in the original code,
# and used as the ZIP code.
acs_labels <- map(study_years, function(y) {
  load_variables(y, "acs5/subject", cache = TRUE) |>
    filter(name %in% acs_variables$variable) |>
    transmute(year = y, name, label)
}) |>
  list_rbind()

check_acs_labels(acs_labels, acs_variables)

acs_zcta <- map(study_years, function(y) {
  get_acs(
    geography = "zcta",
    variables = set_names(acs_variables$variable, acs_variables$name),
    year = y,
    survey = "acs5",
    cache_table = TRUE
  ) |>
    transmute(zip = str_extract(NAME, "\\d{5}$"), year = y, variable, estimate)
}) |>
  list_rbind() |>
  pivot_wider(names_from = variable, values_from = estimate)

stopifnot(!anyDuplicated(acs_zcta[c("zip", "year")]))

## ---- compute-hsa-population
# HSA population: sum of ZCTA population over the ZIP codes the crosswalk
# assigns to the HSA that year. ZIP codes without an ACS ZCTA add nothing.
hsa_population <- hsa_crosswalk |>
  left_join(select(acs_zcta, zip, year, zip_population),
            by = join_by(zip, year), relationship = "one-to-one") |>
  group_by(year, hsanum) |>
  summarize(hsa_population = sum(zip_population, na.rm = TRUE), .groups = "drop")

## ---- read-ruca
# Primary RUCA code of each ZIP code (2010 file), grouped into four types.
ruca_zip <- read_excel(ruca_file, sheet = "Data", col_types = "text") |>
  rename_with(toupper) |>
  transmute(zip = standardize_zip(ZIP_CODE), ruca1 = as.numeric(RUCA1)) |>
  left_join(ruca_groups, by = "ruca1", relationship = "many-to-one") |>
  mutate(rural_urban = factor(rural_urban, levels = unique(ruca_groups$rural_urban)))

stopifnot(!anyDuplicated(ruca_zip$zip))

## ---- read-dartmouth-benchmarks
# HSA primary care measures (2015) and hospital resources (2012). Columns are
# found by the patterns in setup.R; -88888 and -99999 become NA.
read_dartmouth_hsa <- function(path, patterns) {
  df <- read_header_table(path, header_pattern = "^HSA")
  id_col <- grep("^hsa[ _.]?(num|id|code)?$", names(df), ignore.case = TRUE, value = TRUE)
  if (length(id_col) != 1) stop("No single HSA id column in ", basename(path), ": ",
                                paste(names(df), collapse = ", "), call. = FALSE)
  cols <- select_by_pattern(df, patterns, basename(path))
  tibble(hsanum = as.integer(df[[id_col]])) |>
    bind_cols(map(cols, ~ clean_dartmouth_codes(df[[.x]], dartmouth_missing_codes))) |>
    filter(!is.na(hsanum))
}

hsa_benchmarks <- read_dartmouth_hsa(primary_care_file, dartmouth_primary_care_measures) |>
  full_join(read_dartmouth_hsa(capacity_file, dartmouth_capacity_measures),
            by = "hsanum", relationship = "one-to-one")

## ---- read-hsa-boundaries
# HSA boundaries for maps (figures.R only).
boundary_dir <- file.path(public_data_dir, "hsa_boundaries")
if (!dir.exists(boundary_dir)) utils::unzip(boundary_zip, exdir = boundary_dir)
hsa_boundaries <- read_sf(list.files(boundary_dir, pattern = "\\.shp$", full.names = TRUE, recursive = TRUE)[1]) |>
  rename_with(tolower) |>
  transmute(hsanum = as.integer(hsa93)) |>
  st_make_valid()

## ---- label-area-variables
acs_zcta <- set_variable_labels(
  acs_zcta,
  zip_population = "ZCTA total population (ACS 5-year)",
  zip_percent_female = "ZCTA % female (ACS 5-year)",
  zip_percent_white = "ZCTA % White (ACS 5-year)",
  zip_percent_black = "ZCTA % Black (ACS 5-year)",
  zip_percent_asian = "ZCTA % Asian (ACS 5-year)",
  zip_percent_hispanic = "ZCTA % Hispanic (ACS 5-year)",
  zip_median_income = "ZCTA median household income, dollars (ACS 5-year)",
  zip_percent_poverty = "ZCTA % below poverty level (ACS 5-year)"
)
hsa_benchmarks <- set_variable_labels(
  hsa_benchmarks,
  hsa_ambulatory_sensitive_discharges = "HSA discharges for ambulatory-sensitive conditions per 1,000 enrollees (2015)",
  hsa_leg_amputations = "HSA leg amputations per 1,000 Medicare enrollees with diabetes (2015)",
  hsa_percent_eye_exam = "HSA % of enrollees with diabetes with an annual eye exam (2015)",
  hsa_percent_hba1c = "HSA % of enrollees with diabetes with HbA1c testing (2015)",
  hsa_percent_mammogram = "HSA % of women with a mammogram in 2 years (2015)",
  hsa_acute_care_beds = "HSA acute care hospital beds per 1,000 residents (2012)",
  hsa_hospital_fte = "HSA hospital FTE employees per 1,000 residents (2012)"
)

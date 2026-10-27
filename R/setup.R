# Purpose: attach packages and define every constant shared by the scripts.
# Needs: nothing. Produces: attached packages and named constants.
# USRDS data are located only through usRds (the USRDS_WD environment variable,
# set once with usRds::set_USRDS_wd()). Public downloads are cached in data-raw/.

## ---- load-packages
library(tidyverse)
library(labelled)
library(usRds)        # USRDS files, value labels, CMS facility snapshots
library(flowchart)    # cohort flow: every exclusion is an fc_filter() step
library(tidycensus)   # American Community Survey (needs a Census API key)
library(zippeR)       # ZIP code to ZCTA crosswalks by year (UDS Mapper)
library(readxl)
library(sf)
library(lme4)
library(broom.mixed)
library(gtsummary)
library(gt)
library(mice)

## ---- define-study-constants
# Cohort (analysis-plan.md section 4): years in which dialysis started
study_years <- 2011:2019
minimum_age <- 18

# Dialysis setting codes kept (format $MESET: 1 = HOME, 2 = DIALYSIS FACILITY/CENTER).
# The original code kept both; the paper says home dialysis was excluded.
# Open decision #D1; default reproduces the original code.
dialysis_settings_kept <- c("HOME", "DIALYSIS FACILITY/CENTER")

# eGFR restriction (mL/min/1.73 m2): 20 or below, as in the original code
# (the paper says "less than 20"; decided 27 October 2026)
egfr_maximum <- 20

# Outcome (section 7): early initiation is eGFR of 10 or above, as in the
# original code (the paper says "greater than 10"; decided 27 October 2026)
early_egfr_threshold <- 10

# Sensitivity analysis: eGFR range from the original code (exclusive bounds)
sensitivity_egfr_range <- c(5, 25)

# States outside the 48 contiguous states + DC; territories have no region
noncontiguous_states <- c("ALASKA", "HAWAII")

## ---- define-exposure-constants
# Exposure (section 5): facilities per this many HSA residents
density_per_population <- 100000
# Cut points: these percentiles of density among patients in the final cohort
density_percentiles <- c(0.25, 0.50, 0.75)

## ---- define-linkage-constants
# ACS 5-year subject table S0601 variables, with a pattern each year's label
# must match. R/download_public_data.R stops if any year's label does not match.
acs_variables <- tribble(
  ~name,                    ~variable,        ~label_pattern,
  "zip_population",         "S0601_C01_001",  "Total population",
  "zip_percent_female",     "S0601_C01_012",  "Female",
  "zip_percent_white",      "S0601_C01_014",  "White",
  "zip_percent_black",      "S0601_C01_015",  "Black",
  "zip_percent_asian",      "S0601_C01_017",  "Asian",
  "zip_percent_hispanic",   "S0601_C01_021",  "Hispanic",
  "zip_median_income",      "S0601_C01_047",  "[Mm]edian",
  "zip_percent_poverty",    "S0601_C01_049",  "[Pp]overty"
)

# Dartmouth Atlas codes that are not values: -88888 too small, -99999 suppressed.
# The original code made them positive; here they are NA (decided 27 October 2026).
dartmouth_missing_codes <- c(-88888, -99999)

# Census regions by state (USRDS STATE is labelled with format $STATFIP)
census_regions <- list(
  Northeast = c("CONNECTICUT", "MAINE", "MASSACHUSETTS", "VERMONT", "NEW HAMPSHIRE",
                "NEW YORK", "PENNSYLVANIA", "RHODE ISLAND", "NEW JERSEY"),
  Midwest = c("NORTH DAKOTA", "SOUTH DAKOTA", "NEBRASKA", "KANSAS", "MINNESOTA", "IOWA",
              "MISSOURI", "WISCONSIN", "ILLINOIS", "MICHIGAN", "INDIANA", "OHIO"),
  South = c("OKLAHOMA", "TEXAS", "ARKANSAS", "LOUISIANA", "KENTUCKY", "TENNESSEE",
            "MISSISSIPPI", "ALABAMA", "WEST VIRGINIA", "MARYLAND", "DELAWARE",
            "DISTRICT OF COLUMBIA", "VIRGINIA", "NORTH CAROLINA", "SOUTH CAROLINA",
            "GEORGIA", "FLORIDA"),
  West = c("WASHINGTON", "OREGON", "CALIFORNIA", "IDAHO", "NEVADA", "ARIZONA", "UTAH",
           "MONTANA", "WYOMING", "COLORADO", "NEW MEXICO"),
  Pacific = c("ALASKA", "HAWAII")
)

# Primary RUCA code groups (ERS), the four rural-urban types in the paper's Table 1
ruca_groups <- tribble(
  ~ruca1, ~rural_urban,
  1,      "Metropolitan",
  2,      "Metropolitan",
  3,      "Metropolitan",
  4,      "Micropolitan",
  5,      "Micropolitan",
  6,      "Micropolitan",
  7,      "Small town",
  8,      "Small town",
  9,      "Small town",
  10,     "Rural"
)
ruca_not_coded <- 99  # zero-population ZIP code

## ---- define-download-locations
public_data_dir <- "data-raw"

dartmouth_crosswalk_urls <- c(
  `2011` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr11.xls",
  `2012` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr12.xls",
  `2013` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr13.xls",
  `2014` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr14.xls",
  `2015` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr15.xls",
  `2016` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr16.xls",
  `2017` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr17.xls",
  `2018` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr18.csv.zip",
  `2019` = "https://data.dartmouthatlas.org/downloads/geography/ZipHsaHrr19.csv.zip"
)
dartmouth_hsa_boundary_url <-
  "https://data.dartmouthatlas.org/downloads/geography/HSA_Bdry__AK_HI_unmodified.zip"
dartmouth_primary_care_url <-
  "https://data.dartmouthatlas.org/downloads/tables/PC_HSA_rates_2015.xls"
dartmouth_capacity_url <-
  "https://data.dartmouthatlas.org/downloads/tables/2012_hosp_resource_hsa.xls"
ruca_zip_url <-
  "https://www.ers.usda.gov/media/5439/2010-rural-urban-commuting-area-codes-zip-code-file.xlsx?v=90697"

# Dartmouth column patterns (regular expressions, matched case-insensitively).
# Each must match exactly one column; R/download_public_data.R stops otherwise.
dartmouth_primary_care_measures <- c(
  hsa_ambulatory_sensitive_discharges = "ambulatory.*sensitive|ACSC",
  hsa_leg_amputations = "amputation",
  hsa_percent_eye_exam = "eye",
  hsa_percent_hba1c = "a1c",
  hsa_percent_mammogram = "mammo"
)
dartmouth_capacity_measures <- c(
  hsa_acute_care_beds = "acute.*bed",
  hsa_hospital_fte = "FTE|employee"
)

## ---- define-cause-constants
# Primary cause of kidney failure (section 6). The mapping of every $PD96DET code
# is in references/esrd-cause-categories.csv (open decision #D4).
esrd_cause_categories <- c(
  "Diabetes",
  "Hypertension and cardiac disease",
  "Glomerulonephritis",
  "Hereditary or polycystic kidney disease",
  "Transplant failure or complications",
  "Other"
)
esrd_cause_mapping_file <- "references/esrd-cause-categories.csv"

# Models used by R/classify_esrd_causes.R: the same three providers as the
# USRDS-PDF-analysis-project ensemble, each provider's current general-purpose
# model as of October 2026 (the abstract used gpt-5.1, claude-sonnet-4-5 and
# gemini-2.5-flash). The models used are recorded in the output file.
esrd_classifier_models <- list(
  openai = "gpt-6.1-terra",
  anthropic = "claude-sonnet-5-5",
  google = "gemini-3.8-flash"
)
esrd_classifier_batch_size <- 100
# A category is accepted when at least this many of the three models give it
# (2 of 3; decided by Vagish Hemmige, 27 October 2026). Other codes go to the
# deciders.
esrd_classifier_min_agreement <- 2
esrd_classifier_prompt_file <- "prompts/esrd-cause-classification.md"
# Output limit for Claude. ellmer 0.5.0 caps Claude's answers at 4,096 tokens
# unless told otherwise, too few for a batch of 100 codes with reasons; the
# other providers have no default cap in ellmer.
esrd_classifier_claude_max_tokens <- 16000
# Each provider's checked answers are saved here (gitignored), so a rerun does
# not pay for a provider that already finished
esrd_votes_dir <- file.path(public_data_dir, "esrd-cause-votes")

## ---- define-model-constants
# Mixed-effects logistic models (section 8). nAGQ = 1 is the Laplace
# approximation; the original R code used 0. Open decision #D6.
glmer_nagq <- 1
imputation_count <- 10
imputation_seed <- 20231020

# Covariates added at each step of Table 2 (section 8; open decision #D6)
# Year of hemodialysis initiation, as the paper's Methods say; the original R
# code used the year of the form (decided 27 October 2026)
model_1_covariates <- c("age", "sex", "race", "hispanic", "dialysis_year")
model_2_covariates <- c(model_1_covariates,
                        "heart_failure", "coronary_disease", "diabetes",
                        "cerebrovascular_disease", "alcohol_or_drug", "immobility",
                        "institutionalized", "access_type", "esrd_cause")
model_2_laboratory <- c("albumin", "hemoglobin")
model_3_covariates <- c(model_2_covariates,
                        "insurance", "nephrology_care", "rural_urban",
                        "zip_percent_poverty", "zip_percent_black",
                        "hsa_ambulatory_sensitive_discharges",
                        "hsa_percent_eye_exam", "hsa_percent_hba1c")

## ---- define-output-paths
tables_dir <- "tables"
figures_dir <- "figures"

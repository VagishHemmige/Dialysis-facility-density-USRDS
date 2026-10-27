# Purpose: run the definitive analysis in dependency order.
# Run from the project root in a fresh session, by a person authorized to use
# the USRDS data. Before the first run:
#   1. usRds::set_USRDS_wd("<folder with the USRDS files>", permanent = TRUE)
#   2. tidycensus::census_api_key("<key>", install = TRUE)
#   3. references/esrd-cause-categories.csv exists and is reviewed
#      (R/classify_esrd_causes.R, run once by hand).

source("R/setup.R")
source("R/functions.R")
source("R/download_public_data.R")   # public area data; no USRDS data
source("R/prepare_patients.R")       # USRDS Medical Evidence and Residence files
source("R/link_area_data.R")         # facilities, ACS, HSA, RUCA, cause of kidney failure
source("R/create_cohort.R")          # flowchart: every exclusion
source("R/define_exposure.R")        # density categories
source("R/models.R")                 # Table 2 and sensitivity analyses (slow)
source("R/tables.R")
source("R/figures.R")

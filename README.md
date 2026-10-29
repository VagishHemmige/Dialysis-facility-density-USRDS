
<!-- README.md is generated from README.Rmd. Please edit that file -->
<!-- badges: start -->

[![Status](https://img.shields.io/badge/status-replication_in_progress-yellow)](#)
[![Paper](https://img.shields.io/badge/JAMA_Netw_Open-2024-blue)](https://doi.org/10.1001/jamanetworkopen.2023.50009)
<!-- badges: end -->

# Dialysis facility density and early dialysis initiation: a replication

This repository replicates the analysis of a published cross-sectional
study of 844,466 incident hemodialysis patients in the US Renal Data
System (USRDS), which found that patients in Hospital Service Areas
(HSAs, which the paper calls health service areas) with more dialysis
facilities per resident started hemodialysis at a higher eGFR:

> Hemmige V, Deshpande P, Norris KC, Shen JI, Erickson KF, Johansen KL,
> Golestaneh L. Geographic dialysis facility density and early dialysis
> initiation. *JAMA Network Open*. 2024;7(1):e2350009.
> [doi:10.1001/jamanetworkopen.2023.50009](https://doi.org/10.1001/jamanetworkopen.2023.50009)

The original analysis was a single R Markdown file of more than 3,000
lines. This version rebuilds it with
[usRds](https://vagishhemmige.github.io/usRds/),
[flowchart](https://bruigtp.github.io/flowchart/) and
[tidycensus](https://walker-data.com/tidycensus/), corrects errors found
along the way, and documents every difference from the original code.

The analysis website, which explains the code step by step, is at:
<https://vagishhemmige.github.io/Dialysis-facility-density-USRDS/>

## Documentation

- [`analysis-plan.md`](analysis-plan.md): what the analysis is meant to
  do
- [`ARCHITECTURE.md`](ARCHITECTURE.md): how the code is organized
- [`AGENTS.md`](AGENTS.md): how to work in this repository
- [Issues](https://github.com/VagishHemmige/Dialysis-facility-density-USRDS/issues):
  open decisions and known gaps

## Running the analysis

Requires authorized access to the USRDS Medical Evidence and Residence
files, located through the usRds package, and a usRds version that
includes `add_dialysis_facility_counts()`.

1.  Point usRds at the USRDS files once:
    `usRds::set_USRDS_wd("<folder>", permanent = TRUE)`.
2.  Install a Census API key once:
    `tidycensus::census_api_key("<key>", install = TRUE)`.
3.  Create and review `references/esrd-cause-categories.csv` by running
    `R/classify_esrd_causes.R` once (needs OpenAI, Anthropic and Google
    API keys, and Ollama with the two local models).
4.  Run `R/main.R` from the project root.

Public area data are downloaded to `data-raw/` on the first run. Tables
and figures are written to `tables/` and `figures/`, which stay out of
Git until they are checked and cleared for release under the USRDS data
use agreement.

The helper functions are tested on synthetic data:
`testthat::test_file("tests/test-functions.R")`.

# Architecture

The current implementation: scripts, data flow, and the objects passed between them. Written by hand for the first version of the repository (October 2026); regenerate with the Posit describe-design skill when the structure changes.

## Running order

`R/main.R` sources the definitive scripts in this order. Each script runs in the global environment and leaves the objects listed for later scripts.

| Order | Script | Needs | Produces | Data |
|---|---|---|---|---|
| 1 | `R/setup.R` | — | Attached packages; every constant | — |
| 2 | `R/functions.R` | Packages | Helper functions | — |
| 3 | `R/download_public_data.R` | Constants, helpers | `zcta_crosswalk`, `acs_zcta`, `hsa_crosswalk`, `hsa_population`, `ruca_zip`, `hsa_benchmarks`, `hsa_boundaries` | Public; cached in `data-raw/` |
| 4 | `R/prepare_patients.R` | Constants, helpers | `medevid_forms` (one row per Medical Evidence form, with derived variables and residence on the dialysis date) | USRDS, through usRds |
| 5 | `R/link_area_data.R` | 3, 4; `references/esrd-cause-categories.csv` | `linked_forms` (area variables, facility counts, density, availability flags) | USRDS + public |
| 6 | `R/create_cohort.R` | 5 | `cohort_fc` (flowchart), `cohort` (one row per patient) | USRDS |
| 7 | `R/define_exposure.R` | 6 | `density_cutpoints`; `cohort` with `density_category` | USRDS |
| 8 | `R/models.R` | 7 | Estimate tibbles; `models/model_estimates.rds` | USRDS (aggregate estimates) |
| 9 | `R/tables.R` | 7, 8 | `table_1`; HTML files in `tables/` | Outputs, gitignored |
| 10 | `R/figures.R` | 3, 6 | PNG files in `figures/` | Outputs, gitignored |

`R/classify_esrd_causes.R` is not sourced by `main.R`. It is run once by hand, after `setup.R` and `functions.R`, and writes `references/esrd-cause-categories.csv` from the public `$PD96DET` code list. It calls three paid APIs, one function per provider, and sends no patient data. The prompt is `prompts/esrd-cause-classification.md`. Each provider's checked answers are saved in `data-raw/esrd-cause-votes/` (gitignored), named by provider, model and a fingerprint of the prompt, so a rerun pays only for providers that have not finished with the current prompt.

## Data flow

```
USRDS MEDEVID ──┐
USRDS RESIDENC ─┴─ prepare_patients.R ── medevid_forms ──┐
                                                          │
CMS facility snapshots (usRds) ──────────────────────────┤
ACS (tidycensus), ZCTA crosswalk (zippeR) ── download_public_data.R ──┐           ├─ link_area_data.R ── linked_forms
Dartmouth, RUCA (publisher URLs) ────────────┴───────────┤
references/esrd-cause-categories.csv ────────────────────┘
                                                          │
                          create_cohort.R (flowchart) ── cohort_fc, cohort
                                                          │
                          define_exposure.R ── cohort + density_category
                                                          │
                    models.R ── estimates ── tables.R ── tables/
                                                          │
                                             figures.R ── figures/
```

## Key mechanisms

- **Labels from the source documentation.** `usRds::load_usrds_file()` and `apply_usrds_factors()` turn USRDS codes into their Appendix C meanings. Filters compare against those labels (for example `DIALSET %in% dialysis_settings_kept`). `PDIS` is kept as the raw code for the cause mapping.
- **Facility counts by date.** `usRds::add_dialysis_facility_counts()` matches each patient's `DIALDAT` to the CMS release in effect (an interval join on `valid_from`/`valid_to`), then counts facilities in the ZIP code and in its HSA for that calendar year. Rows never multiply; dates outside coverage give `NA`.
- **Cohort and diagram from one object.** Every exclusion is an `fc_filter()` call on `linked_forms`; `cohort` is `fc_view(cohort_fc, what = "data")`. No script removes patients elsewhere.
- **Joins state their relationship.** Every join of area data to patients is `many-to-one`; a duplicate key stops the run.
- **ZIP codes reach ACS through ZCTAs.** Each ZIP code is mapped to its ZCTA with the UDS Mapper crosswalk for the form year (`zippeR`); HSA population counts each ZCTA once (`hsa_population_from_zcta()`).
- **Public inputs are checked.** ACS labels are checked for every year (`check_acs_labels()`); Dartmouth columns are found by pattern and must match exactly one column (`select_by_pattern()`).

## Dependencies outside this repository

- **usRds**: needs the version containing `dialysis_facility_snapshots`, `add_dialysis_facility_counts()` and `summarize_dialysis_facilities()`, which is under review in the usRds project. `R/classify_esrd_causes.R` reads the internal `usRds:::metadata_c` until the package exports its format tables.
- **Census API key** for tidycensus; **API keys** for OpenAI, Anthropic and Google for the one-time classification.

## Website

`_quarto.yml` and `index.qmd` at the root; one page per definitive script in `quarto/`, plus background, differences, the original file and about. Pages import code from `R/` with `knitr::read_chunk()` and never evaluate it. The site renders to `docs/`.

## Tests

`tests/test-functions.R` tests every helper in `R/functions.R` on synthetic data with known answers, including the ensemble functions with a fake chat object.

# Architecture

The current implementation: scripts, data flow, and the objects passed between them. Refreshed with the Posit describe-design skill on 29 October 2026 against every script in `R/`, and the site's `quarto/` folder, on `main` at commit cfff842, with no uncommitted changes. Regenerate it with the same skill when the structure changes.

## Running order

`R/main.R` sources the definitive scripts in this order. Each script runs in the global environment and leaves the objects listed for later scripts.

| Order | Script | Needs | Produces | Data |
|---|---|---|---|---|
| 1 | `R/setup.R` | — | Attached packages; every constant | — |
| 2 | `R/functions.R` | Packages | Helper functions | — |
| 3 | `R/download_public_data.R` | Constants, helpers | `zcta_crosswalk`, `acs_zcta`, `hsa_crosswalk`, `hsa_population`, `ruca_zip`, `hsa_benchmarks`, `hsa_boundaries` | Public; cached in `data-raw/` |
| — | `R/classify_esrd_causes.R` (commented out in `main.R`; run once by hand) | Constants, helpers; the public `$PD96DET` code list (usRds); API keys and Ollama | `references/esrd-cause-categories.csv`, `references/esrd-cause-agreement.csv`, `references/esrd-cause-local-models.csv` | Public code list only |
| 4 | `R/prepare_patients.R` | Constants, helpers | `medevid_forms` (one row per Medical Evidence form, with derived variables and residence on the dialysis date) | USRDS, through usRds |
| 5 | `R/link_area_data.R` | 3, 4; `references/esrd-cause-categories.csv`; usRds facility snapshots | `linked_forms` (area variables, facility counts, density, availability flags) | USRDS + public |
| 6 | `R/create_cohort.R` | 5 | `cohort_fc` (flowchart), `cohort` (one row per patient) | USRDS |
| 7 | `R/define_exposure.R` | 6 | `density_cutpoints`; `cohort` with `density_category` | USRDS |
| 8 | `R/models.R` | 7 | `published_models`, `published_estimates`, `variance_decomposition`, `egfr_range_estimates`, `model_estimates`; `models/model_estimates.rds` | USRDS (aggregate estimates) |
| 9 | `R/tables.R` | 7, 8 (or the saved estimates) | `table_1`, `published_tables`; HTML files in `tables/` | Outputs, gitignored |
| 10 | `R/figures.R` | 3, 6; usRds facility snapshots (`summarize_dialysis_facilities()`) | PNG files in `figures/` | Outputs, gitignored |

`R/classify_esrd_causes.R` sits in `main.R` after `download_public_data.R` as a commented-out line: it calls paid APIs, so an authorized person runs it once by hand. From the public `$PD96DET` code list it writes the three `references/` files in its row above; the deciders review the mapping, and `link_area_data.R` reads only that reviewed file. Which models vote, the agreement rule, saved answers and the safeguards for the review are described on its [site page](https://vagishhemmige.github.io/Dialysis-facility-density-USRDS/quarto/classify_esrd_causes.html).

## Data flow

```
USRDS MEDEVID, RESIDENC ──── prepare_patients.R ──── medevid_forms ─────┐
                                                                         │
ACS (tidycensus), ZCTA crosswalk (zippeR),                               │
Dartmouth Atlas, RUCA (publisher URLs) ── download_public_data.R ── area ┤
                                                                         │
CMS facility snapshots (usRds) ──────────────────────────────────────────┤
                                                                         │
$PD96DET code list (usRds) ── classify_esrd_causes.R (by hand, once)     │
  └── references/esrd-cause-categories.csv, reviewed by the deciders ────┤
                                                                         ▼
                                              link_area_data.R ── linked_forms
                                                                         │
                                  create_cohort.R (flowchart) ── cohort_fc, cohort
                                                                         │
                                  define_exposure.R ── cohort + density_category
                                                                         │
                       models.R ── model_estimates ── tables.R ── tables/
                                                                         │
             area data, facility snapshots, cohort_fc ── figures.R ── figures/
```

## Key mechanisms

- **Labels from the source documentation.** `usRds::load_usrds_file()` and `apply_usrds_factors()` turn USRDS codes into their Appendix C meanings. Filters compare against those labels (for example `DIALSET %in% dialysis_settings_kept`). `PDIS` is kept as the raw code for the cause mapping.
- **Facility counts by date.** `usRds::add_dialysis_facility_counts()` matches each patient's `DIALDAT` to the CMS release in effect (an interval join on `valid_from`/`valid_to`), then counts facilities in the ZIP code and in its HSA for that calendar year. Rows never multiply; dates outside coverage give `NA`.
- **Cohort and diagram from one object.** Every exclusion is an `fc_filter()` call on `linked_forms`; `cohort` is `fc_view(cohort_fc, what = "data")`. No script removes patients elsewhere. `fc_filter()` re-evaluates each condition as text, so conditions use only columns and global constants.
- **Joins state their relationship.** Every join of area data to patients is `many-to-one`; a duplicate key stops the run.
- **ZIP codes reach ACS through ZCTAs.** Each ZIP code is mapped to its ZCTA with the UDS Mapper crosswalk for the year dialysis started (`zippeR`); HSA population counts each ZCTA once (`hsa_population_from_zcta()`).
- **Public inputs are checked.** ACS labels are checked for every year (`check_acs_labels()`); Dartmouth columns are found by pattern and must match exactly one column (`select_by_pattern()`).
- **Cause codes.** `link_area_data.R` reads `code` and `final_category` from the mapping, stops if a code lacks one of the six categories, and warns with the share of first forms whose cause code is not in the mapping; those count as Other.
- **Published models from one list.** `models.R` builds `published_models`, one row per published table, block and model; models shared between blocks are fit once (by a hash of their specification) with `glmmTMB`, and imputed models are pooled across the completed data sets. The variance decomposition fits two null linear mixed models of eGFR with `lme4::lmer()` (HSA, and facility nested in HSA) on the same patients, those with a facility ID, and `variance_shares()` turns each into shares of variance.

## Dependencies outside this repository

- **usRds**: needs the version containing `dialysis_facility_snapshots`, `add_dialysis_facility_counts()` and `summarize_dialysis_facilities()`, which is under review in the usRds project. `R/classify_esrd_causes.R` reads the internal `usRds:::metadata_c` until the package exports its format tables.
- **Packages used without being attached**: `ellmer`, `irr` and `rlang` (classification), `broom.mixed` (estimates).
- **Census API key** for tidycensus; **API keys** for OpenAI, Anthropic and Google, and **Ollama** with the two local models, for the one-time classification.

## Website

`_quarto.yml` and `index.qmd` at the root; one page per definitive script in `quarto/`, plus background, differences, results, supplement, the original file and about. Four pages show the project documents (`analysis-plan.qmd`, `architecture.qmd`, `agents.qmd`, `repository-blueprint.qmd`); each only includes its file from the repository root, which stays the one source, so the plan's citations resolve on the site. Pages import code from `R/` with `knitr::read_chunk()` and never evaluate it. Helpers used only by the pages are in `quarto/_site_functions.R`: `side_by_side_diff()` for before-and-after code comparisons, and `rmd_as_markdown()`, which shows the original R Markdown file on its page as formatted text with each chunk folded, without running anything. Their style is in `styles.css`, and `main.R` never sources them. The site renders to `docs/`, which is not committed: `.github/workflows/publish.yml` renders it on every pull request as a check and, on each push to `main`, renders it and publishes it to the `gh-pages` branch, which GitHub Pages serves.

## Tests

`tests/test-functions.R` tests the helpers in `R/functions.R` on synthetic data with known answers, including the classification helpers with fake provider functions in place of the models. Two helpers are not tested there: `read_header_table()`, and `map_panel()`, which is checked by the synthetic run of `figures.R`. `density_category_labels()` is tested through `categorize_density()`, which uses it to name the five density categories. `format_estimates_table()` is tested only where gt is installed. `tests/test-model-example.R` checks that the model written out on the models page is the one the code fits for Table 2, Model 3, using only constants from `setup.R`. `tests/test-site-functions.R` tests the site helpers. `tests/check-crosslinks.R` is not a test file but a check the publish workflow runs on every pull request: it reads the scripts and the pages and fails if the functions page and the method pages do not link each other as the code says.

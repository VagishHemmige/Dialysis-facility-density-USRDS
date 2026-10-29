# AGENTS.md

Guidance for everyone working on this repository: the maintainer, collaborators, and any AI agents working for them. It covers how to work here: conventions, data handling, and checks.

Four places divide the documentation:

| Where | Covers |
|---|---|
| `analysis-plan.md` | Study design and statistics: what the analysis is meant to do |
| `ARCHITECTURE.md` | Code structure: scripts, data flow, and the objects passed between them |
| `AGENTS.md` (this file) | How to work in the repository: rules, conventions, and checks |
| [GitHub Issues](https://github.com/VagishHemmige/Dialysis-facility-density-USRDS/issues) | Open scientific decisions (decision issues), gaps between code and plan, and known defects |

Read the three files before making changes. Each covers its own topic and does not repeat the others.

## The project

This repository replicates a published cross-sectional study of USRDS incident hemodialysis patients, which found that higher dialysis facility density in a patient's Hospital Service Area (HSA; the paper calls it a health service area) was associated with starting hemodialysis at a higher eGFR (Hemmige et al., JAMA Netw Open 2024, doi:10.1001/jamanetworkopen.2023.50009). The original analysis was one R Markdown file of more than 3,000 lines (kept, with local paths removed, in `original/`). This version rebuilds it with `usRds` and `flowchart`, corrects errors found along the way, and documents each difference. Code and methods are published as a Quarto website.

- **`analysis-plan.md` is the source of truth for design.** Code implements the plan; it does not redefine it. If code needs to depart from the plan, open a decision issue, or comment on the existing one, for the deciders. Once a decider has settled it (in the issue, or relayed there in their exact words), the plan change and the code can go in the same pull request, which closes the issue.
- **Deciders.** Scientific decisions are made by Vagish Hemmige and Ladan Golestaneh, in any area. Anyone may open or contribute to a decision issue; only a decider settles it (see "Working with agents").
- **Replication rule.** The original code is evidence of what was done, not the specification. When it disagrees with the paper or contains an error, do not silently copy it or silently fix it: the plan's section 12 and the site's "Differences from the original code" page record every difference, and choices between the paper and the code go to a decision issue.
- **This is an analysis project, not an R package.** Do not add DESCRIPTION, NAMESPACE, roxygen, or pkgdown infrastructure, or apply CRAN conventions.
- **Default branch:** `main`, protected. Changes reach it only through pull requests.

## Data sources

Each source this project uses is listed below with the package that accesses it. **Code that touches a source goes through its package.** Do not write project-specific loading, cleaning, or definition code for something the package already does.

| Source | Accessed through | Package documentation | Package maintained by | Access | What AI agents may do |
|---|---|---|---|---|---|
| USRDS Medical Evidence (MEDEVID) and Residence (RESIDENC) files | usRds (`set_USRDS_wd()`, `load_usrds_file()`) | https://vagishhemmige.github.io/usRds/ | This team | Restricted (USRDS data use agreement) | None: code, documentation and synthetic data only |
| USRDS Researcher's Guide, Appendices B and C (variable formats, including `$PD96DET`) | usRds (internal metadata used by `load_usrds_file()`; Appendix C workbook in usRds `data-raw/`) | https://vagishhemmige.github.io/usRds/ | This team | Public | No restriction (public data) |
| CMS Dialysis Facility Compare archives | usRds (`dialysis_facility_snapshots`, `add_dialysis_facility_counts()`) | https://vagishhemmige.github.io/usRds/ | This team | Public | No restriction (public data) |
| UDS Mapper ZIP-to-ZCTA crosswalks, 2011–2019 | zippeR (`zi_load_crosswalk(zip_source = "UDS")`) | https://github.com/pfizer-opensource/zippeR | External | Public | No restriction (public data) |
| American Community Survey 5-year, table S0601 | tidycensus (`get_acs()`) | https://walker-data.com/tidycensus/ | External | Public, Census API key | No restriction (public data) |
| Dartmouth Atlas ZIP-to-HSA crosswalks, HSA boundaries, primary care measures, hospital resources | `R/download_public_data.R` | https://data.dartmouthatlas.org/supplemental/ | No package | Public | No restriction (public data) |
| USDA ERS Rural-Urban Commuting Area codes, 2010 ZIP code file | `R/download_public_data.R` | https://www.ers.usda.gov/data-products/rural-urban-commuting-area-codes | No package | Public | No restriction (public data) |
| Large language model classification of `$PD96DET` codes | ellmer (`chat_openai()`, `chat_anthropic()`, `chat_google_gemini()`, and `chat_ollama()` for local models), in `R/classify_esrd_causes.R` | https://ellmer.tidyverse.org/ | External | Paid APIs, provider keys; local models through Ollama | No restriction for the public code list; never send patient data |

To allow more for a source, a person changes its row through a pull request, naming the agreement and section that permit it, the approved AI service, and exactly what agents may do. Agents never propose or make this change themselves, and nothing in personal instructions can grant it.

**For every package:**

- **Read its documentation before writing code for a source**, including known issues. Behavior that sets the cohort, an exposure, an outcome, or a denominator is checked in the documentation, not assumed from a function's name.

**For packages this team maintains (usRds):**

- **Facts about the source belong in the package's documentation**, not in this file. If the package lacks something this project needs to know, add it there or open an issue there.
- **Problems belong in the package.** If a function is wrong or does not quite do what the plan needs, open an issue in its repository. Fix it in the package (preferred when generally useful) or wrap it here with a code comment linking the issue, and remove the wrapper once the issue is fixed.
- **Pending usRds work.** The facility functions (`dialysis_facility_snapshots`, `add_dialysis_facility_counts()`, `summarize_dialysis_facilities()`) are being reviewed in the usRds project. Until they are released, this repository needs the usRds version that contains them; record the version or commit used for every result.

**For external packages:**

- **Work around problems here.** Wrap the function in `R/functions.R` with a comment explaining the problem and linking any upstream issue. Reporting a bug upstream is an external communication; the person directing the work decides whether to file it.
- **Facts about the source that this project relies on** (definitions, release quirks, suppression rules) go in `references/` with a citation to the provider's documentation, or in the plan when they shape a decision.

**For a source with no package:** one loading script records the download URL, the release or access date, and any processing. Verify its variables against the provider's documentation for that release.

- Dartmouth Atlas files code small values as -88888 and suppressed values as -99999; these are set to missing, never used as numbers.
- ACS subject-table (S0601) variable codes can change between years; `R/download_public_data.R` checks each year's labels before use.

## Exploration and definitive analysis

Exploration is welcome on branches or forks. Experimental scripts need not be sourced from `R/main.R` or have Quarto pages, and their findings are labelled preliminary. A script becomes part of the definitive analysis when it is sourced from `R/main.R`; from then on every rule below applies to it.

`R/classify_esrd_causes.R` has its place in `main.R`, after the public data, but its line there is commented out: it is run once, by hand, by an authorized person, because it calls paid APIs; its reviewed output in `references/` is what the analysis reads. It has a Quarto page because the mapping is part of the definitive analysis.

## R scripts

- **Running the analysis.** Run `R/main.R` from the project root. It sources the other scripts in dependency order; `ARCHITECTURE.md` describes what each does.
- **One job per script.** When you add a definitive script, source it from `main.R` at the right point and update `ARCHITECTURE.md` in the same pull request.
- **Header comment.** Each script begins with what it does, which objects it needs from earlier scripts, and what it produces.
- **Constants, libraries, and code lists** live in `R/setup.R`. Other scripts do not call `library()`, re-source `setup.R`, or hard-code values. Any number a reader might want to change (a window, a year, a threshold, a ratio) is a named constant there.
- **Helper functions** go in `R/functions.R`. A function takes its inputs as arguments and does not read global objects.
- **No side effects outside the project.** No `setwd()`, absolute paths, or writes outside the project. USRDS data are located only through `usRds` (the `USRDS_WD` environment variable set by `set_USRDS_wd()`). Public downloads are cached in the ignored `data-raw/` folder.
- **No results in the repository.** No script (exploratory or definitive) or comment, commit message, issue, pull-request text or review report contains results, counts or data values from USRDS data unless they are cleared for release. Check before every commit and post, since a public repository publishes everything pushed to it, on any branch. Numbers quoted from the published paper are public and may be cited.

## Chunk labels

Scripts are divided into labelled sections so Quarto pages can show the code without copying it:

```r
## ---- <step-name>
```

- Every logical step has a label. A label covers the code from its line to the next label.
- Labels are kebab-case, describe the step, and are **unique across all scripts**; a duplicate silently picks up the wrong code.
- Search the `.qmd` files before renaming or deleting a label.
- Labels are comments and never change what the code does.

## Variable labels

Label analysis variables with human-readable descriptions. USRDS variables get their labels from `load_usrds_file(var_labels = TRUE)`; derived variables are labelled where they are created with `labelled::set_variable_labels()`, with units and the year or date they refer to.

## Quarto website

The site documents the code. It does not run the analysis.

- `_quarto.yml` and `index.qmd` sit at the root; `quarto/` has one page per definitive script, named after it. The `custom-callout` extension in `_extensions/` provides the `Rcode` callout.
- Each page loads its script with `knitr::read_chunk("../R/<script>.R")` in a hidden chunk and shows each labelled section with `#| eval: false`, with prose explaining what the section does and why. Pages link to the script on GitHub and to the scripts it depends on.
- **Never evaluate analysis code in the site.** Pages render without restricted data.
- **Site-only helpers** live in `quarto/_site_functions.R`, which pages source and `main.R` never does. They read only code or text given to them, never data, and are tested in `tests/test-site-functions.R`. A chunk calling them (for example `side_by_side_diff()`, which shows two versions of some code side by side) is the only other kind of chunk a page may run. Helpers the analysis needs stay in `R/functions.R`.
- The original R Markdown file is shown on its own page as code only, with machine-specific paths removed.
- The site renders to `docs/` and is served by GitHub Pages. When you add a script, add its page and sidebar entry in the same pull request, and re-render.
- **Prose must match the code.** If a change alters what a section does, update its explanation in the same pull request.

## Outputs

- Tables and figures are exported by `R/tables.R` and `R/figures.R` to `tables/` and `figures/`. They are gitignored until they have been checked for errors against the published paper and cleared for release under the USRDS data use agreement.
- Published figures need alt text.
- `README.Rmd` is the source of `README.md`; edit the `.Rmd` and re-knit.

## Restricted data (applies to everyone)

The **Access** column of "Data sources" says which sources are restricted. For each restricted source:

- **Never commit data**, extracts, or saved objects or outputs derived from patient-level records. Keep data outside the repository, and check `.gitignore` before adding a new output type.
- **AI agents never read restricted data.** Anything an agent opens, prints, or summarizes is sent to the model provider. Agents do not open data files or patient-level objects, print rows, or display identifiers, person-level dates, or small geographies (including ZIP codes linked to patients). Agents also do not open outputs from restricted data that are not yet cleared for release (`tables/` and `figures/` while they are ignored). Agents write code, review it, and run it on **synthetic data**; results on real data are produced by an authorized person.
- **No patient data to model providers.** The cause-of-kidney-failure classification sends only the public `$PD96DET` code list. Never send codes chosen from, counted in, or filtered by patient data.
- **Synthetic data** are built in code, labelled as synthetic, and never derived from real records.
- **Disclosure.** Under the USRDS data use agreement, no count from 1 to 10 is published in a table, figure, flowchart box, or prose, including counts recoverable by subtraction or from complementary cells. Check every output before it leaves the approved environment, including scripts, comments, commit messages, issues, pull-request text and review reports (see R scripts).
- **Credentials and paid APIs.** Never commit keys, tokens, or `.Renviron`. Ask before paid, bulk, or uncached API calls.

## Coding conventions

- **Cohort flow** uses the `flowchart` package, so the STROBE flow diagram and the analytic cohort come from the same code. Every inclusion or exclusion goes through `fc_filter()`, in the plan's order. Never remove people from the cohort outside the flowchart. Record-level processing (choosing a person's first Medical Evidence form, choosing the residence period that contains the dialysis date) is fine. An analysis that uses fewer people than the cohort (complete cases, a subgroup) reports its own number with that analysis. The cohort used downstream is the data from the final step (`fc_view(what = "data")`). Flowchart labels are built from constants in `setup.R`.
- **Code lists** carry each code's category, code system and version, and matching rule (exact or prefix). Check every code against the official code set. Never invent codes, variables, files, or definitions.
- **Joins** use `join_by()` with an explicit `relationship` where possible. After every interval join and every join of records to people, assert that rows did not multiply, and decide deliberately what happens to unmatched rows.
- **Dates and windows** are written as inclusive bounds, matching the plan, and the edges are tested on synthetic data.
- **Code that turns model output into reported numbers** lives in named functions in `R/functions.R`, tested on synthetic data with a known answer.
- **Style:** readable tidyverse code, following the tidyverse style guide. Transform data with dplyr pipelines (`|>`), one step per line; use stringr (`str_glue()`, `str_flatten()`, `str_to_upper()`) rather than `paste()`, `sprintf()` or `toupper()`; purrr (`map()`, `pmap()`, `list_rbind()`) rather than `for` loops or `sapply()`; `case_when(.default = )` rather than nested `ifelse()`; `\(x)` rather than `~ .x`. Select models, rows and columns by name, never by position. Checks are a `filter()` of the problem rows followed by `stop()` with a message that says what failed (or `assert_unique()` for keys), not bare `stopifnot()`. Long calls put one argument per line. Style changes go in their own commits.

## Checks for any change

Check the items that apply before opening a pull request.

- **Plan:** does the change implement the plan as written, and does it leave every open decision open?
- **Data sources:** does it use the access package's functions, and does their documented behavior match what the plan needs?
- **Cohort:** do the flowchart steps' order, denominators, and labels match their conditions, and can each count be reproduced from code?
- **Joins and denominators:** no unintended row multiplication; missing, suppressed, and zero kept distinct.
- **Reported numbers:** does each estimate match the plan's estimand, and do tables, figures, and site prose say what the code actually computes?
- **Structure:** is `ARCHITECTURE.md` current; are chunk labels unique and found by their pages; does every definitive script have a page and sidebar entry; does any site chunk run analysis code? Only the hidden `read_chunk()` import, calls to the site helpers, and results pages reading outputs cleared for release, run.
- **Execution:** does `main.R` run in a fresh session with relative paths; are any saved intermediates or caches stale?

Project-specific checks:

- **Replication:** does every difference from the original code appear in the plan's section 12 and on the differences page, and is each one either a correction of an error or linked to a decision issue?
- **Geography and dates:** are ACS, crosswalk and population matched to the year the plan specifies, and facility counts to the date of dialysis start? Are ZIP codes 5-character strings with leading zeros kept?
- **Denominators:** is HSA population summed over the ZCTAs of the ZIP codes the crosswalk assigns to the HSA for that year, each ZCTA once, and are HSAs with no facilities kept as zero, not missing?
- **Area codes:** are Dartmouth -88888 and -99999 codes missing, and are ACS variable labels checked for every year used?

## Working with agents

- **Autonomy.** The person directing an agent decides how much it may do, and may give it stricter rules of their own; those take precedence. By default an agent may edit code and documentation, add scripts and tests, run code and render the site on synthetic data, and commit to a branch and open a pull request.
- **Decisions.** Anyone, including an agent, may add options and evidence to a decision issue. A decider states the choice in the issue. Agents implement decisions; they never choose among options on their own, in the issue, the plan, or the code.
- **Every agent, under any autonomy:** never merges a pull request; follows the restricted-data rules; asks before running the full pipeline or making expensive calls; and shows a person the exact text before posting or sending anything as them, unless that person's own instructions waive this.
- **Pull requests opened by an agent** are focused. Each says which plan section or issue it addresses, what was checked, and whether by running code on synthetic data or by reading only. Synthetic results are never described as results.
- **References:** cite the source documentation and literature used, in `references.bib`.

# Analysis plan: Replication of "Geographic Dialysis Facility Density and Early Dialysis Initiation"

Status: draft.

## Scope and reporting framework

This document is the authoritative specification of the study's scientific objectives, population, definitions, estimands and statistical methods. `ARCHITECTURE.md` documents the implementation, `AGENTS.md` the working conventions, and GitHub Issues the open decisions and implementation status. Neither file supersedes this plan.

This is a replication. The design is the one published in JAMA Network Open [@hemmige2024density], and every choice the paper states is treated as decided and cited to it. The original analysis code (an R Markdown file from October 2023, kept in `original/`) is the second source: where it makes a choice the paper does not state, the plan adopts the code's choice and says so. Where the code and the paper disagree, or the code contains an error, the point is marked **Open** and linked to a decision issue for the deciders. Each such point is also listed on the website's "Differences from the original code" page.

Reporting will follow STROBE [@vonelm2007strobe] and RECORD [@benchimol2015record]. The reporting map below links each checklist item to a section of this plan.

## 1. Objective

To test whether the density of dialysis facilities in a patient's Hospital Service Area (HSA; the paper calls it a health service area) is associated with starting in-center hemodialysis early, defined as an estimated glomerular filtration rate (eGFR) of 10 mL/min/1.73 m² or above at initiation (section 7) [@hemmige2024density].

- **Primary hypothesis (stated in advance by the paper):** patients in HSAs with higher facility density have higher odds of initiating hemodialysis at eGFR > 10 mL/min/1.73 m².
- **Secondary:** the same association with eGFR as a continuous outcome; with density as a continuous exposure; within strata of race (White, Black).
- **Exploratory:** the share of variation in eGFR at initiation explained by HSA and by dialysis facility.
- **Replication objective:** to reproduce the paper's Figure 1 (cohort flow), Table 1, Table 2 and eTables 1 to 3 from public code, using `usRds` and `flowchart`, and to quantify the effect of each correction to the original code.

## 2. Design

Cross-sectional study of incident hemodialysis patients linked to area-level data [@hemmige2024density]. The question is associational; no causal estimand or target-trial emulation is used.

## 3. Data source

| Source | Content used | Release or year | Linkage |
|---|---|---|---|
| USRDS Medical Evidence file (MEDEVID) | CMS-2728 form: demographics, comorbidities, laboratory values, access, insurance, primary cause of kidney failure, eGFR | Release held by the investigators, covering forms dated 2011 to 2019; variable definitions from the 2024 Researcher's Guide [@usrds2024guide] | `USRDS_ID` |
| USRDS Residence file (RESIDENC) | Residential ZIP code and state over time | Same release | `USRDS_ID`, date of dialysis start within the residence period |
| CMS Dialysis Facility Compare archives | Facility ZIP code, stations, ownership, by release | December 2005 to April 2025, via `usRds::dialysis_facility_snapshots` [@cms2025dfc] | ZIP code and date of dialysis start |
| UDS Mapper ZIP-to-ZCTA crosswalk | ZCTA of each ZIP code | 2011 to 2019, matched to the year dialysis started, via `zippeR` [@uds_crosswalk; @zipper_pkg] | ZIP code and year |
| American Community Survey (ACS) 5-year, subject table S0601 | ZCTA population, % female, % White, % Black, % Asian, % Hispanic, median income, % below poverty | Each year 2011 to 2019, matched to the year dialysis started [@tidycensus] | ZCTA (from the crosswalk) and year |
| Dartmouth Atlas ZIP-to-HSA crosswalks | HSA of each ZIP code | 2011 to 2019, matched to the year [@dartmouth_crosswalks] | ZIP code and year |
| Dartmouth Atlas primary care measures | HSA ambulatory-sensitive discharges, leg amputations, diabetic eye exams, HbA1c testing, mammography | 2015 [@dartmouth_primarycare] | HSA |
| Dartmouth Atlas hospital resources | HSA acute care beds and hospital FTE employees per 1,000 | 2012 [@dartmouth_capacity] | HSA |
| USDA ERS Rural-Urban Commuting Area codes | Primary RUCA code of each ZIP code | 2010 ZIP code file [@ers2020ruca] | ZIP code |

**Secondary-data declaration.** The investigators have analyzed this USRDS release before: it is the release used for the published paper, and the published results are known. Every result of this replication is therefore a reproduction, not a new test of the hypothesis.

**Data currency.** The facility snapshot current on each patient's date of dialysis start is used; a snapshot describes facilities from its CMS release date until the day before the next release.

## 4. Study population

**Source population:** every patient with a CMS-2728 Medical Evidence form in the USRDS.

**Index event:** start of regular chronic dialysis (`DIALDAT`) on the patient's first Medical Evidence form.

**Eligibility, in order.** Each step is one box of the cohort flowchart. Steps 1 to 9 come from the paper and the original code; steps 10 to 16 are linkage and completeness requirements from the original code.

1. First Medical Evidence form per patient (earliest `MEFDATE`); later forms describe a second or later dialysis episode.
2. Dialysis started (`DIALDAT`) 2011 to 2019, as the paper states. The paper starts in 2011 because of the IDEAL trial [@cooper2010ideal]. The original code used the year of the form (`MEFDATE`), applying the lower bound explicitly and the upper bound only implicitly, through the ACS linkage (decided by Vagish Hemmige, 27 October 2026).
3. Age 18 or older at incidence (`INC_AGE`).
4. Hemodialysis as the primary type of dialysis (`DIALTYP` = hemodialysis).
5. In-center dialysis: `DIALSET` "Dialysis facility/center". The paper excludes patients who began home dialysis. The original code kept codes 1 and 2, which excluded home dialysis in the coding of the time (Appendix C format `$MESET_CUR`: 1 hospital inpatient, 2 dialysis facility/center, 3 home; 14,380 patients excluded in the published Figure 1). The current coding (format `$MESET`, 2024 Researcher's Guide) has 1 = home and 2 = dialysis facility/center, so the replication keeps code 2 only, the same intent in the current coding (decided by Vagish Hemmige, 27 October 2026).
6. Insurance status recorded (at least one coverage field marked yes).
7. Vascular access type at first outpatient dialysis recorded (`ACCESSTYPE` not unknown).
8. Sex recorded.
9. eGFR at initiation recorded and no higher than 20 mL/min/1.73 m², as in the original code (decided by Vagish Hemmige, 27 October 2026, in a working session: "Use the code"). The paper says "less than 20", and its Figure 1 labels the 38,708 excluded patients "eGFR <20". As in the original code, missing eGFR is removed in the same step.
10. A residential ZIP code in effect on the date of dialysis start (RESIDENC period containing `DIALDAT`), unique per patient.
11. The ZIP code has a ZCTA in the UDS Mapper crosswalk for the year dialysis started, and ACS data are available for that ZCTA and year. The original code intended this crosswalk but never applied it, matching ZIP codes to ZCTAs directly; the replication applies it (decided by Vagish Hemmige, 27 October 2026, in a working session: "I intended at some point to cross-walk this but never did").
12. A facility snapshot current on the date of dialysis start. The original code's facility join also required the year of the form to match the year dialysis started; the replication drops that requirement (see "Year of linkage" below).
13. An HSA for the ZIP code in the crosswalk for the year dialysis started.
14. Residence in the 48 contiguous states or the District of Columbia (excludes Alaska, Hawaii, territories, and states not assigned a Census region).
15. Race recorded (not unknown) and Hispanic ethnicity recorded (not unknown).
16. ZIP code has a RUCA code other than 99 (zero-population ZIP code) and complete ACS covariates.

The original code applied several of these filters outside its CONSORT table, and its table misreported others; see section 12. In this replication every exclusion is a flowchart step, so the diagram reproduces the cohort exactly.

**Year of linkage.** All area data (ZCTA crosswalk, ACS, HSA, HSA population) are matched to the year dialysis started (`DIALDAT`), the same year as the facility counts. The original code matched area data to the year of the Medical Evidence form (`MEFDATE`) and its facility join silently required the two years to be equal; the replication corrects this (decided by Vagish Hemmige, 27 October 2026).

## 5. Exposure

**HSA dialysis facility density:** the number of dialysis facilities in the patient's HSA on the date of dialysis start, divided by the HSA's population, times 100,000 [@hemmige2024density].

- **Facilities:** every facility listed in the CMS release current on the date of dialysis start (`usRds::add_dialysis_facility_counts()`), assigned to an HSA by its ZIP code and the crosswalk for that calendar year. Facilities whose ZIP code has no HSA are not counted.
- **HSA population:** the ACS total population of the ZCTAs of the ZIP codes in the HSA, using the Dartmouth and ZCTA crosswalks and ACS for the year dialysis started. Each ZCTA is counted once per HSA, because several ZIP codes can share a ZCTA. ZCTAs without ACS data contribute nothing.
- **Categories:** 0 facilities; then cut at the 25th, 50th and 75th percentiles of density among all patients in the final cohort (zeros included), each category including its upper bound. The paper reports cut points of 1.36, 1.95 and 2.76 per 100,000 [@hemmige2024density].
- **Continuous version:** density per 100,000, for sensitivity analyses.
- **Also described:** facility stations per 100,000, and for-profit and non-profit facility counts.

## 6. Covariates

All patient covariates are measured on the first Medical Evidence form, at initiation. Area covariates are fixed for the patient's ZIP code or HSA as described in section 3.

| Covariate | Definition |
|---|---|
| Age | `INC_AGE`, years |
| Sex | `SEX` |
| Race | `RACE` (format `$MERACE`), reported in the paper's five groups: White, Black, Asian, Native American, Pacific Islander. The five published counts sum to each column's total, so the form's Middle Eastern, South Asian and Other/multiracial codes were merged into those groups in the Stata analysis; how is not recorded. Here Middle Eastern counts as White and South Asian as Asian (1997 OMB race standard), and Other/multiracial as White, the largest group (chosen for this demonstration at Vagish Hemmige's request, 27 October 2026). |
| Hispanic ethnicity | `ETHN`: Hispanic (codes 1, 2, 5) vs non-Hispanic (code 3) |
| Year | Year dialysis started (`DIALDAT`), "year of hemodialysis initiation" in the paper; the original R code used the year of `MEFDATE` (decided by Vagish Hemmige, 27 October 2026) |
| Comorbidities | Heart failure (`COMO_CHF`); coronary disease (`COMO_ASHD`); diabetes (any of `COMO_DM_INS`, `COMO_DM_ORAL`, `COMO_DM_NOMEDS`, `COMO_DM_RET`); cerebrovascular disease (`COMO_CVATIA`); cancer (`COMO_CANC`); alcohol or drug dependence (`COMO_ALCHO`, `COMO_DRUG`); immobility (`COMO_INAMB`, `COMO_NEEDASST`, `COMO_INTRANS`); institutionalized (`COMO_INST`, `COMO_INST_AL`, `COMO_INST_NURS`, `COMO_INST_OTH`). Each is "yes" when any listed field is yes |
| Access type | `ACCESSTYPE`: AV fistula, AV graft, catheter, other |
| Access to pre-kidney-failure nephrology care | `NEPHCARE`: none, some, unknown (unknown or blank kept as its own level), as in the paper's Table 1 and the Model 3 footnote (decided by Vagish Hemmige, 27 October 2026, in a working session). The duration (`NEPHCARERANGE`) is not used. |
| Insurance | Hierarchy as in the original code: none; else Medicaid (including dual eligibility); else Medicare or Medicare Advantage; else employer group; else other (including VA) |
| Serum albumin, hemoglobin | `ALBUM` (g/dL), `HEGLB` (g/dL) |
| Primary cause of kidney failure | `PDIS` mapped to six categories: diabetes; hypertension and cardiac disease; glomerulonephritis; hereditary or polycystic kidney disease; transplant failure or complications; other (including unknown and unmapped codes). **Open:** D4, the mapping (see below and "Open decisions") |
| ZIP code poverty, % Black residents | ACS S0601, for the ZIP code's ZCTA and the year dialysis started |
| Rural-urban type | Primary RUCA code grouped as metropolitan (1 to 3), micropolitan (4 to 6), small town (7 to 9) and rural (10) [@ers2020ruca], the four groups in the paper's Table 1 |
| Census region | From the residence state |
| HSA quality benchmarks | Ambulatory-sensitive discharges per 1,000 enrollees; percentage of diabetic enrollees with an eye exam (2015) and with HbA1c testing (2015); percentage of women with a mammogram in 2 years; leg amputations per 1,000 [@dartmouth_primarycare]. Hospital beds and FTE employees per 1,000 [@dartmouth_capacity] are described but not in the models. Dartmouth codes -88888 and -99999 are set to missing; the original code turned them into positive values (decided by Vagish Hemmige, 27 October 2026, in a working session). |

**Cause of kidney failure mapping.** The original mapping spreadsheet is no longer available. The replacement maps every code of USRDS format `$PD96DET` [@usrds2024guide], a public list of about 445 ICD-9 and ICD-10 codes with descriptions, to the six categories above. Five large language models, called through `ellmer` (0.5.0 or later, the first version that sends current Claude models a native structured-output request) [@ellmer_pkg] with the same prompt and a structured output schema, each classify every code, and every model's answers pass the same check: three cloud models (from OpenAI, Anthropic and Google) and two run locally through Ollama, Alibaba's Qwen and IBM's Granite, so that the five come from unrelated companies (decided by Vagish Hemmige, 28 October 2026). A code is accepted when at least three of the five models agree (decided by Vagish Hemmige, 28 October 2026, replacing two of three; the rule was chosen because the classification demonstrates the method rather than being the main analysis); codes so accepted are not read by a person, and every other code is reviewed by the deciders, who record the category and their initials (`reviewer`). Agreement among the models is reported with Fleiss' kappa in a one-row public summary (`references/esrd-cause-agreement.csv`), together with the number of codes accepted unanimously, by majority only and not at all; kappa is descriptive and plays no part in accepting codes. The reviewed mapping is committed to `references/` and is the only version the analysis reads. No patient data are given to any model; the local models send nothing over the internet. Patient-level cross-checks against USRDS's own disease group (`DISGRPC`, PATIENTS file) and against the published Table 1 counts are run by an authorized person. The prompt defines each category in words, starting from the 12 groups of the 2015 CMS-2728 list of primary causes [@cms2728_causes] and the original spreadsheet's sheet names: glomerulonephritis includes secondary glomerulonephritis (lupus nephritis, ANCA vasculitis, anti-GBM disease, Henoch-Schönlein purpura) and infection-related glomerular disease (post-infectious glomerulonephritis, HIV-associated nephropathy, hepatitis-associated and cryoglobulinemic glomerulonephritis), while other infections are in Other (decided by Vagish Hemmige, 27 October 2026). HIV-associated nephropathy is thereby counted as glomerulonephritis, unlike in the CMS-2728 grouping, where HIV disease is a miscellaneous condition. The definitions are shown on the website. **Open:** D4, whether a model-drafted, clinician-reviewed mapping is acceptable for the replication.

## 7. Outcome

**Primary:** eGFR at initiation (`GFR_EPI`, CKD-EPI creatinine equation [@levey2009ckdepi] as calculated by USRDS, with the race coefficient) of 10 or above vs below 10 mL/min/1.73 m², as in the original code's `GFR_DICH` (decided by Vagish Hemmige, 27 October 2026, in a working session: "Use the code"). The paper describes the outcome as greater than 10 vs at most 10 [@hemmige2024density]; the two differ only for patients at exactly 10.

**Secondary:** eGFR as a continuous variable.

There is no follow-up; the outcome is measured at the index event.

## 8. Statistical analysis

**Descriptive analysis.** Table 1 by the five density categories: means (SD) for continuous variables and counts (%) for categorical ones, with a one-way test for continuous variables (currently Welch's, the default of R's `oneway.test()`; whether to use the classical ANOVA is for the deciders) and chi-squared tests for categorical variables. The paper lists one-way ANOVA, Kruskal-Wallis and chi-squared tests without saying which variable used which [@hemmige2024density]; Kruskal-Wallis is not used here. Missing data are reported for each variable.

**Primary model.** Mixed-effects logistic regression of eGFR ≥ 10 on the density category (reference: 0 facilities), with a random intercept for HSA, progressively adjusted [@hemmige2024density]:

- **Model 1:** age, sex, race, Hispanic ethnicity, year.
- **Model 2:** Model 1 plus heart failure, coronary disease, diabetes, cerebrovascular disease, alcohol or drug dependence, immobility, institutionalized, access type, primary cause of kidney failure, and (in the first version) serum albumin and hemoglobin.
- **Model 3:** Model 2 plus insurance, access to nephrology care (none, some, unknown), rural-urban type, ZIP code poverty, ZIP code % Black, and HSA quality benchmarks.

Models 2 and 3 are fit twice, with and without albumin and hemoglobin; with them, the analysis uses complete cases (the paper reports 533,375 patients). The paper used Stata; its exact covariate coding and estimation options are not available, so these models are rebuilt from the paper's text and Table 2 footnotes. The "HSA quality benchmarks" in Model 3 are taken to be the three the Methods give as examples ("such as"): HbA1c testing and eye examinations among enrollees with diabetes, and ambulatory-sensitive discharges. Estimation uses `glmmTMB` [@glmmtmb] with the Laplace approximation; on synthetic data it matched a fully converged `lme4::glmer` about thirty times faster, and 7-point quadrature (Stata's default) changed estimates only in the third decimal (decided by Vagish Hemmige, 27 October 2026). The linear models of eTable 3 also use `glmmTMB`; the variance decomposition uses `lme4::lmer` [@lme4_pkg].

**Variance decomposition.** Null mixed linear models of continuous eGFR with a random intercept for HSA, and with HSA and dialysis facility (`PROVUSRD`) nested, report the share of variance at each level.

**Effect modification.** Models stratified by race (White, Black) [@hemmige2024density].

**Multiplicity.** None; a single primary comparison is reported, as in the paper.

**Missing data.** Complete-case analysis for each model, plus multiple imputation of albumin and hemoglobin, which the paper describes as "a multiple imputation technique with chained predictive analytics (10 imputations)" (eTable 2), read here as chained equations. Only albumin and hemoglobin are imputed, by predictive mean matching, from the outcome, the density category and the Model 3 covariates, without HSA; estimates are pooled by Rubin's rules. **Open:** D7, confirmation of this imputation model.

**Software.** R, with `usRds` [@usrds_pkg], `flowchart` [@flowchart_pkg], `tidycensus` [@tidycensus], `glmmTMB` [@glmmtmb], `lme4` [@lme4_pkg] and `ellmer` [@ellmer_pkg]. The `usRds` version or commit is recorded with every result.

## 9. Sensitivity analyses

| Analysis | Assumption it tests |
|---|---|
| Exclude HSAs with 0 facilities (reference: category 2); Table 2, Models 1–3 without albumin and hemoglobin | That distance to care in HSAs without facilities does not drive the association |
| Stratified by race, White and Black; eTable 1, Models 1–3 with albumin and hemoglobin | That the association holds within each race group |
| Density as a continuous exposure; eTable 2, Models 1–3 with and without albumin and hemoglobin, with them imputed, and by race | That the association does not depend on the choice of cut points |
| Continuous eGFR as the outcome (linear mixed model); eTable 3, Models 1–3 with albumin and hemoglobin, with and without HSAs with 0 facilities | That the association does not depend on the threshold of 10 |
| Multiple imputation of albumin and hemoglobin (eTable 2) | That complete-case results are not biased by missing laboratory values |
| Excluding eGFR of 5 or below (from the original R code; not in the paper) | That results are not driven by implausibly low eGFR values |
| Each correction listed in section 12, applied one at a time | How much each correction to the original code changes the published estimates |

## 10. Disclosure control

USRDS data are used under the investigators' data use agreement. No cell, flowchart box or table entry with a count from 1 to 10 is published, including counts recoverable by subtraction. Tables and figures from USRDS data stay out of the repository until they have been checked for errors and cleared for release.

## 11. Limitations to address in reporting

The limitations in the paper apply [@hemmige2024density]. Specific to the replication: the cause-of-kidney-failure mapping is rebuilt rather than recovered; Stata models are re-estimated in R; and public source files (CMS, Dartmouth, ERS, ACS) are re-downloaded and may have been revised since the original analysis.

## 12. Corrections to the original code

Each is applied in the replication and its effect is reported (section 9). Decisions that belong to the deciders are linked.

| Original behavior | Correction |
|---|---|
| A patient with two residence periods covering the dialysis start date would have been duplicated (a uniqueness check was printed but not enforced) | A patient with no matching period, or more than one, has no residence and is excluded at that flowchart step |
| CONSORT table counted the RUCA exclusion as 0 (compared a labelled factor to `11`) while the next line removed patients | Every exclusion is an `fc_filter()` step |
| Exclusions for the facility linkage, a second sex check, ZIP population, % White, % Black, % Asian, % Hispanic and region were applied outside the CONSORT table; the income and poverty rows were labelled "ZIPPercentageFemale" | As above |
| A ZIP-to-ZCTA step was counted (224 patients in the published Figure 1) but never applied; ZIP codes were matched to ZCTAs directly | The intended crosswalk is applied (UDS Mapper, by year), with its own flowchart step; HSA population counts each ZCTA once |
| Oct 2017 and Jan 2018 CMS files code ownership as 1/2; for-profit counts were 0 for dialysis starts from October 2017 to March 2018 | Ownership harmonized in `usRds` |
| A ZIP code with any facility of unknown ownership or stations had all its for-profit, non-profit or station counts set to 0 | Counts ignore only the record with the missing value |
| Facility files expanded to one row per ZIP code per day | Interval join on each release's validity period |
| Dartmouth suppression codes made positive | Set to missing |
| `DIALSET` codes 1 and 2 kept to exclude home dialysis, correct for the earlier coding (`$MESET_CUR`) but not the current one (`$MESET`, where 1 = home) | Keep "Dialysis facility/center" only, named rather than numbered |
| Area data matched to the form year and facility counts to the dialysis start year; patients whose years differed were silently dropped | All area data matched to the year dialysis started; no one dropped for a year mismatch |
| Study period and the year covariate defined by the form date (`MEFDATE`); the paper defines both by the start of hemodialysis | Both use the year dialysis started (`DIALDAT`) |
| ACS subject-table variable codes assumed to be the same every year | Each year's variable labels are checked against the expected text before use |
| A one-year lagged station count was missing, not 0, where a ZIP code had no facility a year earlier (not used in the published models) | `usRds` returns 0 |
| Two interactive maps saved the center-density map under the station-density file names | One function draws each map, saved under its own name |
| The patient-level analysis file was written to Stata and RDS files next to the code | Nothing patient-level is written to the project |
| A blank comorbidity field became missing, which would drop the patient from a model; the published sample sizes show the paper kept them | Blank or unknown counts as not present, as on the form |
| A primary-cause code listed on two category sheets would have joined twice and duplicated those patients | One row per code in the mapping; the join stops if a code appears twice |

## Open decisions

The deciders (Vagish Hemmige and Ladan Golestaneh) settle these; until then the replication does what the sections above describe.

- **D4, cause-of-kidney-failure mapping (section 6).** Whether a mapping drafted by language models and checked by the deciders is acceptable for the replication, and whether the mapping is right.
- **D7, imputation model (section 8).** Confirmation of the imputation model for eTable 2.

## Reporting map

| Checklist item | Topic | Plan section |
|---|---|---|
| STROBE 4 | Study design | 2 |
| STROBE 5 | Setting, dates | 3 |
| STROBE 6 / RECORD 6.1–6.3 | Eligibility, codes and algorithms, linkage | 4, 6 |
| STROBE 7 / RECORD 7.1 | Variables, codes and algorithms | 5, 6, 7 |
| STROBE 8 | Data sources and measurement | 3 |
| STROBE 9 | Bias | 9, 11 |
| STROBE 10 | Study size | 4 |
| STROBE 11 | Quantitative variables | 5, 6 |
| STROBE 12 / RECORD 12.1–12.3 | Statistical methods, data cleaning, linkage | 8, 9, 12 |
| STROBE 13 / RECORD 13.1 | Participants, flow diagram | 4 |
| STROBE 14 | Descriptive data, missingness | 8 |
| STROBE 16 | Main results | 8 |
| STROBE 17 | Other analyses | 9 |
| STROBE 19 / RECORD 19.1 | Limitations | 11 |
| RECORD 22.1 | Access to data and code | 3, 10 |

## References

Rendered from `references.bib`.

# R Analysis Repository Blueprint

Intended file organization for an R research analysis. `ARCHITECTURE.md`, maintained through Posit, describes the current implementation.

```text
repository/
├── R/
│   ├── main.R               # Orchestrates definitive analysis
│   ├── setup.R              # Packages, paths, shared parameters
│   ├── functions.R          # Reusable functions
│   ├── ...                  # Study-specific scripts and subdirectories
│   ├── tables.R             # Generates or orchestrates tables
│   └── figures.R            # Generates or orchestrates figures
├── figures/                 # Generated figures
├── tables/                  # Generated tables
├── references/              # Supporting literature and evidence
├── quarto/                  # Explanatory Quarto pages
├── _extensions/             # Quarto extensions, when used
├── docs/                    # Example rendered website directory
├── _quarto.yml              # Quarto configuration
├── index.qmd                # Website entry point
├── README.md                # Overview and execution
├── README.Rmd               # Optional source for README.md
├── analysis-plan.md         # Scientific objectives and methods
├── references.bib           # Bibliographic citations
├── AGENTS.md                # Agent instructions
├── ARCHITECTURE.md          # Current implementation (Posit)
├── REPOSITORY-BLUEPRINT.md  # Intended organization
├── LICENSE.md               # Optional license
├── .Rbuildignore            # Optional build exclusions
├── <project>.Rproj          # Optional RStudio project file (not used by Positron)
└── .gitignore               # Project-specific exclusions
```

## Analytical scripts

- `R/main.R` sources definitive scripts in dependency order.
- Typical workflow: setup → cohort construction → processing → modeling → outputs.
- Study-specific scripts may be grouped into subdirectories by analytical stage.
- `R/tables.R` and `R/figures.R` may generate outputs directly or orchestrate specialized scripts.

## Documentation

- Document definitive analytical scripts with explanatory Quarto pages; exploratory scripts need not have pages.
- Use [Cryptococcus-cost-analysis](https://github.com/VagishHemmige/Cryptococcus-cost-analysis) as an example for Quarto supporting files, chunk imports, callouts, and formatting—not scientific methods.
- Quarto source and rendered output locations may vary by project.

## Outputs and version control

- Track approved, nonrestricted outputs when useful for publication; otherwise retain them locally and exclude them from Git.
- **`.gitignore`:** Exclude restricted data, credentials, caches, temporary files, and generated outputs unless intentionally tracked (e.g., `.Rproj.user/`, `.Rhistory`, `.RData`, `.httr-oauth`, `.quarto/`, `cache/`, `figures/`, `tables/`, `*.quarto_ipynb`); verify exclusions cover actual output paths without hiding necessary source or reference files.

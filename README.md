BioPRIO
================

# BioPRIO – Biological Invasive species Prioritization Risk Assessment Tool

BioPRIO is an adaptation of the
[FinnPRIO](https://doi.org/10.1007/s10530-016-1126-3) plant pest risk
assessment framework for **terrestrial invertebrates** (invasive
insects, ecological threat invertebrates). Originally developed for
plant pests in Finland, this version is adapted for Norway with generic
“risk assessment area” terminology.

## Assessment Framework

BioPRIO uses Monte Carlo simulations with PERT distributions to assess
invasion risk across four modules:

| Module | Description |
|----|----|
| **ENT** (Entry) | Probability of species entering via various pathways |
| **EST** (Establishment) | Likelihood of establishing given climate, hosts, prey, habitats |
| **IMP** (Impact) | Economic and environmental/social impact potential |
| **MAN** (Management) | Preventability and controllability |

Risk scores are calculated as:

- **RISK** = IMPACT x INVASION
- **INVASION** = ENTRY x ESTABLISHMENT
- **MANAGEABILITY** = min(PREVENTABILITY, CONTROLLABILITY)

## Requirements

- **R** (\>= 4.0)
- **Python** (\>= 3.9) – only needed for AI-assisted justification
  scripts
- R packages are auto-installed on first run via `global.R`

## Quick Start

### Running the App

``` r
# Option 1: Standard Shiny launch
shiny::runApp()

# Option 2: Use the startup script
source("START_APP.R")
```

On startup, select a SQLite database file (`.db`) containing species and
assessment data.

### Key Features

- Multi-user concurrent database access control with automatic
  stale-lock release
- Monte Carlo simulations (default 50,000 iterations) using PERT
  distributions
- Word document report generation
- Entry pathway assessment supporting multiple pathways per species
- Full CRUD for species and assessor management

## Project Structure

    BioPRIO/
    ├── R/                              # Core R modules
    │   ├── constants.R                 # Simulation parameters and system paths
    │   ├── internal functions.R        # UI rendering helpers
    │   ├── simulations.R               # Monte Carlo scoring logic
    │   └── sqlite queries.R           # Database query templates
    ├── python/                         # AI-assisted justification scripts
    │   ├── get_additional_literature.py
    │   ├── instructions_loader.py
    │   ├── parse_rmd_instructions.py
    │   ├── gpt_researcher_scripts/    # GPT Researcher pipeline
    │   │   ├── populate_bioprio_justifications_hybrid.py
    │   │   └── populate_bioprio_values.py
    │   └── SQuAI_scripts/             # SQuAI local PDF RAG pipeline
    ├── scripts/
    │   ├── get litterature/            # Literature fetching (R)
    │   ├── populate database/          # Species population scripts
    │   ├── database management scripts/
    │   ├── migration scripts/
    │   └── terminology_migration/
    ├── www/                            # Web assets
    │   ├── instructions.html           # User guide
    │   ├── styles.css                  # Custom styling
    │   └── img/                        # Images
    ├── information/                    # Documentation and instructions Rmd
    ├── docs/plans/                     # Design documents
    ├── ui.R                            # Shiny UI definition
    ├── server.R                        # Shiny server logic
    ├── global.R                        # Package loading and initialization
    └── START_APP.R                     # App launcher script

## AI-Assisted Workflow

BioPRIO includes Python scripts for automatically generating scientific
justifications for assessment answers.

### 1. Fetch Literature

``` r
# R: EuropePMC, PubMed, CrossRef, OpenAlex
source("scripts/get litterature/get_species_literature.R")
```

``` bash
# Python: Semantic Scholar, CORE
python python/get_additional_literature.py
```

### 2. Generate Justifications

``` bash
# Hybrid mode: web research + local PDFs
python python/populate_bioprio_justifications_hybrid.py --db path/to/database.db
```

### 3. Determine Values

``` bash
python python/gpt_researcher_scripts/populate_bioprio_values.py --db path/to/database.db
```

### API Keys

The AI scripts require API keys stored externally (not in the
repository):

- OpenAI API key
- Tavily API key (for GPT Researcher web search)
- CORE API key (optional, for literature fetching)

## Database Population

### For Invertebrates

``` r
source("scripts/populate database/populate_ant_species.R")
```

Uses GBIF for taxonomy and distribution data. Supports re-running with
configurable duplicate handling.

### For Plant Pests (EPPO)

Original FinnPRIO scripts in `scripts/populate database scripts/`.

## Technology Stack

| Component      | Technology                     |
|----------------|--------------------------------|
| Language       | R                              |
| Web framework  | Shiny                          |
| Database       | SQLite                         |
| Statistics     | mc2d (PERT distributions)      |
| Reporting      | officer, flextable             |
| AI enhancement | Python, OpenAI, GPT Researcher |

## Key Terminology (BioPRIO vs FinnPRIO)

| FinnPRIO                    | BioPRIO                         |
|-----------------------------|---------------------------------|
| pest                        | species                         |
| PRA area                    | risk assessment area            |
| host plant                  | suitable host, prey, or habitat |
| Finland-specific references | Generic / risk assessment area  |

## References

- Heikkila et al. (2016) *A novel prioritizing method for invasive alien
  plant pests based on the Finnish risk assessment framework.*
  Biological Invasions 18:1827–1842. [DOI:
  10.1007/s10530-016-1126-3](https://doi.org/10.1007/s10530-016-1126-3)
- [CBD Pathways of
  Introduction](https://www.cbd.int/doc/decisions/cop-12/cop-12-dec-17-en.pdf)

## License

Internal use – Norwegian Scientific Committee for Food and Environment
(VKM).

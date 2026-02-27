# BioPRIO - Biological Prioritization Risk Assessment Tool

BioPRIO is an adaptation of the FinnPRIO plant pest risk assessment framework for **terrestrial invertebrates** (invasive insects, ecological threat invertebrates). Originally developed for plant pests in Finland, this version is adapted for Norway with generic "risk assessment area" terminology.

## Overview

BioPRIO uses Monte Carlo simulations to assess invasion risk based on four modules:

| Module | Description |
|--------|-------------|
| **ENT** (Entry) | Probability of species entering via various pathways |
| **EST** (Establishment) | Likelihood of establishing given climate, hosts, prey, habitats |
| **IMP** (Impact) | Economic and environmental/social impact potential |
| **MAN** (Management) | Preventability and controllability |

## Requirements

- **R** (>= 4.0)
- **Python** (>= 3.9) for AI-assisted justification scripts
- Required R packages are auto-installed on first run

## Quick Start

### Running the App

```r
# Open R in the project directory
setwd("path/to/BioiPRIO_development")
shiny::runApp()
```

Or use the startup script:
```r
source("START_APP.R")
```

### Database Selection

On startup, select a SQLite database file (`.db` or `.sqlite`) containing species and assessment data.

## Project Structure

```
BioiPRIO_development/
├── R/                          # Core R modules
│   ├── constants.R             # Simulation parameters
│   ├── internal functions.R    # UI rendering
│   ├── simulations.R           # Monte Carlo scoring (DO NOT MODIFY)
│   └── sqlite queries.R        # Database queries
├── python/                     # AI enhancement scripts
│   ├── populate_bioprio_justifications.py       # Web-based research
│   ├── populate_bioprio_justifications_hybrid.py # Web + local PDFs
│   ├── populate_bioprio_values.py               # Value determination
│   └── get_additional_literature.py             # Literature fetcher
├── scripts/
│   ├── get litterature/        # Literature fetching (R)
│   ├── populate database/      # Species population scripts
│   └── terminology_migration/  # Database migration scripts
├── www/                        # Web assets
│   ├── instructions.html       # User guide
│   └── styles.css              # Styling
├── databases/                  # SQLite databases
├── docs/plans/                 # Design documents
├── ui.R                        # Shiny UI
├── server.R                    # Shiny server
└── global.R                    # Package loading
```

## AI-Assisted Workflow

BioPRIO includes Python scripts for automatically generating scientific justifications:

### 1. Fetch Literature

```bash
# R script: EuropePMC, PubMed, CrossRef, OpenAlex
Rscript "scripts/get litterature/get_species_literature.R"

# Python script: Semantic Scholar, CORE
python python/get_additional_literature.py
```

### 2. Generate Justifications

```bash
# Web-only research
python python/populate_bioprio_justifications.py --db path/to/database.db

# Hybrid mode (web + local PDFs)
python python/populate_bioprio_justifications_hybrid.py --db path/to/database.db
```

### 3. Determine Values

```bash
python python/populate_bioprio_values.py --db path/to/database.db
```

### API Keys Required

Store API keys in `C:\Users\dafl\Desktop\API keys\`:
- `openai_api_key.txt` - OpenAI API key
- `tavily_api_key.txt` - Tavily API key (for GPT Researcher)
- `core_api_key.txt` - CORE API key (optional, for literature fetching)

## Database Population

### For Invertebrates (Ants, etc.)

```r
# Edit configuration in script, then run:
source("scripts/populate database/populate_ant_species.R")
```

Uses GBIF for taxonomy and distribution data.

### For Plant Pests (EPPO)

Original FinnPRIO scripts in `scripts/populate database scripts/`.

## Key Terminology Changes from FinnPRIO

| FinnPRIO | BioPRIO |
|----------|---------|
| pest | species |
| PRA area | risk assessment area |
| host plant | suitable host, prey, or habitat |
| Finland-specific | Generic/Norway |

## Scoring Logic

**CRITICAL: The scoring calculations in `R/simulations.R` must NEVER be modified.**

Risk scores are calculated as:
- **RISK** = IMPACT × INVASION
- **INVASION** = ENTRY × ESTABLISHMENT
- **MANAGEABILITY** = min(PREVENTABILITY, CONTROLLABILITY)

## References

- Original paper: Heikkilä et al. (2016) Biological Invasions 18:1827-1842
- CBD Pathways: https://www.eea.europa.eu/policy-documents/cbd-2014-pathways-of-introduction

## License

Internal use - Norwegian Institute of Public Health (FHI) / VKM

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

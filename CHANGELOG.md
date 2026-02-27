# BioPRIO Changelog

## 2026-02-27: Additional Literature Fetcher (Python)

### Summary
Created `python/get_additional_literature.py` - a Python script that fetches literature from Semantic Scholar and CORE APIs, complementing the existing R script's sources.

### Source Coverage (No Overlap)
| Script | Sources |
|--------|---------|
| `get_species_literature.R` | EuropePMC, PubMed, CrossRef, OpenAlex |
| `get_additional_literature.py` | Semantic Scholar, CORE |

### Features
- Reads species list from SQLite database (scientificName, gbifTaxonKey)
- Reuses existing species folders by GBIF key prefix (e.g., `1315095_Formica_aserva_Forel,_1901`)
- Saves PDFs to `literature_additional/` subfolder (separate from R's `literature/` folder)
- Deduplicates by DOI - checks both `literature/` and `literature_additional/`
- Downloads PDFs via Unpaywall API and direct links from sources
- Generates `metadata_additional.csv` with paper info
- Uses REST API directly for Semantic Scholar (library had timeout issues)

### Usage
```bash
# Process all species from database
python python/get_additional_literature.py

# Process specific species
python python/get_additional_literature.py --species "Formica aserva"

# Custom database and output
python python/get_additional_literature.py --db path/to/db.sqlite --output path/to/species --limit 50
```

### Configuration
- `SPECIES_DOCS_BASE_PATH`: Output folder for species literature
- `DATABASE_PATH`: SQLite database with species list
- `CORE_API_KEY_FILE`: Path to CORE API key (optional)
- `UNPAYWALL_EMAIL`: Email for Unpaywall API

---

## 2026-02-27: Hybrid Justification Populator

### Summary
Created `python/populate_bioprio_justifications_hybrid.py` - uses GPT Researcher's hybrid mode combining web search with local PDF documents for richer justifications.

### Key Differences from Standard Populator
| Aspect | Standard | Hybrid |
|--------|----------|--------|
| `report_source` | `"web"` | `"hybrid"` |
| Local docs | Not used | PDFs from species folder |
| Research depth | Web only | Web + local literature |

### How It Works
1. Finds species folder by GBIF key prefix
2. Copies PDFs to temporary `my-docs/` folder
3. Runs GPT Researcher in hybrid mode
4. Cleans up temporary folder after each species

### File
`python/populate_bioprio_justifications_hybrid.py`

---

## 2026-02-27: Literature Script Hybrid Integration (R)

### Summary
Adapted `scripts/get litterature/get_species_literature.R` to save PDFs in the folder structure expected by the hybrid justification populator.

### Changes
- Added rgbif package for GBIF taxon key lookup
- Folder naming: `{GBIF_KEY}_{Species_Name}` (e.g., `11700741_Lasius_aphidicola`)
- Finds existing folders by GBIF key prefix (handles variations like `1315095_Formica_aserva_Forel,_1901`)
- Saves PDFs in `literature/` subfolder within species folder
- Updated output path to match hybrid script expectations

### New Function: get_gbif_key()
```r
get_gbif_key <- function(species_name) {
  result <- name_backbone(name = species_name, rank = "species", strict = FALSE)
  as.character(result$usageKey)
}
```

---

## 2026-02-19: Python Justification Script - Database Write Fix

### Problem
Justifications from GPT Researcher were not being saved to the database, even though console output appeared correct.

### Root Cause
The `get_assessment_info()` function used an INNER JOIN between `answers` and `questions` tables:
```sql
SELECT ... FROM answers a JOIN questions q ON ... WHERE a.idAssessment = ?
```

This query returns NOTHING if no answer rows exist. Since `populate_ant_species.R` doesn't create answer rows (by design - "app creates them dynamically"), the Python script found 0 questions to process.

### Fix Applied
1. **Modified `get_assessment_info()`** to:
   - Query questions table directly (not via JOIN)
   - Check if answer row exists for each question
   - Create answer row if missing (mimics app behavior)
   - Commit any new rows before returning

2. **Added row count verification** to:
   - `update_answer_justification()` - raises exception if no row updated
   - `update_pathway_justification()` - raises exception if update/insert fails

### How It Works Now
```
1. Script runs → get_assessment_info() called
2. No answer rows? → Creates them (same as app would)
3. Console shows: "ℹ️ Created X answer rows for this assessment"
4. Justifications saved to those rows
5. Row count verified after each UPDATE
```

### File Modified
`python/populate_bioprio_justifications.py`

---

## 2026-02-18: R Script for Ant Species Population (Updated)

### Summary
Created and refined R script to populate BioPRIO database with ant species (or other invertebrates). Since EPPO data is not available for ants, this script uses GBIF for taxonomy and distribution metadata.

### File
`scripts/populate database/populate_ant_species.R`

### Features
- Takes a vector of species scientific names as input
- Fetches taxonomy data from GBIF (scientific name, synonyms, vernacular names, taxon key)
- Checks European presence using GBIF occurrence data
- Fetches **distribution metadata** from GBIF backbone taxonomy (not occurrence records)
  - Converts ISO country codes to full country names
  - Includes establishment means (Native, Introduced, etc.)
  - Adds source attribution: "Distribution according to GBIF (fetched YYYY-MM-DD)"
- Creates species entries in `pests` table
- Creates assessments with proper app compatibility:
  - Version "2.1" (required for app)
  - Adds default entry pathway (required for app to load assessment)
  - Does NOT pre-create answer rows (app creates them dynamically)
- **Re-run support**: Can update existing records or add new assessments

### Configuration Options
```r
# Database Path
DB_FILE <- "path/to/database.db"

# Species to add
SPECIES_NAMES <- c("Lasius neglectus", "Linepithema humile", "Solenopsis invicta")

# Assessor and defaults
DEFAULT_ASSESSOR_ID <- 3L
DEFAULT_TAXA_ID <- 1L        # Insects [1INSEC]
DEFAULT_QUARANTINE_ID <- 6L  # Other non-quarantine

# Data fetching
CREATE_ASSESSMENTS <- TRUE
FETCH_DISTRIBUTION <- TRUE

# Re-run behavior
PEST_EXISTS_MODE <- "update"       # "skip" or "update"
ASSESSMENT_EXISTS_MODE <- "update" # "skip", "update", or "add_new"
```

### Re-run Modes
| Mode | Pests | Assessments |
|------|-------|-------------|
| `"skip"` | Don't modify existing | Don't modify existing |
| `"update"` | Update with fresh GBIF data | Update notes with fresh distribution |
| `"add_new"` | N/A | Create additional assessment |

### Usage
```r
# Edit configuration in script, then run:
source("scripts/populate database/populate_ant_species.R")

# Can be run multiple times safely with "update" mode
```

### Database Tables Populated
| Table | Fields |
|-------|--------|
| `pests` | scientificName, synonyms, vernacularName, gbifTaxonKey, idTaxa, idQuarantineStatus, inEurope, eppoCode (empty) |
| `assessments` | idPest, idAssessor, startDate, notes (distribution), version ("2.1") |
| `entryPathways` | idAssessment, idPathway (8 = Intentional introduction) |

### App Compatibility Fixes Applied
| Issue | Fix |
|-------|-----|
| App crashes on NULL values | All fields use empty strings instead of NULL/NA |
| App requires version "2.1" | Assessment version set to "2.1" |
| App requires entry pathway | Default pathway added automatically |
| App creates answers dynamically | Script does NOT pre-create answer rows |

### Distribution Data Format
```
Distribution according to GBIF (fetched 2026-02-18): Australia (Introduced);
Bolivia (Introduced); Chile (Introduced); Fiji (Introduced); ...
```

### Notes
- `eppoCode` is empty string (not applicable for ants)
- Hosts/prey/habitats must be filled manually in the app
- Threatened ecosystems must be selected manually
- Additional entry pathways can be added in the app
- AntWiki integration removed (blocked by Cloudflare)

---

## 2026-02-19: Python Justification Script Fixed

### Summary
Fixed `populate_bioprio_justifications.py` to match FinnPRIO structure exactly. The script was incorrectly adding value judgments and scoring scales - it should ONLY research and populate justification text.

### What Was Wrong
The BioPRIO script had been modified to include:
- Value scales (e.g., "EUR scale: <50k, 50-100k, ... >50 million")
- Judgment criteria (e.g., "Scale: easy, difficult, nearly impossible")
- Extended guidance not present in FinnPRIO

### What Was Fixed
Script now matches FinnPRIO exactly - only terminology changes applied:
- Takes questions from database
- Uses GPT Researcher to research answers
- Puts research text into justification field
- **NO value judgments, scales, or scoring guidance**

### File
`python/populate_bioprio_justifications.py`

---

## 2026-02-18: Python AI Scripts for BioPRIO

### Summary
Created Python scripts for AI-powered justification generation, adapted from FinnPRIO for terrestrial invertebrates framework. **Terminology-only changes** - script logic identical to FinnPRIO.

### Files (`python/`)

| File | Purpose |
|------|---------|
| `populate_bioprio_justifications.py` | Generate AI justifications using GPT Researcher |
| `requirements.txt` | Python dependencies |

### Terminology Dictionary (FinnPRIO → BioPRIO)

**Variables and Functions:**
| FinnPRIO | BioPRIO |
|----------|---------|
| `pest_name` | `species_name` |
| `get_pest_name()` | `get_species_name()` |
| `EPPOCODES_TO_POPULATE` | `SPECIES_FILTER` |
| `get_eppo_codes_for_assessments()` | `get_species_identifiers_for_assessments()` |
| `eppo_codes` parameter | `species_filter` parameter |
| `--eppo-codes` CLI flag | `--species` CLI flag |

**Comments and Docstrings:**
| FinnPRIO | BioPRIO |
|----------|---------|
| "pest" | "species" |
| "FinnPRIO" | "BioPRIO" |
| "plant pest risk assessment" | "invasive species risk assessment" |
| "FinnPRIO app" | "BioPRIO app" |

**Question Instructions (EST2 only):**
| FinnPRIO | BioPRIO |
|----------|---------|
| "host plant distribution" | "hosts, prey, or habitats distribution" |
| "Which plants are hosts" | "Which organisms/habitats the species depends on" |
| "Distribution of hosts" | "Distribution of these resources" |
| "Abundance of hosts" | "Abundance of hosts/prey/habitats" |

**Print Statements:**
| FinnPRIO | BioPRIO |
|----------|---------|
| "FinnPRIO JUSTIFICATION POPULATOR" | "BioPRIO JUSTIFICATION POPULATOR" |
| "Ready to use in FinnPRIO app!" | "Ready to use in BioPRIO app!" |
| "Filtering by EPPO codes" | "Filtering by species" |

**Default Paths:**
| FinnPRIO | BioPRIO |
|----------|---------|
| `FinnPRIO_development/databases/` | `BioiPRIO_development/databases/` |

### What Stays IDENTICAL to FinnPRIO

- All database functions (copy, query, update)
- GPT Researcher configuration
- Text cleaning functions
- Main workflow logic
- Question-specific instruction FORMAT (simple focus guidance, no value scales)
- Error handling
- Command-line argument structure

### Usage

```bash
# Install dependencies
pip install -r python/requirements.txt

# Generate justifications
python python/populate_bioprio_justifications.py --db path/to/database.db

# Filter by species
python python/populate_bioprio_justifications.py --species "Formica aserva" "Lasius neglectus"
```

### API Keys Required
- OpenAI API key (for GPT-4o)
- Tavily API key (for GPT Researcher web search)

Configure paths in the scripts or use environment variables.

---

## 2026-02-18: Phase 2.12 - Expand Hosts to Include Prey & Habitats

### Summary
Expanded "suitable hosts" terminology to include "prey" and "habitats" throughout the guidance text. This ensures the framework properly covers terrestrial invertebrates that may depend on prey organisms (predators) or specific habitats (habitat specialists) rather than just host plants.

### Changes Made

**Database info columns:**
| Metric | Before | After |
|--------|--------|-------|
| "prey" occurrences | 1 | 68 |
| "habitat" occurrences | 7 | 75 |

**instructions.html:**
| Metric | Before | After |
|--------|--------|-------|
| "prey" occurrences | 0 | 46 |
| "habitat" occurrences | ~10 | 56 |

### Terminology Pattern
| Before | After |
|--------|-------|
| "suitable hosts are present" | "suitable hosts, prey, or habitats are present" |
| "suitable hosts grow" | "suitable hosts, prey, or habitats occur" |
| "distribution of suitable hosts" | "distribution of suitable hosts, prey, or habitats" |
| "locate suitable hosts" | "locate suitable hosts, prey, or habitats" |
| "survive without suitable hosts" | "survive without suitable hosts, prey, or habitats" |
| "suitable hosts from different plant families" | "suitable hosts from different taxonomic groups, or uses multiple prey species or habitat types" |

### Migration Scripts
- `scripts/terminology_migration/phase2_12_expand_hosts_prey_habitats.R`
- `scripts/terminology_migration/phase2_12b_fix_remaining.R`
- `scripts/terminology_migration/phase2_12c_update_instructions_html.R`
- `scripts/terminology_migration/phase2_12d_fix_instructions_remaining.R`

### Rationale
The original FinnPRIO framework was designed for plant pests where "hosts" referred to host plants. For terrestrial invertebrates:
- **Herbivores/plant feeders**: "hosts" remains appropriate
- **Predators**: "prey" is the relevant resource
- **Habitat specialists**: "habitats" is the relevant resource

The expanded terminology allows assessors to apply the framework to any invertebrate type.

---

## 2026-02-18: Phase 2.11 - Fix Info Column Terminology

### Summary
Fixed missing terminology updates in the `info` columns of `questions` and `pathwayQuestions` tables. These columns contain the guidance text shown in (i) popup panels and were missed during Phase 2 migration.

### Changes Made
| Table | Column | Records Updated |
|-------|--------|-----------------|
| `questions` | `info` | 17 |
| `pathwayQuestions` | `info` | 3 |

**Terminology Replacements Applied:**
| Find | Replace |
|------|---------|
| "PRA area" | "risk assessment area" |
| "host plant(s)" | "suitable host(s)" |
| "the pest" | "the species" |
| "pest's" | "species'" |

**Preserved (intentional):**
- "other pests" (target organisms for biocontrol)
- "control pests" (in biological control context)
- "biological pest control"

### Validation
- 0 remaining "PRA area" occurrences
- 0 remaining "host plant" occurrences
- 193 "species" occurrences (updated)
- 12 remaining "pest" occurrences (all intentional)

### Migration Script
`scripts/terminology_migration/phase2_11_fix_info_columns.R`

### Backup
`databases/clean_database/clean_backup_before_info_fix_20260218.db`

---

## 2026-02-18: LLM-Optimized Instructions

### Summary
Created `www/instructions_llm.md` - a machine-readable version of the BioPRIO assessment instructions optimized for AI/LLM scripts that generate justifications.

### File Details
- **Location:** `www/instructions_llm.md`
- **Size:** 551 lines (~3,000 words)
- **Format:** Structured Markdown with JSON output specification

### Contents
| Section | Purpose |
|---------|---------|
| Overview | Framework introduction and module descriptions |
| Output Format | JSON structure for AI responses (question_id, selected_option, min/max_option, confidence, justification) |
| Entry Pathways | Reference table with pathway groups and scoring formula differences |
| Questions (ENT, EST, IMP, MAN) | All 22 questions with options, point values, guidance, and example justifications |
| Quality Criteria | Requirements for good justifications (cite evidence, be quantitative, address uncertainty) |
| Data Sources | Recommended sources (GBIF, CABI, EPPO, Europhyt, Eurostat, WorldClim) |

### Key Differences from Human Instructions
| Aspect | Human (`instructions.html`) | LLM (`instructions_llm.md`) |
|--------|----------------------------|----------------------------|
| Format | HTML with detailed prose | Structured Markdown tables |
| Length | ~4,000 lines | 551 lines |
| Examples | Narrative scenarios | JSON response templates |
| Guidance | Contextual explanations | Bullet-point criteria |
| Output | Free-form text | Specified JSON schema |

### Usage
For AI scripts (e.g., GPT Researcher, OpenAI API) that automatically generate risk assessment justifications based on species data.

---

## 2026-02-18: Phase 2 - Comprehensive Terminology Update

### Summary
Comprehensive terminology update based on expert review (`reformulated_questions.Rmd`). Replaced "pest" with "species" throughout, updated question wording for arthropod applicability, and standardized "PRA area" to "risk assessment area". **All scoring logic unchanged.**

### Changes Made

**Global Replacements:**
| Find | Replace | Count |
|------|---------|-------|
| "pest" | "species" | 24 instances |
| "PRA area" | "risk assessment area" | 7 instances |

**Main Questions Updated:**
| Question | Change |
|----------|--------|
| EST1 | Added "(or persist through unfavourable seasons)", "production conditions" → "land use conditions" |
| EST2 | Rephrased: "How large an area of suitable hosts, prey organisms, or habitats does the risk assessment area contain?" |
| EST4 | "characteristics" → "biological or ecological traits", "assist" → "facilitate" |
| EST4 options | Updated to use "traits" and "facilitate" |
| IMP3 | Added "and native biodiversity", rephrased for clarity |
| IMP4.1-4.3 | Added "public health" to impact categories |
| MAN3 | Added "of commodities or conveyances" |
| MAN4 | Added "if established" |
| MAN5 | "survey" → "survey and monitor" |

**Pathway Questions Updated:**
| Question | Change |
|----------|--------|
| ENT2A/B | Added "to the risk assessment area" |
| ENT3 | "host material or commodity" → "commodities, plant material, or other conveyances potentially associated with the species" |
| ENT4 | "suitable habitat" → "suitable host, prey organism, or habitat" |

### Migration Scripts Created (`scripts/terminology_migration/`)
| File | Purpose |
|------|---------|
| `phase2_1_backup_database.R` | Create timestamped backup |
| `phase2_2_pest_to_species.R` | Global pest → species replacement |
| `phase2_3_update_main_questions.R` | Update main question wording |
| `phase2_4_update_pathway_questions.R` | Update pathway question wording |
| `phase2_5_validate_changes.R` | Validate points unchanged, terminology correct |
| `phase2_6_extract_final_questions.R` | Extract all questions for review |
| `phase2_7_standardize_pra_area.R` | Standardize to "risk assessment area" |
| `phase2_8_update_threatened_sectors.R` | Replace agriculture-focused sectors with ecological habitats |
| `phase2_9_update_instructions_A.R` | Instructions: pest → species, PRA area → risk assessment area |
| `phase2_10_update_instructions_B.R` | Instructions: host plant → suitable host |
| `phase2_run_all.R` | Master script to run all steps |
| `phase2_final_questions.txt` | Final questions after migration |
| `phase2_B_host_plant_review.md` | Review document for host plant contexts |
| `phase2_B_summary_recommendations.md` | Summary of terminology recommendations |

**Instructions (`www/instructions.html`) Updated:**

| Term | Before | After | Count |
|------|--------|-------|-------|
| "pest" | 201 | 9 (intentional) | -192 |
| "PRA area" | 57 | 0 | -57 |
| "host plant(s)" | 51 | 0 | -51 |
| "species" | ~2 | 205 | +203 |
| "suitable host(s)" | 0 | 45 | +45 |
| "risk assessment area" | 0 | 57 | +57 |

Remaining 9 "pest" occurrences are intentional:
- "other pests" (target organisms for biocontrol) - 5 occurrences
- "pesticides" (single word) - 1 occurrence
- "caused by pests" (general reference) - 1 occurrence
- Original paper citation title - 2 occurrences

**Intentional Introduction Pathway Updated:**

| Section | Before | After |
|---------|--------|-------|
| Pathway description | "biological control agents and pest insects" | "biological control agents, pet trade or hobbyist releases, research organisms, deliberate introductions for ecosystem services" |
| Example scenarios | "crops that are cultivated" | "habitats or production systems present" |
| Example scenarios | "control pests that are present" | "control target species that are present" |

Existing terrarium animal examples retained (already appropriate for invertebrates).

**Backup:** `www/instructions_backup_phase2.html`

**General Information Section Updated:**

| Section | Change |
|---------|--------|
| "Hosts" | Renamed to "Hosts, Prey & Habitats" |
| "Threatened Sectors" | Renamed to "Threatened Ecosystems & Habitats" |

**Threatened Sectors Database Replaced:**

Old structure (14 agriculture-focused items):
- Trees and shrubs: Conifers, Broadleaves, Fruits, Berries
- Open-field crops: Potato, Sugar beet, Vegetables, Other
- Greenhouse crops: Cucumber, Tomato, Pepper, Lettuce, Ornamentals
- Others: Others

New structure (24 ecological habitat categories):
| Group | Items |
|-------|-------|
| Forest ecosystems | Coniferous forest, Deciduous forest, Mixed forest, Forest plantations |
| Open terrestrial habitats | Grasslands & meadows, Heathland & shrubland, Alpine & mountain habitats, Coastal habitats |
| Wetlands & freshwater | Mires & bogs, Fens & marshes, Lakes & ponds, Rivers & streams |
| Agricultural systems | Arable land & crops, Orchards & fruit production, Pastures & grazing land, Greenhouses & nurseries |
| Urban & built environments | Urban green spaces, Private gardens, Parks & recreational areas, Infrastructure corridors |
| Special ecological interest | Pollinator networks, Deadwood & saproxylic habitats, Soil ecosystems, Cultural landscapes |

### Validation Completed

**Database:**
- [x] No remaining "pest" terminology (except "other pests" in IMP2.2 - intentional)
- [x] No remaining "PRA area" terminology
- [x] All points values unchanged
- [x] All key terminology verified present
- [x] Threatened sectors replaced with ecological habitat categories

**Server.R:**
- [x] Section headings updated ("Hosts, Prey & Habitats", "Threatened Ecosystems & Habitats")

**Instructions.html:**
- [x] No remaining "host plant" terminology
- [x] No remaining "PRA area" terminology
- [x] "pest" → "species" (192 replacements)
- [x] "host plant(s)" → "suitable host(s)" (51 replacements)
- [x] Intentional introduction examples broadened for invertebrates
- [x] Remaining "pest" occurrences verified as intentional (9 total)

### Backups
```
databases/clean_database/clean_backup_phase2_20260218.db
www/instructions_backup_phase2.html
```

### Rollback if Needed
```bash
# Database
cp databases/clean_database/clean_backup_phase2_20260218.db databases/clean_database/clean.db

# Instructions
cp www/instructions_backup_phase2.html www/instructions.html
```

---

## 2026-02-17: Phase 1 - Initial Terminology Adaptation

### Summary
Adapted FinnPRIO plant pest risk assessment framework for terrestrial invertebrates (invasive insects, ecological threat invertebrates). **Terminology-only changes** - all scoring logic, point values, and calculations remain identical.

### Target Area
Norway (using "risk assessment area" terminology)

---

## Changes Made

### Database (`databases/clean_database/clean.db`)

**Main Questions Updated:**
| Question | Change |
|----------|--------|
| EST2 | "host plants grow or are cultivated" → "suitable hosts, prey, or habitats occur" |
| IMP2.3 | "plant production sector" → "plant production sector or ecosystem" |
| IMP4.3 | "culturally important plants" → "culturally important plants or other organisms" |

**Pathway Questions Updated:**
| Question | Change |
|----------|--------|
| ENT3 | "host plant commodity" → "host material or commodity" |

**Pathways Renamed (CBD Classification):**
| ID | Old Name | New Name |
|----|----------|----------|
| 1 | Seeds | Contaminant of seeds or growing media |
| 3 | Wood and wood products | Wood and wood packaging |
| 4 | Food and fodder | Agricultural commodities |
| 5 | Other living plant parts | Cut plant material |

**Pathways Unchanged:**
- Plants for planting (ID 2)
- Hitchhiking (ID 6)
- Natural spread (ID 7)
- Intentional introduction (ID 8)

### UI (`ui.R`)
- Line 1: `"FinnPRIO-Assessor"` → `"BioPRIO-Assessor"`

### Instructions (`www/instructions.html`)
- FinnPRIO → BioPRIO (2 occurrences, citation preserved)
- Pathway names updated to match database
- "host plant commodities" → "host materials or commodities"

---

## Files Created

### Migration Scripts (`scripts/terminology_migration/`)
| File | Purpose |
|------|---------|
| `1_extract_current_questions.R` | Extract all questions from database |
| `2_update_main_questions.R` | Update main questions terminology |
| `3_update_pathway_questions.R` | Update pathway questions terminology |
| `4_update_pathways.R` | Rename pathways |
| `5_validate_scores.R` | Verify points values unchanged |
| `current_questions.txt` | Baseline before migration |
| `final_questions.txt` | After migration (for diff) |

### Documentation (`docs/plans/`)
| File | Purpose |
|------|---------|
| `2026-02-17-bioprio-terminology-design.md` | Design document |
| `2026-02-17-bioprio-implementation.md` | Implementation plan |

### Project Files
| File | Purpose |
|------|---------|
| `CLAUDE.md` | Project documentation for AI assistants |
| `PLANNING.md` | Implementation tracking |
| `CHANGELOG.md` | This file |

---

## Validation Completed

- [x] All 22 questions extracted and verified
- [x] Points values unchanged (automated validation)
- [x] EST2 contains "suitable hosts, prey, or habitats"
- [x] ENT3 contains "host material or commodity"
- [x] IMP2.3 contains "plant production sector or ecosystem"
- [x] IMP4.3 contains "plants or other organisms"
- [x] MAN2 still references "European Union"
- [x] Pathways A,C,D,E renamed correctly
- [x] Pathways B,F,G,H unchanged
- [x] ui.R title updated
- [x] instructions.html terminology updated
- [x] App runs without errors

---

## Backup

Original database backed up to:
```
databases/clean_database/clean_backup_20260217.db
```

---

## What's NOT Changed

- `R/simulations.R` - All scoring formulas intact
- `R/internal functions.R` - Rendering logic intact
- `R/constants.R` - Simulation parameters intact
- `server.R` - No terminology was present
- `global.R` - No terminology was present
- Database schema - Structure unchanged
- Point values in JSON - All preserved exactly

---

## To Continue Development

### Run the App
```bash
cd "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development"
Rscript -e "shiny::runApp('.', port=3838, launch.browser=TRUE)"
```

### Rollback if Needed
```bash
cp databases/clean_database/clean_backup_20260217.db databases/clean_database/clean.db
```

### Re-run Validation
```bash
Rscript scripts/terminology_migration/5_validate_scores.R
```

### View Current Questions
```bash
Rscript scripts/terminology_migration/1_extract_current_questions.R
```

---

## Git Status (Not Committed)

The following files have changes that are NOT yet committed:
- `CLAUDE.md` (new)
- `PLANNING.md` (new)
- `CHANGELOG.md` (updated)
- `ui.R` (modified)
- `www/instructions.html` (modified)
- `databases/clean_database/clean.db` (modified - phase 1 + phase 2)
- `docs/plans/` (new directory)
- `scripts/terminology_migration/` (new directory, includes phase 2 scripts)
- `reformulated_questions.Rmd` (source document for phase 2)

Commit when ready with appropriate message.

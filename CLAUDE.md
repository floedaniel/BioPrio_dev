# BioPRIO - Project Documentation

## Project Purpose

BioPRIO is an adaptation of the FinnPRIO plant pest risk assessment framework for **terrestrial invertebrates** (invasive insects, ecological threat invertebrates). Originally developed for plant pests in Finland, this version is adapted for Norway with generic "risk assessment area" terminology.

## Core Constraint

**CRITICAL: Do not change the calculations**

### Scoring Logic Location

All scoring formulas are in `R/simulations.R`:
- `simulation()` - Main orchestrator
- `rpert_from_tag()` - PERT distribution sampling
- `generate_inclusion_exclusion_score()` - Multi-pathway combination

**These functions must NEVER be modified for this adaptation.**

## File Structure

```
BioiPRIO_development/
├── R/                              # Core R modules (DO NOT MODIFY for terminology)
│   ├── constants.R                 # Simulation parameters
│   ├── internal functions.R        # UI rendering, data processing
│   ├── simulations.R               # Monte Carlo scoring logic (NEVER MODIFY)
│   └── sqlite queries.R            # Database queries
├── scripts/                        # Support scripts
│   ├── database management/        # DB utilities
│   ├── migration scripts/          # Data migration
│   ├── populate database/          # Data population
│   └── div support/                # Diagnostics
├── www/                            # Web assets
│   ├── instructions.html           # User guide (terminology updates OK)
│   └── styles.css                  # Styling
├── databases/                      # SQLite databases
│   └── *.sqlite                    # Question text lives here
├── docs/plans/                     # Design documents
├── ui.R                            # Shiny UI
├── server.R                        # Shiny server logic
├── global.R                        # Global setup
├── CLAUDE.md                       # This file
└── PLANNING.md                     # Implementation plan
```

## Key Technical Details

### 1. Think Before Coding

Explicit reasoning precedes action:
- **Declare assumptions**: State what you assume to be true about the code, data, or requirements
- **Expose ambiguities**: Identify unclear requirements or implementation details before proceeding
- **Consider alternatives**: Evaluate multiple approaches and justify the chosen solution
- **Halt on uncertainty**: Stop and ask for clarification rather than guessing or making assumptions
- **Verify understanding**: Read existing code thoroughly before making changes

### 2. Simplicity First

Only the minimum necessary solution is implemented:
- **No speculative features**: Build only what is explicitly requested or clearly necessary
- **No premature abstractions**: Don't create utilities, helpers, or frameworks for one-time operations
- **No extra configurability**: Avoid adding parameters, options, or settings "just in case"
- **Remove complexity**: Simplify until only essential code remains
- **Trust existing guarantees**: Don't add validation or error handling for scenarios that can't happen with internal code

### 3. Surgical Changes

Edits are strictly limited to what the task requires:
- **Minimal scope**: Change only the code directly related to the task
- **No incidental refactoring**: Don't clean up, reorganize, or improve unrelated code
- **No stylistic changes**: Don't add comments, docstrings, or type annotations to unchanged code
- **Remove only what you create**: Delete artifacts created by your changes, not pre-existing code
- **No backwards-compatibility hacks**: Delete unused code completely rather than leaving markers (e.g., `_unused` variables, `// removed` comments)

### 4. Goal-Driven Execution

Work is defined by verifiable outcomes:
- **Convert tasks to criteria**: Define measurable success conditions before starting
- **Test against criteria**: Verify that each change satisfies its requirements
- **Iterate until satisfied**: Continue refining until all criteria are met
- **Verify in context**: Test changes within the full application workflow
- **Document what changed**: Explain what was modified and why in commit messages

## Technology Stack

- **Language**: R
- **Framework**: Shiny (web application framework)
- **Database**: SQLite (FinnPrio_DB.db)
- **Key Packages**:
  - UI: shiny, shinyjs, shinyFiles, shinythemes, shinyalert, shinyWidgets, DT
  - Data: DBI, RSQLite, tidyverse, lubridate, glue, jsonlite, fs
  - Statistics: mc2d (for PERT distributions in Monte Carlo simulations)
  - Reporting: officer, flextable

**Note**: All packages are loaded via `global.R` with automatic dependency checking and installation.

## Running the Application

To launch the Shiny app:
```r
shiny::runApp()
```

The application expects a SQLite database file to be selected on startup via the file chooser dialog.

## Code Architecture

### Application Structure

The app follows the standard Shiny architecture pattern:

- **global.R**: Package loading and initialization (optimized with automatic dependency management)
- **ui.R**: User interface definition (navbar with tabs for Assessments, Pest-species data, Assessors, Instructions)
- **server.R**: Server-side logic and reactive programming (~2100+ lines)
  - Includes full CRUD operations for Pests and Assessors
  - Automatic stale session unlock (5-minute timeout)
- **R/**: Helper functions organized by purpose
  - `constants.R`: System volume paths and default simulation parameters
  - `internal functions.R`: UI rendering helpers and utility functions
  - `simulations.R`: Monte Carlo simulation logic for risk assessment
  - `sqlite queries.R`: SQL query templates for data export

### Data Management (CRUD Operations)

The application provides full CRUD (Create, Read, Update, Delete) functionality for key data entities:

**Pest-Species Data Tab:**
- **Create**: `+ Add Pest` button opens modal for new pest entry with validation
- **Read**: Interactive DataTable with search, sort, and single-row selection
- **Update**: `Edit Selected Pest` button pre-populates modal with existing data
- **Delete**: `Delete Selected Pest` with cascade deletion of associated assessments, answers, and simulations
- **Validation**: Prevents duplicate scientific names, EPPO codes, and GBIF taxon keys
- **Data Integrity**: Warns before deleting pests with existing assessments

**Assessors Tab:**
- **Create**: `+ Add Assessor` button for new assessor entry
- **Read**: Interactive DataTable showing firstName, lastName, email
- **Update**: `Edit Selected Assessor` button for modifications
- **Delete**: `Delete Selected Assessor` with protection (blocks deletion if assessments exist)
- **Validation**: Requires firstName and lastName; email is optional
- **Data Integrity**: Prevents deletion of assessors with existing assessments

**Implementation Pattern:**
- Row selection: `input$[table_name]_rows_selected`
- Edit modals: Pre-populated with `value =` parameter in input fields
- Validation: Check required fields and duplicates before DB operations
- Confirmation: `shinyalert()` with callbacks for destructive operations
- Refresh: Reload reactive data and update dropdowns after changes

### Database Schema

The SQLite database (FinnPrio_DB.db) follows this structure:

**Core Tables:**
- `assessments`: Main assessment records linking pests, assessors, dates, validity status
- `pests`: Pest species information (scientific name, EPPO code, GBIF key, taxonomic group, quarantine status)
- `assessors`: Assessor information (name, email)
- `questions`: Main questionnaire items organized by group (ENT, EST, IMP, MAN)
- `pathwayQuestions`: Entry pathway-specific questions (ENT2A, ENT2B, ENT3, ENT4)

**Answer Tables:**
- `answers`: Responses to main questions (stores min/likely/max values and justification)
- `pathwayAnswers`: Responses to pathway-specific questions

**Relationship Tables:**
- `entryPathways`: Links assessments to selected entry pathways
- `threatXassessment`: Links assessments to threatened sectors
- `pathways`: Entry pathway definitions with grouping (group 1/2/3 affects calculation)
- `threatenedSectors`: Sectors that could be impacted

**Simulation Tables:**
- `simulations`: Simulation run metadata (iterations, lambda, weights, date)
- `simulationSummaries`: Statistical summaries of simulation results (min, q5, q25, median, q75, q95, max, mean)

**System Table:**
- `dbStatus`: Concurrent access control (tracks inUse flag and timestamp)

### Data Flow

1. **Database Loading**: User selects .db file → Connection established → All reference data loaded into reactiveValues
2. **Assessment Workflow**:
   - Create assessment → Select pest & assessor → Choose entry pathways
   - Answer questions (ENT, EST, IMP, MAN groups + pathway-specific)
   - Mark as finished (triggers completeness validation)
   - Mark as valid (ensures only one valid assessment per species)
3. **Simulation Workflow**:
   - Assessment must be finished → Run Monte Carlo simulation → Save results → Generate statistics
4. **Export**: Wide table format joins all assessment data, answers, and simulation results

### Key Reactive Patterns

**Concurrent Access Control**:
- `dbStatus` table prevents simultaneous database writes
- **Automatic stale lock release**: Checks timestamp using `difftime(now(), as_datetime(timestamp))`
- If lock is stale (>5 minutes), automatically resets `inUse = 0` and updates timestamp
- Prevents permanent locks from crashed/abandoned sessions
- Disables save buttons when another user actively has the database locked
- Implementation in server.R uses lubridate functions: `now()`, `as_datetime()`

**Assessment Selection**:
- Selecting a row in assessments table triggers loading of all related data (entry pathways, threats, answers)
- `assessments$selected` drives the entire questionnaire rendering

**Dynamic UI Generation**:
- `render_quest_tab()` generates interactive checkbox tables for min/likely/max selections
- Questions stored as JSON in database, parsed dynamically
- JavaScript callbacks enforce single-selection-per-column constraint

**Answer Validation**:
- Before marking finished: checks all required questions answered, all min/likely/max selections complete
- Entry pathway answers validated separately if pathways selected

## Monte Carlo Simulations

The core risk calculation uses PERT distributions fitted to min/likely/max answers:

**Entry Score Calculation**:
- Each pathway scored separately using ENT questions
- Scenario A (no current management): ENT1 × ENT2A × ENT3A × ENT4
- Scenario B (with management): ENT1 × ENT2B × ENT3B × ENT4
- Multiple pathways combined using inclusion-exclusion principle
- Pathway group (1/2/3) determines divisor (81/27/9)

**Establishment Score**:
- Uses EST questions with conditional logic
- SPR1 (spread) derived from EST2 × EST3 matrix lookup
- Final: (EST1 + SPR1 + EST4) / 21, with edge case handling

**Impact Score**:
- Weighted combination: (w1 × (IMP1 + IMP2) + w2 × (IMP3 + IMP4)) / 9
- w1 typically for economic impacts, w2 for environmental/social
- IMP2 and IMP4 are boolean question groups that get summed

**Risk Score**:
- RISK = IMPACT × INVASION (where INVASION = ENTRY × ESTABLISHMENT)

**Manageability Score**:
- PREVENTABILITY = max(MAN1, MAN2, MAN3) / 4
- CONTROLLABILITY = max(MAN4, MAN5) / 4
- MANAGEABILITY = min(PREVENTABILITY, CONTROLLABILITY)

Default simulation parameters: 50,000 iterations, lambda=1, weights=0.5/0.5

## Important Development Notes

### Database Transactions

Always wrap multi-step database operations in transaction logic (though not explicitly implemented in current code). When modifying entry pathways via `save_general`, the cascade deletion of pathwayAnswers is automatic due to schema constraints.

### Question Types

Two question types in the system:
- `"minmax"`: Standard three-column selection (minimum/likely/maximum)
- `"boolean"`: Yes/no questions (IMP2.x, IMP4.x) that still use three-column format but get summed together

### Entry Pathway Groups

Pathways have a `group` field (1, 2, or 3) that determines the calculation formula:
- Group 1: Uses full formula with ENT3 (transfer/survival)
- Group 2: Omits ENT3
- Group 3: Omits both ENT1 and ENT3

This is hardcoded in `simulations.R` case_when logic.

### Answer Storage

Answers store option identifiers (e.g., "a", "b", "c") not point values. Points are joined at simulation time using the points lookup tables generated from questions$list JSON.

### Validation Edge Cases

- IMP2 and IMP4 are composite questions (IMP2.1, IMP2.2, IMP2.3) that get summed. If none selected, create zero-value rows before simulation.
- ENT3A/ENT3B apply conditional overrides based on ENT2/ENT3 combinations (see lines 85-90, 113-118 in simulations.R)

## File Locations and System Configuration

**Project Structure**:
- **Root Files**: `global.R`, `ui.R`, `server.R`, `0_clean_session.R`
- **R/**: Helper functions and utilities
- **www/**: Web assets (templates, CSS, instructions, images)
- **databases/**: Database files organized by project/purpose
- **information/**: Documentation (README files, database diagrams)
- **scripts/**: Utility scripts organized by function (see Script Files section below)
- **python/**: AI enhancement scripts for generating justifications and values

**Database Selection**:
- Selected at runtime via shinyFiles dialog
- File chooser includes quick access volumes (defined in `R/constants.R`):
  - **Working Directory**: `getwd()` - Project root folder
  - **Home**: `fs::path_home()` - User home directory
  - **Named Paths**: Dynamically detected drive letters (Windows)
  - **My Computer**: Root filesystem access

**Application Assets**:
- **Templates**: www/template.docx (for Word report generation)
- **CSS**: www/styles.css (custom styling)
- **Instructions**: www/instructions.html (user documentation displayed in Instructions tab)
- **Images**: www/img/ (application images)

**Configuration Files**:
- `R/constants.R`: System volume paths, default simulation parameters (50000 iterations, lambda=1, weights=0.5/0.5)
- `global.R`: Package loading with automatic dependency management (17 packages total)

## Common Modification Patterns

**Adding a Question**:
1. Insert into `questions` or `pathwayQuestions` table with JSON list format
2. Update points calculation if needed
3. Modify simulation.R if question affects risk calculation

**Adding a Pathway**:
1. Insert into `pathways` table with appropriate group (1/2/3)
2. No code changes needed, dynamic UI will pick it up

**Modifying Simulation Logic**:
- Edit `simulation()` function in R/simulations.R
- Maintain consistency with FinnPRIO model specification
- Test with known assessment data to verify statistical output

**Export Format Changes**:
- Modify SQL in `sqlite queries.R` for structure
- Update `export_wide_table()` function for post-processing

### Assessment Framework (4 Modules)

1. **ENT (Entry)** - Pathway-based entry probability
2. **EST (Establishment & Spread)** - Climate, hosts, spread rate
3. **IMP (Impact)** - Economic + environmental/social impacts
4. **MAN (Management)** - Preventability + controllability


### Question Storage

Questions are stored in SQLite database tables:
- `questions` - Main assessment questions (ENT1, EST1-4, IMP1-4, MAN1-5)
- `pathwayQuestions` - Entry pathway questions (ENT2A/B, ENT3, ENT4)
- `pathways` - Pathway definitions

Question options stored as JSON in `list` column:
```json
{
  "opt": ["a", "b", "c", "d"],
  "text": ["Option A text", "Option B text", ...],
  "points": [1, 2, 3, 4]  // NEVER MODIFY POINTS
}
```

### Terminology Changes Permitted

| Location | What Can Change | What Cannot Change |
|----------|-----------------|-------------------|
| `questions.question` | Question text | - |
| `questions.list` | `text` array values | `points` array values |
| `pathwayQuestions.question` | Question text | - |
| `pathwayQuestions.list` | `text` array values | `points` array values |
| `pathways.name` | Pathway names | `idPathway`, pathway groups |
| `www/instructions.html` | Guidance text | - |

## Database Population Scripts

### For Invertebrates (Ants, etc.)
`scripts/populate database/populate_ant_species.R`

Uses GBIF for taxonomy and distribution data. Key features:
- Fetches distribution **metadata** (not occurrence records)
- Converts ISO codes to full country names
- Supports re-running: `PEST_EXISTS_MODE` and `ASSESSMENT_EXISTS_MODE`
- Creates app-compatible records (version "2.1", entry pathways, no pre-created answers)

### For Plant Pests (EPPO)
`scripts/populate database scripts/` (original FinnPRIO scripts)

Uses EPPO API for taxonomy data. Includes:
1. `1_populate_eppo_pests_table_db.R` - Add species from EPPO
2. `2_populate_eppo_assesment_host.R` - Create assessments with hosts
3. `3_populate_eppo_notes_datasheet.R` - Add datasheet notes
4. `4_populate_eppo_pathwayshosts.R` - Add pathway information
5. `5_populate_eppo_distribution.R` - Add distribution data

### Database Compatibility Requirements
For assessments to work in the app:
- Version must be "2.1"
- Entry pathway must exist
- All text fields must be empty strings (not NULL)
- Answer rows are created dynamically by app (do NOT pre-create)

## Development Conventions

1. **Test score equivalence** after any terminology change
2. **Document all changes** in CHANGELOG.md
3. **Use CBD pathway terminology** for pathway names
4. **Use "risk assessment area"** instead of country names
5. **Preserve answer option structure** - only change text, never points

## Validation Requirement

Before any change is considered complete, verify:
```
FinnPRIO input → Score X
BioPRIO input (same biological situation) → Score X (identical)
```

### Python AI Enhancement Scripts (`python/`)

Python scripts for automatically generating justifications, populating values, and fetching literature:

**Justification Generation:**
- `populate_bioprio_justifications.py`: Web-based research using GPT Researcher
- `populate_bioprio_justifications_hybrid.py`: Hybrid mode (web + local PDFs)
- `populate_bioprio_values.py`: Determines min/likely/max values from justifications

**Literature Fetching:**
- `get_additional_literature.py`: Fetches papers from Semantic Scholar and CORE APIs

**Workflow:**
1. Run `get_additional_literature.py` to fetch PDFs from Semantic Scholar/CORE
2. Run R script `get_species_literature.R` to fetch PDFs from EuropePMC/PubMed/CrossRef/OpenAlex
3. Run `populate_bioprio_justifications_hybrid.py` to generate justifications using web + local PDFs
4. Run `populate_bioprio_values.py` to determine values from justifications
5. Load enhanced database in BioPRIO Assessor

**Configuration:**
- API keys read from external files at `C:\Users\dafl\Desktop\API keys\`
- Species docs stored at: `C:\Users\dafl\OneDrive - Folkehelseinstituttet\VKM Data\27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species\`
- Folder naming: `{GBIF_KEY}_{Species_Name}` (e.g., `11700741_Lasius_aphidicola`)


## References

- Design document: `docs/plans/2026-02-17-bioprio-terminology-design.md`
- Original paper: Heikkilä et al. (2016) Biological Invasions 18:1827-1842
- CBD Pathways: https://www.eea.europa.eu/policy-documents/cbd-2014-pathways-of-introduction

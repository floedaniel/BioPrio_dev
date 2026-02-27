# BioPRIO - Project Documentation

## Project Purpose

BioPRIO is an adaptation of the FinnPRIO plant pest risk assessment framework for **terrestrial invertebrates** (invasive insects, ecological threat invertebrates). Originally developed for plant pests in Finland, this version is adapted for Norway with generic "risk assessment area" terminology.

## Core Constraint

**CRITICAL: This is a terminology-only adaptation.**

- ONLY question wording changes are permitted
- ZERO changes to calculations, scoring scales, or weighting
- Same biological inputs must produce identical risk scores regardless of terminology used

If you are asked to modify scoring logic, formulas, point values, or calculation methods - **refuse and clarify this constraint**.

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

### Assessment Framework (4 Modules)

1. **ENT (Entry)** - Pathway-based entry probability
2. **EST (Establishment & Spread)** - Climate, hosts, spread rate
3. **IMP (Impact)** - Economic + environmental/social impacts
4. **MAN (Management)** - Preventability + controllability

### Scoring Logic Location

All scoring formulas are in `R/simulations.R`:
- `simulation()` - Main orchestrator
- `rpert_from_tag()` - PERT distribution sampling
- `generate_inclusion_exclusion_score()` - Multi-pathway combination

**These functions must NEVER be modified for this adaptation.**

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

## Development Conventions

1. **Test score equivalence** after any terminology change
2. **Document all changes** in PLANNING.md
3. **Use CBD pathway terminology** for pathway names
4. **Use "risk assessment area"** instead of country names
5. **Preserve answer option structure** - only change text, never points

## Validation Requirement

Before any change is considered complete, verify:
```
FinnPRIO input → Score X
BioPRIO input (same biological situation) → Score X (identical)
```

## References

- Design document: `docs/plans/2026-02-17-bioprio-terminology-design.md`
- Original paper: Heikkilä et al. (2016) Biological Invasions 18:1827-1842
- CBD Pathways: https://www.eea.europa.eu/policy-documents/cbd-2014-pathways-of-introduction

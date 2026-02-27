# BioPRIO Terminology Adaptation Design

**Date:** 2026-02-17
**Status:** Approved
**Author:** Claude (AI Assistant)

## Overview

BioPRIO is an adaptation of the FinnPRIO plant pest risk assessment framework for **terrestrial invertebrates**. This is strictly a terminology/wording adaptation - the underlying scoring, weighting, and calculations remain completely unchanged.

## Scope & Constraints

### In Scope
- Rewording 5 questions for invertebrate terminology
- Replacing "Finland" with "risk assessment area" in 9 questions
- Renaming 4 entry pathways (A, C, D, E) using CBD classification
- Creating project documentation (CLAUDE.md, PLANNING.md)
- Database question text updates only

### Out of Scope (Unchanged)
- All scoring formulas in `R/simulations.R`
- Point values for answer options
- PERT distribution logic
- Monte Carlo simulation parameters
- Conditional lookup tables (ENT2/ENT3 matrix, EST2/EST3 → SPR1 matrix)
- UI code structure
- Database schema

### Core Validation Constraint

> Given identical biological inputs expressed in FinnPRIO plant terminology vs BioPRIO invertebrate terminology, the resulting ENTRY, ESTABLISHMENT, IMPACT, RISK, and MANAGEABILITY scores must be mathematically identical.

### Target Taxa
- Invasive insects (beetles, moths, flies, ants, wasps, etc.)
- Ecological threat invertebrates (predators, parasites, competitors)

### Target Area
- Norway (using generic "risk assessment area" terminology)

## Question Terminology Changes

### Invertebrate-Specific Rewording (5 questions)

| ID | FinnPRIO Wording | BioPRIO Wording |
|----|------------------|-----------------|
| **ENT2A** | "host plant commodity" | "host material or commodity" |
| **ENT2B** | "host plant commodity" | "host material or commodity" |
| **ENT3** | "host plant commodity" | "host material or commodity" |
| **EST2** | "host plants grow or are cultivated" | "suitable hosts, prey, or habitats occur" |
| **IMP2.3** | "plant production sector" | "plant production sector or ecosystem" |
| **IMP4.3** | "plants which have..." | "plants or other organisms which have..." |

### Geographic Terminology (9 questions)

Replace "Finland" → "the risk assessment area" in:
- ENT3, ENT4, EST1, EST2, EST3, IMP1, IMP3, MAN1, MAN4, MAN5

Replace "Finnish culture" → "the local culture" in:
- IMP4.3

**Exception:** MAN2 retains "European Union" reference.

## Pathway Renaming

Based on [CBD Pathway Classification](https://www.eea.europa.eu/policy-documents/cbd-2014-pathways-of-introduction) (Hulme et al. 2008, adopted by CBD 2014):

| ID | FinnPRIO | BioPRIO | CBD Category |
|----|----------|---------|--------------|
| **A** | Seeds | Contaminant of seeds or growing media | Transport-Contaminant |
| **B** | Plants for planting | Plants for planting | Transport-Contaminant |
| **C** | Wood and wood products | Wood and wood packaging | Transport-Contaminant |
| **D** | Food and fodder | Agricultural commodities | Transport-Contaminant |
| **E** | Cut flowers and branches | Cut plant material | Transport-Contaminant |
| **F** | Hitchhiking | Hitchhiking | Transport-Stowaway |
| **G** | Natural spread | Natural spread | Unaided |
| **H** | Intentional introduction | Intentional introduction | Release |

## Validation Strategy

### Test Cases

| ID | Description | Validates |
|----|-------------|-----------|
| TC1 | High-risk invasive insect | Full score range, wood pathway |
| TC2 | Low-risk specialist predator | Low establishment, habitat limitation |
| TC3 | Ecological threat with natural spread | Pathway G, ecosystem impacts |
| TC4 | Multi-pathway hitchhiker | Combined pathway probability |
| TC5 | Edge case: unsuitable climate | EST1=a triggers zero establishment |

### Score Equivalence Verification

For each test case, verify identical outputs:
- ENTRY (A and B scenarios)
- ESTABLISHMENT
- INVASION (A and B)
- IMPACT
- RISK (A and B)
- PREVENTABILITY, CONTROLLABILITY, MANAGEABILITY

## File Changes

### Files to Create
- `CLAUDE.md` - Project documentation for AI assistants
- `PLANNING.md` - Phased implementation plan
- `docs/plans/2026-02-17-bioprio-terminology-design.md` - This document

### Files to Modify
- `databases/*.sqlite` - Question text and pathway names only
- `www/instructions.html` - User guide terminology

### Files NOT Modified
- `R/simulations.R` - Scoring logic unchanged
- `R/internal functions.R` - No terminology in calculations
- `R/constants.R` - Parameters unchanged
- `R/sqlite queries.R` - Query structure unchanged
- `server.R`, `ui.R`, `global.R` - UI/app logic unchanged

## References

- Hulme, P.E. et al. (2008). Grasping at the routes of biological invasions: a framework for integrating pathways into policy. Journal of Applied Ecology.
- CBD (2014). Pathways of introduction of invasive species, their prioritization and management. UNEP/CBD/SBSTTA/18/9/Add.1
- Heikkilä, J. et al. (2016). FinnPRIO: a model for ranking invasive plant pests based on risk. Biological Invasions 18:1827-1842.

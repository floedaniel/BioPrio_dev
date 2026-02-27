# BioPRIO Implementation Plan

## Overview

Adapt FinnPRIO plant pest risk assessment framework for terrestrial invertebrates. **Terminology changes only** - no modifications to scoring, weighting, or calculations.

---

## Phase 1: Question Mapping

**Goal:** Identify every question requiring terminology changes.

### 1.1 Invertebrate-Specific Changes (5 questions)

| Question | Current Text | New Text | Status |
|----------|--------------|----------|--------|
| ENT2A | "...with the host plant commodity considered in the pathway" | "...with the host material or commodity considered in the pathway" | [ ] Pending |
| ENT2B | "...with the host plant commodity considered in the pathway" | "...with the host material or commodity considered in the pathway" | [ ] Pending |
| ENT3 | "How large a volume of the considered host plant commodity is traded..." | "How large a volume of the considered host material or commodity is traded..." | [ ] Pending |
| EST2 | "In how large an area do the pest's host plants grow or are cultivated in Finland?" | "In how large an area do suitable hosts, prey, or habitats occur in the risk assessment area?" | [ ] Pending |
| IMP2.3 | "...impact on the profitability of some plant production sector?" | "...impact on the profitability of some plant production sector or ecosystem?" | [ ] Pending |
| IMP4.3 | "An impact on plants which have an important, recognized position in the Finnish culture" | "An impact on plants or other organisms which have an important, recognized position in the local culture" | [ ] Pending |

### 1.2 Geographic Terminology Changes (9 questions)

Replace "Finland" → "the risk assessment area":

| Question | Status |
|----------|--------|
| ENT3 | [ ] Pending |
| ENT4 | [ ] Pending |
| EST1 | [ ] Pending |
| EST2 | [ ] Pending |
| EST3 | [ ] Pending |
| IMP1 | [ ] Pending |
| IMP3 | [ ] Pending |
| MAN1 | [ ] Pending |
| MAN4 | [ ] Pending |
| MAN5 | [ ] Pending |

**Exception:** MAN2 keeps "European Union" reference.

### 1.3 Questions Unchanged (verified generic)

- ENT1: "How wide is the current global geographical distribution of the pest?" ✓
- EST4: "Does the pest have characteristics that could assist..." ✓
- IMP1: Direct economic losses (structure unchanged, only area reference) ✓
- IMP2.1: "Would the pest impact foreign trade?" ✓
- IMP2.2: "Is the pest a vector for other pests?" ✓
- IMP4.1: "Cultural impacts" ✓
- IMP4.2: "Significant aesthetic impacts" ✓
- MAN2: "Is the pest present in the area of the European Union?" ✓
- MAN3: "How difficult is it to detect the pest during inspections?" ✓

---

## Phase 2: Terminology Updates

**Goal:** Apply approved terminology changes to database and documentation.

### 2.1 Database Updates

| Table | Column | Action | Status |
|-------|--------|--------|--------|
| `questions` | `question` | Update text for flagged questions | [ ] Pending |
| `questions` | `list` (JSON) | Update `text` values only (preserve `points`) | [ ] Pending |
| `pathwayQuestions` | `question` | Update text | [ ] Pending |
| `pathwayQuestions` | `list` (JSON) | Update `text` values only | [ ] Pending |
| `pathways` | `name` | Rename A, C, D, E | [ ] Pending |

### 2.2 Pathway Renaming

| ID | Current | New | Status |
|----|---------|-----|--------|
| A | Seeds | Contaminant of seeds or growing media | [ ] Pending |
| B | Plants for planting | Plants for planting | [x] No change |
| C | Wood and wood products | Wood and wood packaging | [ ] Pending |
| D | Food and fodder | Agricultural commodities | [ ] Pending |
| E | Cut flowers and branches | Cut plant material | [ ] Pending |
| F | Hitchhiking | Hitchhiking | [x] No change |
| G | Natural spread | Natural spread | [x] No change |
| H | Intentional introduction | Intentional introduction | [x] No change |

### 2.3 Instructions Update

| File | Action | Status |
|------|--------|--------|
| `www/instructions.html` | Update pathway definitions | [ ] Pending |
| `www/instructions.html` | Update terminology guidance | [ ] Pending |

---

## Phase 3: Validation

**Goal:** Confirm score equivalence between FinnPRIO and BioPRIO terminology.

### 3.1 Test Cases

| ID | Description | Entry | Est | Impact | Risk | Status |
|----|-------------|-------|-----|--------|------|--------|
| TC1 | High-risk invasive insect (wood pathway) | | | | | [ ] Pending |
| TC2 | Low-risk specialist predator | | | | | [ ] Pending |
| TC3 | Ecological threat (natural spread) | | | | | [ ] Pending |
| TC4 | Multi-pathway hitchhiker | | | | | [ ] Pending |
| TC5 | Unsuitable climate (EST1=a) | | | | | [ ] Pending |

### 3.2 Validation Checklist

For each test case, verify identical scores:

- [ ] ENTRY_A score matches
- [ ] ENTRY_B score matches
- [ ] ESTABLISHMENT score matches
- [ ] INVASION_A score matches
- [ ] INVASION_B score matches
- [ ] IMPACT score matches
- [ ] RISK_A score matches
- [ ] RISK_B score matches
- [ ] PREVENTABILITY score matches
- [ ] CONTROLLABILITY score matches
- [ ] MANAGEABILITY score matches

---

## Key Terminology Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Host concept | "suitable hosts, prey, or habitats" | Covers parasites, predators, free-living species |
| Commodity term | "host material or commodity" | Maintains biological framing while generic |
| Impact extension | "plant production sector or ecosystem" | Adds ecological dimension |
| Cultural reference | "plants or other organisms" | Includes culturally important animals |
| Geographic term | "risk assessment area" | Generic, works for any country |
| Pathway framework | CBD classification | International standard (Hulme et al. 2008) |

---

## Open Questions

*None currently - all terminology decisions resolved.*

---

## Progress Tracking

| Phase | Status | Completion |
|-------|--------|------------|
| Phase 1: Question Mapping | Complete | 100% |
| Phase 2: Terminology Updates | Not started | 0% |
| Phase 3: Validation | Not started | 0% |

**Overall Progress:** Design complete, implementation pending.

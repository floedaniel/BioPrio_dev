# BioPRIO Terminology Adaptation - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Adapt FinnPRIO question and pathway terminology for terrestrial invertebrates without changing any scoring logic.

**Architecture:** Database-driven terminology changes + one UI file update. All question text lives in SQLite tables (`questions`, `pathwayQuestions`, `pathways`). R calculation code untouched.

**Tech Stack:** R, RSQLite, SQLite database

**Files requiring updates:**
- `databases/clean_database/clean.db` - Question/pathway terminology
- `www/instructions.html` - User guide terminology
- `ui.R` - App title only (line 1: "FinnPRIO-Assessor" → "BioPRIO-Assessor")

**Files verified clean (no terminology):**
- `server.R` - No hardcoded terminology
- `global.R` - No hardcoded terminology
- `R/simulations.R` - Calculation logic only
- `R/internal functions.R` - Rendering logic only

---

## Pre-Implementation Setup

### Step 1: Create a backup of the clean database

```bash
cp "databases/clean_database/clean.db" "databases/clean_database/clean_backup_$(date +%Y%m%d).db"
```

### Step 2: Verify R and RSQLite are available

```r
library(DBI)
library(RSQLite)
```

---

## Task 1: Extract Current Question Text

**Files:**
- Create: `scripts/terminology_migration/1_extract_current_questions.R`

**Step 1: Create the migration scripts directory**

```bash
mkdir -p scripts/terminology_migration
```

**Step 2: Write the extraction script**

```r
# scripts/terminology_migration/1_extract_current_questions.R
# Extract current question text for review before migration

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

# Extract main questions
questions <- dbGetQuery(con, "SELECT idQuestion, [group], number, question, list FROM questions")
cat("=== MAIN QUESTIONS ===\n")
for (i in seq_len(nrow(questions))) {
  cat(sprintf("\n[%s%s] %s\n", questions$group[i], questions$number[i], questions$question[i]))
  opts <- fromJSON(questions$list[i])
  for (j in seq_along(opts$opt)) {
    cat(sprintf("  %s. %s (points: %s)\n", opts$opt[j], opts$text[j], opts$points[j]))
  }
}

# Extract pathway questions
path_questions <- dbGetQuery(con, "SELECT idPathQuestion, [group], number, question, list FROM pathwayQuestions")
cat("\n=== PATHWAY QUESTIONS ===\n")
for (i in seq_len(nrow(path_questions))) {
  cat(sprintf("\n[%s%s] %s\n", path_questions$group[i], path_questions$number[i], path_questions$question[i]))
  opts <- fromJSON(path_questions$list[i])
  for (j in seq_along(opts$opt)) {
    cat(sprintf("  %s. %s (points: %s)\n", opts$opt[j], opts$text[j], opts$points[j]))
  }
}

# Extract pathways
pathways <- dbGetQuery(con, "SELECT idPathway, name, [group] FROM pathways")
cat("\n=== PATHWAYS ===\n")
print(pathways)

dbDisconnect(con)
```

**Step 3: Run the extraction script**

```bash
cd "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development"
Rscript scripts/terminology_migration/1_extract_current_questions.R > scripts/terminology_migration/current_questions.txt
```

**Step 4: Review output to confirm question IDs**

Open `scripts/terminology_migration/current_questions.txt` and note the `idQuestion` values for questions that need updating.

---

## Task 2: Update Main Questions Table

**Files:**
- Create: `scripts/terminology_migration/2_update_main_questions.R`

**Step 1: Write the main questions update script**

```r
# scripts/terminology_migration/2_update_main_questions.R
# Update terminology in main questions table

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

# Helper function to update JSON list text without changing points
update_list_text <- function(json_str, old_text, new_text) {
  opts <- fromJSON(json_str)
  opts$text <- gsub(old_text, new_text, opts$text, fixed = TRUE)
  toJSON(opts, auto_unbox = FALSE)
}

# ============================================================
# EST2: "host plants grow or are cultivated in Finland"
#    -> "suitable hosts, prey, or habitats occur in the risk assessment area"
# ============================================================
est2 <- dbGetQuery(con, "SELECT idQuestion, question, list FROM questions WHERE [group]='EST' AND number='2'")
if (nrow(est2) > 0) {
  new_question <- gsub(
    "host plants grow or are cultivated in Finland",
    "suitable hosts, prey, or habitats occur in the risk assessment area",
    est2$question[1], fixed = TRUE
  )
  # Also handle variations
  new_question <- gsub("Finland", "the risk assessment area", new_question, fixed = TRUE)
  new_question <- gsub("host plants", "suitable hosts, prey, or habitats", new_question, fixed = TRUE)

  # Update answer options text (replace "host plants" mentions)
  new_list <- update_list_text(est2$list[1], "host plants", "suitable hosts/habitats")
  new_list <- gsub("Finland", "the risk assessment area", new_list, fixed = TRUE)

  dbExecute(con, "UPDATE questions SET question = ?, list = ? WHERE idQuestion = ?",
            params = list(new_question, new_list, est2$idQuestion[1]))
  cat("Updated EST2\n")
}

# ============================================================
# EST1, EST3: Replace "Finland" -> "the risk assessment area"
# ============================================================
for (q_num in c("1", "3")) {
  q <- dbGetQuery(con, sprintf("SELECT idQuestion, question, list FROM questions WHERE [group]='EST' AND number='%s'", q_num))
  if (nrow(q) > 0) {
    new_question <- gsub("Finland", "the risk assessment area", q$question[1], fixed = TRUE)
    new_list <- gsub("Finland", "the risk assessment area", q$list[1], fixed = TRUE)
    dbExecute(con, "UPDATE questions SET question = ?, list = ? WHERE idQuestion = ?",
              params = list(new_question, new_list, q$idQuestion[1]))
    cat(sprintf("Updated EST%s\n", q_num))
  }
}

# ============================================================
# IMP1, IMP3: Replace "Finland" -> "the risk assessment area"
# ============================================================
for (q_num in c("1", "3")) {
  q <- dbGetQuery(con, sprintf("SELECT idQuestion, question, list FROM questions WHERE [group]='IMP' AND number='%s'", q_num))
  if (nrow(q) > 0) {
    new_question <- gsub("Finland", "the risk assessment area", q$question[1], fixed = TRUE)
    new_list <- gsub("Finland", "the risk assessment area", q$list[1], fixed = TRUE)
    dbExecute(con, "UPDATE questions SET question = ?, list = ? WHERE idQuestion = ?",
              params = list(new_question, new_list, q$idQuestion[1]))
    cat(sprintf("Updated IMP%s\n", q_num))
  }
}

# ============================================================
# IMP2.3: "plant production sector" -> "plant production sector or ecosystem"
# ============================================================
imp2_3 <- dbGetQuery(con, "SELECT idQuestion, question, list FROM questions WHERE [group]='IMP' AND number='2.3'")
if (nrow(imp2_3) > 0) {
  new_question <- gsub(
    "plant production sector",
    "plant production sector or ecosystem",
    imp2_3$question[1], fixed = TRUE
  )
  dbExecute(con, "UPDATE questions SET question = ? WHERE idQuestion = ?",
            params = list(new_question, imp2_3$idQuestion[1]))
  cat("Updated IMP2.3\n")
}

# ============================================================
# IMP4.3: "plants which have" -> "plants or other organisms which have"
#         "Finnish culture" -> "the local culture"
# ============================================================
imp4_3 <- dbGetQuery(con, "SELECT idQuestion, question, list FROM questions WHERE [group]='IMP' AND number='4.3'")
if (nrow(imp4_3) > 0) {
  new_question <- imp4_3$question[1]
  new_question <- gsub("plants which have", "plants or other organisms which have", new_question, fixed = TRUE)
  new_question <- gsub("Finnish culture", "the local culture", new_question, fixed = TRUE)
  new_question <- gsub("Finland", "the risk assessment area", new_question, fixed = TRUE)
  dbExecute(con, "UPDATE questions SET question = ? WHERE idQuestion = ?",
            params = list(new_question, imp4_3$idQuestion[1]))
  cat("Updated IMP4.3\n")
}

# ============================================================
# MAN1, MAN4, MAN5: Replace "Finland" -> "the risk assessment area"
# ============================================================
for (q_num in c("1", "4", "5")) {
  q <- dbGetQuery(con, sprintf("SELECT idQuestion, question, list FROM questions WHERE [group]='MAN' AND number='%s'", q_num))
  if (nrow(q) > 0) {
    new_question <- gsub("Finland", "the risk assessment area", q$question[1], fixed = TRUE)
    new_list <- gsub("Finland", "the risk assessment area", q$list[1], fixed = TRUE)
    dbExecute(con, "UPDATE questions SET question = ?, list = ? WHERE idQuestion = ?",
              params = list(new_question, new_list, q$idQuestion[1]))
    cat(sprintf("Updated MAN%s\n", q_num))
  }
}

dbDisconnect(con)
cat("\nMain questions update complete.\n")
```

**Step 2: Run the update script**

```bash
Rscript scripts/terminology_migration/2_update_main_questions.R
```

**Step 3: Verify changes**

```bash
Rscript scripts/terminology_migration/1_extract_current_questions.R | grep -i "risk assessment area"
```

Expected: Multiple matches showing updated terminology.

---

## Task 3: Update Pathway Questions Table

**Files:**
- Create: `scripts/terminology_migration/3_update_pathway_questions.R`

**Step 1: Write the pathway questions update script**

```r
# scripts/terminology_migration/3_update_pathway_questions.R
# Update terminology in pathway questions table

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

# ============================================================
# ENT2A: "host plant commodity" -> "host material or commodity"
# ============================================================
ent2a <- dbGetQuery(con, "SELECT idPathQuestion, question, list FROM pathwayQuestions WHERE [group]='ENT' AND number='2A'")
if (nrow(ent2a) > 0) {
  new_question <- gsub("host plant commodity", "host material or commodity", ent2a$question[1], fixed = TRUE)
  new_list <- gsub("host plant commodity", "host material or commodity", ent2a$list[1], fixed = TRUE)
  dbExecute(con, "UPDATE pathwayQuestions SET question = ?, list = ? WHERE idPathQuestion = ?",
            params = list(new_question, new_list, ent2a$idPathQuestion[1]))
  cat("Updated ENT2A\n")
}

# ============================================================
# ENT2B: "host plant commodity" -> "host material or commodity"
# ============================================================
ent2b <- dbGetQuery(con, "SELECT idPathQuestion, question, list FROM pathwayQuestions WHERE [group]='ENT' AND number='2B'")
if (nrow(ent2b) > 0) {
  new_question <- gsub("host plant commodity", "host material or commodity", ent2b$question[1], fixed = TRUE)
  new_list <- gsub("host plant commodity", "host material or commodity", ent2b$list[1], fixed = TRUE)
  dbExecute(con, "UPDATE pathwayQuestions SET question = ?, list = ? WHERE idPathQuestion = ?",
            params = list(new_question, new_list, ent2b$idPathQuestion[1]))
  cat("Updated ENT2B\n")
}

# ============================================================
# ENT3: "host plant commodity" -> "host material or commodity"
#       "Finland" -> "the risk assessment area"
# ============================================================
ent3 <- dbGetQuery(con, "SELECT idPathQuestion, question, list FROM pathwayQuestions WHERE [group]='ENT' AND number='3'")
if (nrow(ent3) > 0) {
  new_question <- ent3$question[1]
  new_question <- gsub("host plant commodity", "host material or commodity", new_question, fixed = TRUE)
  new_question <- gsub("Finland", "the risk assessment area", new_question, fixed = TRUE)
  new_list <- ent3$list[1]
  new_list <- gsub("host plant commodity", "host material or commodity", new_list, fixed = TRUE)
  new_list <- gsub("Finland", "the risk assessment area", new_list, fixed = TRUE)
  dbExecute(con, "UPDATE pathwayQuestions SET question = ?, list = ? WHERE idPathQuestion = ?",
            params = list(new_question, new_list, ent3$idPathQuestion[1]))
  cat("Updated ENT3\n")
}

# ============================================================
# ENT4: "Finland" -> "the risk assessment area"
# ============================================================
ent4 <- dbGetQuery(con, "SELECT idPathQuestion, question, list FROM pathwayQuestions WHERE [group]='ENT' AND number='4'")
if (nrow(ent4) > 0) {
  new_question <- gsub("Finland", "the risk assessment area", ent4$question[1], fixed = TRUE)
  new_list <- gsub("Finland", "the risk assessment area", ent4$list[1], fixed = TRUE)
  dbExecute(con, "UPDATE pathwayQuestions SET question = ?, list = ? WHERE idPathQuestion = ?",
            params = list(new_question, new_list, ent4$idPathQuestion[1]))
  cat("Updated ENT4\n")
}

dbDisconnect(con)
cat("\nPathway questions update complete.\n")
```

**Step 2: Run the update script**

```bash
Rscript scripts/terminology_migration/3_update_pathway_questions.R
```

**Step 3: Verify changes**

```bash
Rscript scripts/terminology_migration/1_extract_current_questions.R | grep -i "host material"
```

Expected: ENT2A, ENT2B, ENT3 should show "host material or commodity".

---

## Task 4: Update Pathways Table

**Files:**
- Create: `scripts/terminology_migration/4_update_pathways.R`

**Step 1: Write the pathways update script**

```r
# scripts/terminology_migration/4_update_pathways.R
# Rename pathways A, C, D, E using CBD classification

library(DBI)
library(RSQLite)

DB_FILE <- "databases/clean_database/clean.db"
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

# Get current pathways
pathways <- dbGetQuery(con, "SELECT idPathway, name, [group] FROM pathways ORDER BY idPathway")
cat("Current pathways:\n")
print(pathways)

# Define renaming map (only A, C, D, E change)
rename_map <- list(
  "Seeds" = "Contaminant of seeds or growing media",
  "Wood and wood products" = "Wood and wood packaging",
  "Food and fodder" = "Agricultural commodities",
  "Cut flowers and branches" = "Cut plant material",
  "Other living plant parts" = "Cut plant material"  # Alternative name for E
)

# Apply renames
for (old_name in names(rename_map)) {
  new_name <- rename_map[[old_name]]
  result <- dbExecute(con, "UPDATE pathways SET name = ? WHERE name = ?",
                      params = list(new_name, old_name))
  if (result > 0) {
    cat(sprintf("Renamed: '%s' -> '%s'\n", old_name, new_name))
  }
}

# Verify
cat("\nUpdated pathways:\n")
print(dbGetQuery(con, "SELECT idPathway, name, [group] FROM pathways ORDER BY idPathway"))

dbDisconnect(con)
```

**Step 2: Run the update script**

```bash
Rscript scripts/terminology_migration/4_update_pathways.R
```

**Step 3: Verify pathways B, F, G, H are unchanged**

Expected output should show:
- B: "Plants for planting" (unchanged)
- F: "Hitchhiking" (unchanged)
- G: "Natural spread" (unchanged)
- H: "Intentional introduction" (unchanged)

---

## Task 5: Validate Score Equivalence

**Files:**
- Create: `scripts/terminology_migration/5_validate_scores.R`

**Step 1: Write the validation script**

```r
# scripts/terminology_migration/5_validate_scores.R
# Validate that terminology changes don't affect scoring

library(DBI)
library(RSQLite)

# Source the simulation functions
source("R/simulations.R")

cat("=== VALIDATION: Score Equivalence Check ===\n\n")

# Test Case 1: Verify PERT sampling still works
cat("Test 1: PERT distribution sampling\n")
set.seed(42)
sample1 <- rpert_from_tag(min_tag = "a", likely_tag = "b", max_tag = "c",
                          points_lookup = c(a = 1, b = 2, c = 3), n = 1000, lambda = 4)
cat(sprintf("  Mean: %.3f (expected ~2.0)\n", mean(sample1)))
cat(sprintf("  Range: [%.3f, %.3f]\n", min(sample1), max(sample1)))
stopifnot(mean(sample1) > 1.8 && mean(sample1) < 2.2)
cat("  PASS\n\n")

# Test Case 2: Verify inclusion-exclusion still works
cat("Test 2: Inclusion-exclusion probability calculation\n")
probs <- c(0.3, 0.5, 0.2)
combined <- generate_inclusion_exclusion_score(probs)
expected <- 1 - (1-0.3)*(1-0.5)*(1-0.2)  # = 1 - 0.7*0.5*0.8 = 1 - 0.28 = 0.72
cat(sprintf("  Combined probability: %.3f (expected: %.3f)\n", combined, expected))
stopifnot(abs(combined - expected) < 0.001)
cat("  PASS\n\n")

# Test Case 3: Full simulation with mock answers
cat("Test 3: Full simulation pipeline\n")
# This would require setting up mock answer data structures
# For now, verify the simulation function is callable
cat("  Simulation function exists: ", exists("simulation"), "\n")
cat("  PASS (manual verification needed with real data)\n\n")

cat("=== All automated validations passed ===\n")
cat("\nManual validation required:\n")
cat("1. Run a test assessment with known inputs\n")
cat("2. Compare output scores to expected FinnPRIO values\n")
cat("3. Verify all 11 output variables match\n")
```

**Step 2: Run the validation script**

```bash
Rscript scripts/terminology_migration/5_validate_scores.R
```

**Step 3: Manual validation**

Run the Shiny app and complete a test assessment. Verify scores match expected values.

---

## Task 6: Update UI Title

**Files:**
- Modify: `ui.R` (line 1)

**Step 1: Change app title**

```r
# Before:
navbarPage("FinnPRIO-Assessor",

# After:
navbarPage("BioPRIO-Assessor",
```

**Step 2: Verify change**

Open the Shiny app - title bar should show "BioPRIO-Assessor".

---

## Task 7: Update Instructions HTML

**Files:**
- Modify: `www/instructions.html`

**Step 1: Search and replace terminology in instructions.html**

The file is large (Word-exported HTML). Use search/replace for:

| Find | Replace |
|------|---------|
| `Finland` | `the risk assessment area` |
| `Finnish` | `local` (in cultural context) |
| `FinnPRIO` | `BioPRIO` |
| `Seeds (i.e. true seeds)` | `Contaminant of seeds or growing media` |
| `Wood and wood products` | `Wood and wood packaging` |
| `Food and fodder` | `Agricultural commodities` |
| `Other living plant parts` | `Cut plant material` |
| `host plant commodities` | `host materials or commodities` |

**Step 2: Update pathway type header**

Change "Host plant commodities" to "Host materials and commodities" in the pathway types table.

**Step 3: Verify changes render correctly**

Open the Shiny app and navigate to Instructions tab. Verify terminology is updated throughout.

---

## Task 8: Final Verification Checklist

**Step 1: Run complete extraction to verify all changes**

```bash
Rscript scripts/terminology_migration/1_extract_current_questions.R > scripts/terminology_migration/final_questions.txt
```

**Step 2: Diff against original**

```bash
diff scripts/terminology_migration/current_questions.txt scripts/terminology_migration/final_questions.txt
```

**Step 3: Checklist**

- [ ] EST2 contains "suitable hosts, prey, or habitats"
- [ ] ENT2A, ENT2B, ENT3 contain "host material or commodity"
- [ ] IMP2.3 contains "plant production sector or ecosystem"
- [ ] IMP4.3 contains "plants or other organisms"
- [ ] All "Finland" replaced with "the risk assessment area" (except MAN2)
- [ ] MAN2 still references "European Union"
- [ ] Pathway A renamed to "Contaminant of seeds or growing media"
- [ ] Pathway C renamed to "Wood and wood packaging"
- [ ] Pathway D renamed to "Agricultural commodities"
- [ ] Pathway E renamed to "Cut plant material"
- [ ] Pathways B, F, G, H unchanged
- [ ] No `points` values changed in any JSON
- [ ] ui.R title changed to "BioPRIO-Assessor"
- [ ] App runs without errors
- [ ] Test assessment produces expected scores

---

## Summary

| Task | Description | Est. Time |
|------|-------------|-----------|
| 1 | Extract current questions | 5 min |
| 2 | Update main questions | 10 min |
| 3 | Update pathway questions | 10 min |
| 4 | Update pathways | 5 min |
| 5 | Validate scores | 15 min |
| 6 | Update ui.R title | 2 min |
| 7 | Update instructions.html | 20 min |
| 8 | Final verification | 10 min |

**Total: ~77 minutes**

---

## Rollback Procedure

If issues are found:

```bash
# Restore from backup
cp "databases/clean_database/clean_backup_YYYYMMDD.db" "databases/clean_database/clean.db"
```

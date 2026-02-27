# Literature Script Hybrid Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Adapt `get_species_literature.R` to save PDFs in `{GBIF_KEY}_{Species_Name}` folders for the hybrid justification populator.

**Architecture:** Add rgbif package for GBIF taxon key lookup, modify folder naming to use `{gbif_key}_{species_name}` pattern, update output path to match hybrid script expectations, save PDFs directly in species folders.

**Tech Stack:** R, rgbif, httr, europepmc, rentrez, rcrossref, openalexR

---

## Task 1: Add rgbif Package Dependency

**Files:**
- Modify: `scripts/get litterature/get_species_literature.R:9-13`

**Step 1: Add rgbif to required packages**

Find this line in the `required_packages` vector:
```r
required_packages <- c(

  "europepmc", "rentrez", "rcrossref", "httr", "jsonlite",
  "dplyr", "purrr", "stringr", "tidyr", "tibble", "openalexR"
)
```

Change to:
```r
required_packages <- c(
  "rgbif",
  "europepmc", "rentrez", "rcrossref", "httr", "jsonlite",
  "dplyr", "purrr", "stringr", "tidyr", "tibble", "openalexR"
)
```

**Step 2: Add library() call**

Find line 33 (`library(openalexR)`) and add after it:
```r
library(rgbif)
```

**Step 3: Verify syntax**

Run in R: `source("scripts/get litterature/get_species_literature.R")` (will install rgbif if missing)

**Step 4: Commit**

```bash
git add "scripts/get litterature/get_species_literature.R"
git commit -m "feat: add rgbif package for GBIF taxon key lookup"
```

---

## Task 2: Update Output Directory Configuration

**Files:**
- Modify: `scripts/get litterature/get_species_literature.R:47-48`

**Step 1: Update base_output_dir**

Find:
```r
# Base output directory (each species gets a subfolder)
base_output_dir <- "./species_literature"
```

Change to:
```r
# Base output directory (each species gets a subfolder)
# Format: {GBIF_KEY}_{Scientific_Name} to match hybrid justification populator
base_output_dir <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/VKM Data/27.02.2025_maur_forprosjekt_biologisk_mangfold/data/species"
```

**Step 2: Commit**

```bash
git add "scripts/get litterature/get_species_literature.R"
git commit -m "feat: update output directory for hybrid integration"
```

---

## Task 3: Add GBIF Key Lookup Function

**Files:**
- Modify: `scripts/get litterature/get_species_literature.R`

**Step 1: Add get_gbif_key function after the log_msg function (around line 82)**

Insert after `log_msg <- function(...) { ... }`:

```r

#' Get GBIF taxon key for a species
#' @param species_name Scientific name (e.g., "Lasius aphidicola")
#' @return GBIF usageKey as character, or NULL if not found
get_gbif_key <- function(species_name) {
  tryCatch({
    # Query GBIF backbone taxonomy
    result <- name_backbone(name = species_name, rank = "species", strict = FALSE)

    if (is.null(result) || length(result) == 0) {
      log_msg("  ⚠️ No GBIF match found for: ", species_name)
      return(NULL)
    }

    # Check if we got a valid match
    if (is.null(result$usageKey)) {
      log_msg("  ⚠️ No usageKey in GBIF response for: ", species_name)
      return(NULL)
    }

    # Check match type - warn if fuzzy
    if (!is.null(result$matchType) && result$matchType != "EXACT") {
      log_msg("  ℹ️ GBIF match type: ", result$matchType, " for ", species_name)
      if (!is.null(result$canonicalName)) {
        log_msg("  ℹ️ Matched to: ", result$canonicalName)
      }
    }

    as.character(result$usageKey)

  }, error = function(e) {
    log_msg("  ❌ GBIF lookup error for ", species_name, ": ", e$message)
    NULL
  })
}
```

**Step 2: Verify syntax**

Run in R console:
```r
source("scripts/get litterature/get_species_literature.R")
# Test the function
get_gbif_key("Lasius aphidicola")
```

Expected: Returns a numeric string like "11700741"

**Step 3: Commit**

```bash
git add "scripts/get litterature/get_species_literature.R"
git commit -m "feat: add get_gbif_key function for GBIF taxon lookup"
```

---

## Task 4: Update species_folder_name Function

**Files:**
- Modify: `scripts/get litterature/get_species_literature.R:69-72`

**Step 1: Update function to accept gbif_key parameter**

Find:
```r
#' Create species folder name
species_folder_name <- function(species) {
  gsub("[^A-Za-z0-9]+", "_", species)
}
```

Change to:
```r
#' Create species folder name in format: {GBIF_KEY}_{Scientific_Name}
#' @param species Scientific name
#' @param gbif_key GBIF taxon key
#' @return Folder name like "11700741_Lasius_aphidicola"
species_folder_name <- function(species, gbif_key) {
  safe_name <- gsub("[^A-Za-z0-9]+", "_", species)
  paste0(gbif_key, "_", safe_name)
}
```

**Step 2: Commit**

```bash
git add "scripts/get litterature/get_species_literature.R"
git commit -m "feat: update species_folder_name to include GBIF key"
```

---

## Task 5: Update process_species Function

**Files:**
- Modify: `scripts/get litterature/get_species_literature.R:396-528`

**Step 1: Add gbif_key parameter and lookup at start**

Find the function signature:
```r
process_species <- function(species, base_dir, email, max_results, from_date) {
```

Change to:
```r
process_species <- function(species, base_dir, email, max_results, from_date, gbif_key = NULL) {
```

**Step 2: Add GBIF key validation at the start of the function**

After the log_msg lines at the start of process_species (around line 400), add:
```r
  # Validate GBIF key
  if (is.null(gbif_key) || gbif_key == "") {
    log_msg("⚠️ No GBIF key provided for ", species, " - skipping")
    return(NULL)
  }
  log_msg("GBIF taxon key: ", gbif_key)
```

**Step 3: Update folder creation to use gbif_key**

Find:
```r
  # Create species folder structure
  species_dir <- file.path(base_dir, species_folder_name(species))
  pdf_dir <- file.path(species_dir, "pdfs")

  if (!dir.exists(pdf_dir)) dir.create(pdf_dir, recursive = TRUE)
```

Change to:
```r
  # Create species folder (PDFs saved directly, no subfolder)
  species_dir <- file.path(base_dir, species_folder_name(species, gbif_key))

  if (!dir.exists(species_dir)) dir.create(species_dir, recursive = TRUE)
```

**Step 4: Update PDF filepath to save directly in species folder**

Find:
```r
    filepath <- file.path(pdf_dir, paste0(safe_filename(doi), ".pdf"))
```

Change to:
```r
    filepath <- file.path(species_dir, paste0(safe_filename(doi), ".pdf"))
```

**Step 5: Commit**

```bash
git add "scripts/get litterature/get_species_literature.R"
git commit -m "feat: update process_species to use GBIF key for folder naming"
```

---

## Task 6: Update Main Processing Loop

**Files:**
- Modify: `scripts/get litterature/get_species_literature.R:530-553`

**Step 1: Add GBIF key lookup before calling process_species**

Find the main loop:
```r
for (species in species_list) {
  species_log <- process_species(
    species = species,
    base_dir = base_output_dir,
    email = unpaywall_email,
    max_results = max_results_per_source,
    from_date = search_from_date
  )
```

Change to:
```r
for (species in species_list) {
  log_msg("Looking up GBIF key for: ", species)
  gbif_key <- get_gbif_key(species)

  if (is.null(gbif_key)) {
    log_msg("⚠️ Skipping ", species, " - no GBIF key found")
    next
  }

  species_log <- process_species(
    species = species,
    base_dir = base_output_dir,
    email = unpaywall_email,
    max_results = max_results_per_source,
    from_date = search_from_date,
    gbif_key = gbif_key
  )
```

**Step 2: Commit**

```bash
git add "scripts/get litterature/get_species_literature.R"
git commit -m "feat: add GBIF key lookup in main processing loop"
```

---

## Task 7: Final Verification

**Step 1: Test GBIF lookup**

Run in R console:
```r
source("scripts/get litterature/get_species_literature.R")
get_gbif_key("Lasius aphidicola")
# Expected: "11700741" or similar
```

**Step 2: Test folder naming**

```r
species_folder_name("Lasius aphidicola", "11700741")
# Expected: "11700741_Lasius_aphidicola"
```

**Step 3: Verify output directory exists**

```r
dir.exists(base_output_dir)
# Expected: TRUE
```

**Step 4: Test with a single species (optional dry run)**

Set `species_list <- c("Lasius aphidicola")` and `max_results_per_source <- 5` for a quick test.

**Step 5: Final commit**

```bash
git add "scripts/get litterature/get_species_literature.R"
git commit -m "feat: complete literature script hybrid integration

Integrates get_species_literature.R with hybrid justification populator:
- Adds rgbif for GBIF taxon key lookup
- Saves to {GBIF_KEY}_{Species_Name} folder format
- PDFs saved directly in species folder
- Output path matches hybrid script expectations"
```

---

## Summary

The modified script will:
1. Look up GBIF taxon key for each species using rgbif
2. Create folders named `{GBIF_KEY}_{Species_Name}` (e.g., `11700741_Lasius_aphidicola`)
3. Save PDFs directly in the species folder
4. Output to the path expected by `populate_bioprio_justifications_hybrid.py`

This enables the hybrid research workflow:
```
get_species_literature.R → downloads PDFs to {GBIF_KEY}_{Species}/ folders
                                    ↓
populate_bioprio_justifications_hybrid.py → finds PDFs, uses hybrid research mode
```

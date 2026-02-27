# Design: Literature Script Integration with Hybrid Research

**Date**: 2026-02-27
**Status**: Approved

## Overview

Adapt `get_species_literature.R` to save downloaded PDFs in the folder structure expected by `populate_bioprio_justifications_hybrid.py`.

## Current State

- Output: `./species_literature/{Species_Name}/pdfs/`
- Folder naming: `Lasius_aphidicola` (spaces replaced with underscores)

## Target State

- Output: `C:\Users\dafl\OneDrive - Folkehelseinstituttet\VKM Data\27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species\`
- Folder naming: `{GBIF_KEY}_{Species_Name}` (e.g., `11700741_Lasius_aphidicola`)
- PDFs saved directly in species folder (no `/pdfs` subfolder)

## Changes Required

### 1. Add rgbif Dependency
Add `"rgbif"` to `required_packages` vector for GBIF taxonomy lookup.

### 2. New Function: get_gbif_key()
```r
get_gbif_key <- function(species_name) {
  # Query GBIF backbone taxonomy using name_backbone()
  # Return usageKey (taxon key) or NULL if not found
}
```

### 3. Update Configuration
```r
base_output_dir <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/VKM Data/27.02.2025_maur_forprosjekt_biologisk_mangfold/data/species"
```

### 4. Modify species_folder_name()
```r
species_folder_name <- function(species, gbif_key) {
  safe_name <- gsub("[^A-Za-z0-9]+", "_", species)
  paste0(gbif_key, "_", safe_name)
}
```

### 5. Update process_species()
- Look up GBIF key at start of processing
- Skip species if no GBIF key found (with warning)
- Save PDFs directly in species folder (remove `/pdfs` subfolder)
- Pass `gbif_key` to folder naming function

## Data Flow

```
1. For each species:
   ├── get_gbif_key("Lasius aphidicola") → "11700741"
   ├── species_folder_name() → "11700741_Lasius_aphidicola"
   ├── Create: base_output_dir/11700741_Lasius_aphidicola/
   ├── Search literature databases
   ├── Download PDFs directly to species folder
   └── Save metadata.csv, references.ris, download_log.csv
```

## Error Handling

- If GBIF key not found: log warning, skip species
- If rgbif query fails: log error, skip species

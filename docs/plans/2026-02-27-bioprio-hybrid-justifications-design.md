# Design: BioPRIO Hybrid Justification Populator

**Date**: 2026-02-27
**Status**: Approved

## Overview

Create `populate_bioprio_justifications_hybrid.py` - a new script that combines web research with local PDF/document analysis using GPT Researcher's hybrid mode.

## Background

The existing `populate_bioprio_justifications.py` uses web-only research (`report_source="web"`). For species with available literature (PDFs, datasheets), hybrid research can produce more accurate justifications by incorporating local documents alongside web searches.

## Requirements

1. Use GPT Researcher's `report_source="hybrid"` mode
2. Load local documents from species-specific folders
3. Retain all existing features (cost tracking, filtering, skip logic)
4. Fall back to web-only if no local documents found

## Configuration

### Species Documents Location
```
Base path: C:\Users\dafl\OneDrive - Folkehelseinstituttet\VKM Data\27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species\
```

### Folder Naming Convention
```
{GBIF_KEY}_{Scientific_Name}
Example: 11700741_Lasius_aphidicola
```

### Supported Document Extensions
- `.pdf`
- `.txt`
- `.docx`
- `.doc`

## New Functions

### `find_species_docs_folder(gbif_key: str, scientific_name: str) -> Optional[Path]`
Searches for a folder matching the pattern `{gbif_key}_{scientific_name}` in the species docs base path. Scientific name spaces are replaced with underscores.

### `copy_species_docs_to_temp(gbif_key: str, scientific_name: str) -> bool`
1. Clears existing temp `my-docs/` folder
2. Finds species folder using `find_species_docs_folder()`
3. Recursively copies all matching documents to temp folder
4. Returns `True` if documents were copied, `False` otherwise

### `cleanup_temp_docs()`
Removes the temp `my-docs/` folder after processing completes.

## Modified Functions

### `research_justification()`
- Add `use_hybrid: bool = False` parameter
- Set `report_source = "hybrid" if use_hybrid else "web"`

### `process_assessment()`
- Call `copy_species_docs_to_temp()` at start using GBIF key and scientific name
- Pass `use_hybrid` flag to `research_justification()`

### `main()`
- Add `try/finally` block to ensure `cleanup_temp_docs()` runs

## Preserved Features

All existing features from `populate_bioprio_justifications.py` are retained:
- Full cost tracking with Excel export
- Species filtering (GBIF keys, scientific names, EPPO codes)
- Question filtering (`--question` flag)
- Skip existing justifications logic
- All command-line arguments
- `bioprio_instructions_loader` integration
- Domain exclusions

## Data Flow

```
1. main() starts
   └── Copy database to output location

2. For each assessment:
   ├── Load assessment info (GBIF key, scientific name)
   ├── find_species_docs_folder() → locate docs folder
   ├── copy_species_docs_to_temp() → copy to my-docs/
   │   └── Returns use_hybrid = True/False
   │
   ├── For each question:
   │   └── research_justification(use_hybrid=...)
   │       └── GPTResearcher(report_source="hybrid"|"web")
   │
   └── Save justifications to database

3. cleanup_temp_docs() → remove my-docs/
4. Export cost report
```

## Error Handling

- If species folder not found: log warning, continue with web-only
- If document copy fails: log warning, skip that file
- Cleanup runs in `finally` block to ensure temp folder removal

## File Location

```
python/populate_bioprio_justifications_hybrid.py
```

## Implementation Approach

Copy existing `populate_bioprio_justifications.py` as base, then:
1. Add configuration constants for species docs path
2. Add document handling functions
3. Modify research functions to support hybrid mode
4. Add cleanup in finally block

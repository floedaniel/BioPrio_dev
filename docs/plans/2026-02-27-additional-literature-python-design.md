# Design: Additional Literature Fetcher (Python)

**Date**: 2026-02-27
**Status**: Approved

## Overview

A Python script that fetches literature from **Semantic Scholar** and **CORE** - sources not covered by the existing R script - and saves PDFs to the same species folder structure.

## Source Coverage (No Overlap)

| Script | Sources |
|--------|---------|
| `get_species_literature.R` | EuropePMC, PubMed, CrossRef, OpenAlex |
| `get_additional_literature.py` | **Semantic Scholar**, **CORE** |

## Configuration

```python
# Same output path as R script and hybrid populator
SPECIES_DOCS_BASE_PATH = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\VKM Data\27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species"

# Database path for species list
DATABASE_PATH = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\FinnPrio\BioiPRIO_development\databases\ant_test\clean_ants.db"

# Subfolder for Python-sourced literature
LITERATURE_SUBFOLDER = "literature_additional"

# API keys
CORE_API_KEY_FILE = r"C:\Users\dafl\Desktop\API keys\core_api_key.txt"
```

## Key Features

1. **Read species from database** - Query `pests` table for `scientificName` and `gbifTaxonKey`
2. **Reuse existing folders** - Find by `{GBIF_KEY}_` prefix (same logic as R script)
3. **Separate subfolder** - Save to `literature_additional/` to avoid mixing with R downloads
4. **Deduplicate by DOI** - Check existing PDFs before downloading
5. **Unpaywall for PDFs** - Same PDF retrieval strategy as R script

## Folder Structure

```
{GBIF_KEY}_{Species_Name}/
├── literature/              ← R script PDFs (EuropePMC, PubMed, CrossRef, OpenAlex)
├── literature_additional/   ← Python script PDFs (Semantic Scholar, CORE)
├── metadata.csv
└── ...
```

## Dependencies

```
pip install semanticscholar requests
```

- `semanticscholar` - Official Python client for Semantic Scholar API
- `requests` - For CORE REST API calls and Unpaywall

## Data Flow

```
1. Load species from SQLite database (scientificName, gbifTaxonKey)
2. For each species:
   ├── Find existing species folder by GBIF key prefix
   ├── Create literature_additional/ subfolder
   ├── Search Semantic Scholar for papers
   ├── Search CORE for open access papers
   ├── Deduplicate results by DOI
   ├── Filter out DOIs already downloaded (check both literature/ and literature_additional/)
   ├── For each new paper:
   │   ├── Try Unpaywall for PDF URL
   │   ├── Try CORE direct PDF link
   │   └── Download and validate PDF
   └── Save metadata CSV and download log
```

## API Details

### Semantic Scholar
- Endpoint: Uses `semanticscholar` Python library
- Rate limit: 1000 req/sec (unauthenticated)
- Returns: titles, authors, DOIs, abstracts, citation counts

### CORE
- Endpoint: `https://api.core.ac.uk/v3/search/works`
- Rate limit: Requires free API key
- Returns: titles, authors, DOIs, abstracts, direct PDF URLs

## Error Handling

- API failures: Log warning, continue with other sources
- Missing GBIF key: Skip species with warning
- PDF download failures: Log to download_log.csv, continue
- Rate limiting: Implement delays between requests

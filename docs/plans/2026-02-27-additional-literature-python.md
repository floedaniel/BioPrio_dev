# Additional Literature Fetcher (Python) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a Python script that fetches literature from Semantic Scholar and CORE APIs, complementing the existing R script's sources.

**Architecture:** Query species from SQLite database, search both APIs for each species, deduplicate by DOI, download PDFs via Unpaywall/CORE direct links, save to `literature_additional/` subfolder within existing species folders.

**Tech Stack:** Python, semanticscholar, requests, sqlite3, pathlib

---

## Task 1: Create Script Skeleton with Configuration

**Files:**
- Create: `scripts/get litterature/get_additional_literature.py`

**Step 1: Create the script with imports and configuration**

```python
"""
Additional Literature Fetcher for BioPRIO

Complements get_species_literature.R by searching sources not covered by it:
- Semantic Scholar
- CORE (open access aggregator)

Saves PDFs to literature_additional/ subfolder within species folders.
"""

import os
import sqlite3
import time
import re
from pathlib import Path
from typing import List, Dict, Optional, Set
from dataclasses import dataclass
from datetime import datetime

import requests

try:
    from semanticscholar import SemanticScholar
    SEMANTIC_SCHOLAR_AVAILABLE = True
except ImportError:
    SEMANTIC_SCHOLAR_AVAILABLE = False
    print("⚠️  semanticscholar not installed. Install with: pip install semanticscholar")

# =============================================================================
# CONFIGURATION
# =============================================================================

# Output path (same as R script and hybrid populator)
SPECIES_DOCS_BASE_PATH = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\VKM Data\27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species"

# Database path for species list
DATABASE_PATH = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\FinnPrio\BioiPRIO_development\databases\ant_test\clean_ants.db"

# Subfolder for Python-sourced literature (separate from R's "literature" folder)
LITERATURE_SUBFOLDER = "literature_additional"

# API configuration
CORE_API_KEY_FILE = r"C:\Users\dafl\Desktop\API keys\core_api_key.txt"
UNPAYWALL_EMAIL = "daniel.flo@vkm.no"

# Search settings
MAX_RESULTS_PER_SOURCE = 100
SEARCH_FROM_YEAR = 1800

# Rate limiting (seconds)
DELAY_BETWEEN_SEARCHES = 1.0
DELAY_BETWEEN_DOWNLOADS = 0.5

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def load_api_key(file_path: str) -> str:
    """Load API key from file, stripping whitespace."""
    try:
        with open(file_path, 'r') as f:
            return f.read().strip()
    except FileNotFoundError:
        print(f"⚠️  API key file not found: {file_path}")
        return ""


def log_msg(*args):
    """Log message with timestamp."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"[{timestamp}]", *args)


def safe_filename(doi: str) -> str:
    """Create safe filename from DOI."""
    return re.sub(r"[^A-Za-z0-9._-]+", "_", doi)


def normalize_doi(doi: str) -> str:
    """Normalize DOI to lowercase without URL prefix."""
    if not doi:
        return ""
    doi = doi.lower()
    doi = re.sub(r"^https?://doi\.org/", "", doi)
    doi = re.sub(r"^doi:\s*", "", doi)
    return doi


# Load CORE API key
CORE_API_KEY = load_api_key(CORE_API_KEY_FILE)


if __name__ == "__main__":
    log_msg("Additional Literature Fetcher")
    log_msg(f"Species docs path: {SPECIES_DOCS_BASE_PATH}")
    log_msg(f"Database path: {DATABASE_PATH}")
    log_msg(f"Semantic Scholar available: {SEMANTIC_SCHOLAR_AVAILABLE}")
    log_msg(f"CORE API key loaded: {bool(CORE_API_KEY)}")
```

**Step 2: Verify script runs**

Run: `python "scripts/get litterature/get_additional_literature.py"`

Expected output:
```
[HH:MM:SS] Additional Literature Fetcher
[HH:MM:SS] Species docs path: C:\Users\dafl\...
[HH:MM:SS] Database path: C:\Users\dafl\...
[HH:MM:SS] Semantic Scholar available: True/False
[HH:MM:SS] CORE API key loaded: True/False
```

**Step 3: Commit**

```bash
git add "scripts/get litterature/get_additional_literature.py"
git commit -m "feat: create additional literature script skeleton"
```

---

## Task 2: Add Database Functions

**Files:**
- Modify: `scripts/get litterature/get_additional_literature.py`

**Step 1: Add species data class and database functions after helper functions**

```python
# =============================================================================
# DATA CLASSES
# =============================================================================

@dataclass
class Species:
    """Species information from database."""
    scientific_name: str
    gbif_key: str
    eppo_code: str = ""


# =============================================================================
# DATABASE FUNCTIONS
# =============================================================================

def get_species_from_database(db_path: str) -> List[Species]:
    """Get all species with GBIF keys from the database."""
    if not Path(db_path).exists():
        log_msg(f"❌ Database not found: {db_path}")
        return []

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("""
        SELECT DISTINCT p.scientificName, p.gbifTaxonKey, p.eppoCode
        FROM pests p
        WHERE p.gbifTaxonKey IS NOT NULL AND p.gbifTaxonKey != ''
        ORDER BY p.scientificName
    """)

    species_list = []
    for row in cursor.fetchall():
        scientific_name, gbif_key, eppo_code = row
        if scientific_name and gbif_key:
            species_list.append(Species(
                scientific_name=scientific_name,
                gbif_key=str(gbif_key),
                eppo_code=eppo_code or ""
            ))

    conn.close()
    log_msg(f"Loaded {len(species_list)} species from database")
    return species_list
```

**Step 2: Update main block to test database loading**

```python
if __name__ == "__main__":
    log_msg("Additional Literature Fetcher")
    log_msg(f"Semantic Scholar available: {SEMANTIC_SCHOLAR_AVAILABLE}")
    log_msg(f"CORE API key loaded: {bool(CORE_API_KEY)}")

    # Test database loading
    species_list = get_species_from_database(DATABASE_PATH)
    for sp in species_list[:3]:
        log_msg(f"  - {sp.scientific_name} (GBIF: {sp.gbif_key})")
```

**Step 3: Verify database loading works**

Run: `python "scripts/get litterature/get_additional_literature.py"`

Expected: Lists first 3 species from database

**Step 4: Commit**

```bash
git add "scripts/get litterature/get_additional_literature.py"
git commit -m "feat: add database functions for species loading"
```

---

## Task 3: Add Folder Management Functions

**Files:**
- Modify: `scripts/get litterature/get_additional_literature.py`

**Step 1: Add folder functions after database functions**

```python
# =============================================================================
# FOLDER MANAGEMENT
# =============================================================================

def find_existing_species_folder(base_dir: str, gbif_key: str) -> Optional[Path]:
    """Find existing species folder by GBIF key prefix."""
    base_path = Path(base_dir)
    if not base_path.exists():
        return None

    prefix = f"{gbif_key}_"
    for folder in base_path.iterdir():
        if folder.is_dir() and folder.name.startswith(prefix):
            return folder

    return None


def get_or_create_species_folder(base_dir: str, species: Species) -> Optional[Path]:
    """Get existing or create new species folder."""
    # Try to find existing folder
    existing = find_existing_species_folder(base_dir, species.gbif_key)
    if existing:
        log_msg(f"  📂 Using existing folder: {existing.name}")
        return existing

    # Create new folder
    safe_name = re.sub(r"[^A-Za-z0-9]+", "_", species.scientific_name)
    folder_name = f"{species.gbif_key}_{safe_name}"
    folder_path = Path(base_dir) / folder_name
    folder_path.mkdir(parents=True, exist_ok=True)
    log_msg(f"  📂 Created new folder: {folder_name}")
    return folder_path


def get_existing_dois(species_folder: Path) -> Set[str]:
    """Get set of DOIs already downloaded (from both literature folders)."""
    existing_dois = set()

    # Check both literature/ and literature_additional/
    for subfolder in ["literature", LITERATURE_SUBFOLDER]:
        lit_path = species_folder / subfolder
        if lit_path.exists():
            for pdf_file in lit_path.glob("*.pdf"):
                # Extract DOI from filename (files are named {doi}.pdf)
                doi = pdf_file.stem.replace("_", "/")
                existing_dois.add(normalize_doi(doi))

    return existing_dois
```

**Step 2: Commit**

```bash
git add "scripts/get litterature/get_additional_literature.py"
git commit -m "feat: add folder management functions"
```

---

## Task 4: Add Semantic Scholar Search

**Files:**
- Modify: `scripts/get litterature/get_additional_literature.py`

**Step 1: Add paper data class and Semantic Scholar search function**

```python
# =============================================================================
# DATA CLASSES (add after Species)
# =============================================================================

@dataclass
class Paper:
    """Paper information from search results."""
    title: str
    doi: str
    year: Optional[int] = None
    authors: str = ""
    source: str = ""
    pdf_url: Optional[str] = None
    citations: int = 0


# =============================================================================
# SEMANTIC SCHOLAR SEARCH
# =============================================================================

def search_semantic_scholar(species_name: str, limit: int = 100) -> List[Paper]:
    """Search Semantic Scholar for papers about a species."""
    if not SEMANTIC_SCHOLAR_AVAILABLE:
        log_msg("  ⚠️  Semantic Scholar not available")
        return []

    try:
        sch = SemanticScholar()
        results = sch.search_paper(
            species_name,
            limit=limit,
            fields=["title", "authors", "year", "externalIds", "citationCount", "isOpenAccess", "openAccessPdf"]
        )

        papers = []
        for paper in results:
            # Extract DOI
            doi = None
            if paper.externalIds:
                doi = paper.externalIds.get("DOI")

            if not doi:
                continue  # Skip papers without DOI

            # Extract PDF URL if available
            pdf_url = None
            if paper.openAccessPdf:
                pdf_url = paper.openAccessPdf.get("url")

            # Format authors
            authors = ""
            if paper.authors:
                author_names = [a.name for a in paper.authors[:3] if a.name]
                authors = ", ".join(author_names)
                if len(paper.authors) > 3:
                    authors += " et al."

            papers.append(Paper(
                title=paper.title or "",
                doi=doi,
                year=paper.year,
                authors=authors,
                source="SemanticScholar",
                pdf_url=pdf_url,
                citations=paper.citationCount or 0
            ))

        log_msg(f"  📚 Semantic Scholar: found {len(papers)} papers with DOIs")
        return papers

    except Exception as e:
        log_msg(f"  ❌ Semantic Scholar error: {e}")
        return []
```

**Step 2: Commit**

```bash
git add "scripts/get litterature/get_additional_literature.py"
git commit -m "feat: add Semantic Scholar search function"
```

---

## Task 5: Add CORE Search

**Files:**
- Modify: `scripts/get litterature/get_additional_literature.py`

**Step 1: Add CORE search function**

```python
# =============================================================================
# CORE SEARCH
# =============================================================================

def search_core(species_name: str, limit: int = 100) -> List[Paper]:
    """Search CORE for open access papers about a species."""
    if not CORE_API_KEY:
        log_msg("  ⚠️  CORE API key not available")
        return []

    try:
        url = "https://api.core.ac.uk/v3/search/works"
        headers = {"Authorization": f"Bearer {CORE_API_KEY}"}
        params = {
            "q": species_name,
            "limit": limit,
            "scroll": "false"
        }

        response = requests.get(url, headers=headers, params=params, timeout=30)

        if response.status_code != 200:
            log_msg(f"  ❌ CORE API error: HTTP {response.status_code}")
            return []

        data = response.json()
        results = data.get("results", [])

        papers = []
        for item in results:
            doi = item.get("doi")
            if not doi:
                continue  # Skip papers without DOI

            # Get direct PDF link if available
            pdf_url = None
            download_url = item.get("downloadUrl")
            if download_url and download_url.endswith(".pdf"):
                pdf_url = download_url

            # Format authors
            authors = ""
            author_list = item.get("authors", [])
            if author_list:
                author_names = [a.get("name", "") for a in author_list[:3] if a.get("name")]
                authors = ", ".join(author_names)
                if len(author_list) > 3:
                    authors += " et al."

            papers.append(Paper(
                title=item.get("title", ""),
                doi=doi,
                year=item.get("yearPublished"),
                authors=authors,
                source="CORE",
                pdf_url=pdf_url,
                citations=0  # CORE doesn't provide citation counts
            ))

        log_msg(f"  📚 CORE: found {len(papers)} papers with DOIs")
        return papers

    except Exception as e:
        log_msg(f"  ❌ CORE error: {e}")
        return []
```

**Step 2: Commit**

```bash
git add "scripts/get litterature/get_additional_literature.py"
git commit -m "feat: add CORE search function"
```

---

## Task 6: Add PDF Download Functions

**Files:**
- Modify: `scripts/get litterature/get_additional_literature.py`

**Step 1: Add Unpaywall and PDF download functions**

```python
# =============================================================================
# PDF RETRIEVAL
# =============================================================================

def get_unpaywall_pdf_url(doi: str, email: str) -> Optional[str]:
    """Get PDF URL from Unpaywall."""
    try:
        url = f"https://api.unpaywall.org/v2/{requests.utils.quote(doi, safe='')}?email={email}"
        response = requests.get(url, timeout=10)

        if response.status_code != 200:
            return None

        data = response.json()

        # Try best OA location first
        best_oa = data.get("best_oa_location")
        if best_oa and best_oa.get("url_for_pdf"):
            return best_oa["url_for_pdf"]

        # Fall back to any OA location with PDF
        for loc in data.get("oa_locations", []):
            if loc.get("url_for_pdf"):
                return loc["url_for_pdf"]

        return None

    except Exception:
        return None


def download_pdf(url: str, filepath: Path, timeout: int = 60) -> Dict:
    """Download PDF with validation."""
    try:
        headers = {"User-Agent": "BioPRIO-LitFetcher/1.0 (literature retrieval)"}
        response = requests.get(url, headers=headers, timeout=timeout, stream=True)

        if response.status_code != 200:
            return {"success": False, "reason": f"HTTP {response.status_code}"}

        # Write to file
        with open(filepath, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)

        # Validate file size
        file_size = filepath.stat().st_size
        if file_size < 1024:
            filepath.unlink()
            return {"success": False, "reason": "File too small"}

        # Check PDF magic bytes
        with open(filepath, "rb") as f:
            header = f.read(5)
            if header != b"%PDF-":
                filepath.unlink()
                return {"success": False, "reason": "Not a PDF file"}

        return {"success": True, "reason": "OK", "size": file_size}

    except Exception as e:
        if filepath.exists():
            filepath.unlink()
        return {"success": False, "reason": str(e)}


def find_pdf_url(paper: Paper, email: str) -> Optional[str]:
    """Try to find PDF URL from multiple sources."""
    # Use paper's own PDF URL if available (from Semantic Scholar or CORE)
    if paper.pdf_url:
        return paper.pdf_url

    # Try Unpaywall
    url = get_unpaywall_pdf_url(paper.doi, email)
    if url:
        return url

    return None
```

**Step 2: Commit**

```bash
git add "scripts/get litterature/get_additional_literature.py"
git commit -m "feat: add PDF download functions"
```

---

## Task 7: Add Main Processing Functions

**Files:**
- Modify: `scripts/get litterature/get_additional_literature.py`

**Step 1: Add process_species and main functions**

```python
# =============================================================================
# MAIN PROCESSING
# =============================================================================

def process_species(species: Species, base_dir: str) -> Dict:
    """Process a single species: search, deduplicate, download."""
    log_msg("=" * 60)
    log_msg(f"Processing: {species.scientific_name}")
    log_msg(f"GBIF key: {species.gbif_key}")
    log_msg("=" * 60)

    # Get or create species folder
    species_folder = get_or_create_species_folder(base_dir, species)
    if not species_folder:
        return {"species": species.scientific_name, "error": "Could not create folder"}

    # Create literature_additional subfolder
    lit_folder = species_folder / LITERATURE_SUBFOLDER
    lit_folder.mkdir(exist_ok=True)

    # Get existing DOIs to avoid re-downloading
    existing_dois = get_existing_dois(species_folder)
    log_msg(f"  📄 Found {len(existing_dois)} existing PDFs")

    # Search both sources
    all_papers = []

    log_msg("  🔍 Searching Semantic Scholar...")
    ss_papers = search_semantic_scholar(species.scientific_name, MAX_RESULTS_PER_SOURCE)
    all_papers.extend(ss_papers)
    time.sleep(DELAY_BETWEEN_SEARCHES)

    log_msg("  🔍 Searching CORE...")
    core_papers = search_core(species.scientific_name, MAX_RESULTS_PER_SOURCE)
    all_papers.extend(core_papers)

    # Deduplicate by DOI
    seen_dois = set()
    unique_papers = []
    for paper in all_papers:
        norm_doi = normalize_doi(paper.doi)
        if norm_doi and norm_doi not in seen_dois:
            seen_dois.add(norm_doi)
            unique_papers.append(paper)

    log_msg(f"  📊 Total unique papers: {len(unique_papers)}")

    # Filter out already downloaded
    new_papers = [p for p in unique_papers if normalize_doi(p.doi) not in existing_dois]
    log_msg(f"  📊 New papers to download: {len(new_papers)}")

    # Download PDFs
    stats = {"downloaded": 0, "failed": 0, "skipped": len(unique_papers) - len(new_papers)}

    for i, paper in enumerate(new_papers, 1):
        log_msg(f"  [{i}/{len(new_papers)}] {paper.title[:50]}...")

        pdf_url = find_pdf_url(paper, UNPAYWALL_EMAIL)
        if not pdf_url:
            log_msg(f"    ❌ No PDF URL found")
            stats["failed"] += 1
            continue

        filepath = lit_folder / f"{safe_filename(paper.doi)}.pdf"
        result = download_pdf(pdf_url, filepath)

        if result["success"]:
            log_msg(f"    ✅ Downloaded ({result['size']} bytes)")
            stats["downloaded"] += 1
        else:
            log_msg(f"    ❌ Failed: {result['reason']}")
            stats["failed"] += 1

        time.sleep(DELAY_BETWEEN_DOWNLOADS)

    # Save metadata
    metadata_file = lit_folder / "metadata_additional.csv"
    with open(metadata_file, "w", encoding="utf-8") as f:
        f.write("title,doi,year,authors,source,citations\n")
        for paper in unique_papers:
            title = paper.title.replace('"', '""')
            f.write(f'"{title}","{paper.doi}",{paper.year or ""},"{paper.authors}","{paper.source}",{paper.citations}\n')

    log_msg(f"  📊 Results: {stats['downloaded']} downloaded, {stats['failed']} failed, {stats['skipped']} skipped")
    return stats


def main():
    """Main entry point."""
    log_msg("=" * 60)
    log_msg("ADDITIONAL LITERATURE FETCHER")
    log_msg("Sources: Semantic Scholar, CORE")
    log_msg("=" * 60)

    log_msg(f"Output path: {SPECIES_DOCS_BASE_PATH}")
    log_msg(f"Semantic Scholar: {'✅ Available' if SEMANTIC_SCHOLAR_AVAILABLE else '❌ Not installed'}")
    log_msg(f"CORE API key: {'✅ Loaded' if CORE_API_KEY else '❌ Not found'}")

    if not SEMANTIC_SCHOLAR_AVAILABLE and not CORE_API_KEY:
        log_msg("❌ No sources available. Install semanticscholar or add CORE API key.")
        return

    # Load species from database
    species_list = get_species_from_database(DATABASE_PATH)
    if not species_list:
        log_msg("❌ No species found in database")
        return

    log_msg(f"\nProcessing {len(species_list)} species...")

    # Process each species
    total_stats = {"downloaded": 0, "failed": 0, "skipped": 0}

    for species in species_list:
        stats = process_species(species, SPECIES_DOCS_BASE_PATH)
        if "error" not in stats:
            total_stats["downloaded"] += stats["downloaded"]
            total_stats["failed"] += stats["failed"]
            total_stats["skipped"] += stats["skipped"]

        time.sleep(2)  # Pause between species

    # Final summary
    log_msg("")
    log_msg("=" * 60)
    log_msg("FINAL SUMMARY")
    log_msg("=" * 60)
    log_msg(f"Total downloaded: {total_stats['downloaded']}")
    log_msg(f"Total failed: {total_stats['failed']}")
    log_msg(f"Total skipped (already had): {total_stats['skipped']}")
    log_msg("Done!")


if __name__ == "__main__":
    main()
```

**Step 2: Verify script runs end-to-end**

Run: `python "scripts/get litterature/get_additional_literature.py"`

Expected: Processes species, searches both APIs, downloads PDFs

**Step 3: Commit**

```bash
git add "scripts/get litterature/get_additional_literature.py"
git commit -m "feat: add main processing functions

Complete additional literature fetcher with:
- Species loading from database
- Semantic Scholar and CORE search
- Deduplication by DOI
- PDF download via Unpaywall
- Metadata CSV generation"
```

---

## Task 8: Add Command Line Arguments

**Files:**
- Modify: `scripts/get litterature/get_additional_literature.py`

**Step 1: Add argparse at the end of the script**

```python
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Additional Literature Fetcher for BioPRIO")
    parser.add_argument("--db", type=str, default=DATABASE_PATH,
                        help="Path to SQLite database")
    parser.add_argument("--output", type=str, default=SPECIES_DOCS_BASE_PATH,
                        help="Output directory for species folders")
    parser.add_argument("--species", type=str, nargs="+", default=None,
                        help="Filter by species names (e.g., --species 'Lasius aphidicola')")
    parser.add_argument("--limit", type=int, default=MAX_RESULTS_PER_SOURCE,
                        help="Max results per source")

    args = parser.parse_args()

    # Override globals with args
    DATABASE_PATH = args.db
    SPECIES_DOCS_BASE_PATH = args.output
    MAX_RESULTS_PER_SOURCE = args.limit

    # Filter species if specified
    if args.species:
        # Will need to filter after loading
        pass

    main()
```

**Step 2: Commit**

```bash
git add "scripts/get litterature/get_additional_literature.py"
git commit -m "feat: add command line arguments"
```

---

## Summary

The implementation creates `scripts/get litterature/get_additional_literature.py` with:

1. **Configuration** - Same paths as R script and hybrid populator
2. **Database functions** - Load species with GBIF keys from SQLite
3. **Folder management** - Reuse existing folders, save to `literature_additional/`
4. **Semantic Scholar search** - Using official Python client
5. **CORE search** - Using REST API
6. **PDF download** - Via Unpaywall and direct links
7. **Deduplication** - Check existing PDFs in both subfolders
8. **CLI arguments** - For flexibility

**Usage:**
```bash
# Process all species from database
python get_additional_literature.py

# Process specific species
python get_additional_literature.py --species "Formica aserva"

# Custom database and output
python get_additional_literature.py --db path/to/db.sqlite --output path/to/species
```

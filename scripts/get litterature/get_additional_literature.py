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
    print("Warning: semanticscholar not installed. Install with: pip install semanticscholar")

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
        print(f"Warning: API key file not found: {file_path}")
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


# =============================================================================
# DATA CLASSES
# =============================================================================

@dataclass
class Species:
    """Species information from database."""
    scientific_name: str
    gbif_key: str
    eppo_code: str = ""


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
# DATABASE FUNCTIONS
# =============================================================================

def get_species_from_database(db_path: str) -> List[Species]:
    """Get all species with GBIF keys from the database."""
    if not Path(db_path).exists():
        log_msg(f"Database not found: {db_path}")
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
        log_msg(f"  Using existing folder: {existing.name}")
        return existing

    # Create new folder
    safe_name = re.sub(r"[^A-Za-z0-9]+", "_", species.scientific_name)
    folder_name = f"{species.gbif_key}_{safe_name}"
    folder_path = Path(base_dir) / folder_name
    folder_path.mkdir(parents=True, exist_ok=True)
    log_msg(f"  Created new folder: {folder_name}")
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


# =============================================================================
# SEMANTIC SCHOLAR SEARCH
# =============================================================================

def search_semantic_scholar(species_name: str, limit: int = 100) -> List[Paper]:
    """Search Semantic Scholar for papers about a species."""
    if not SEMANTIC_SCHOLAR_AVAILABLE:
        log_msg("  Semantic Scholar not available")
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

        log_msg(f"  Semantic Scholar: found {len(papers)} papers with DOIs")
        return papers

    except Exception as e:
        log_msg(f"  Semantic Scholar error: {e}")
        return []


# =============================================================================
# CORE SEARCH
# =============================================================================

def search_core(species_name: str, limit: int = 100) -> List[Paper]:
    """Search CORE for open access papers about a species."""
    if not CORE_API_KEY:
        log_msg("  CORE API key not available")
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
            log_msg(f"  CORE API error: HTTP {response.status_code}")
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

        log_msg(f"  CORE: found {len(papers)} papers with DOIs")
        return papers

    except Exception as e:
        log_msg(f"  CORE error: {e}")
        return []


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


if __name__ == "__main__":
    log_msg("Additional Literature Fetcher")
    log_msg(f"Semantic Scholar available: {SEMANTIC_SCHOLAR_AVAILABLE}")
    log_msg(f"CORE API key loaded: {bool(CORE_API_KEY)}")

    # Test database loading
    species_list = get_species_from_database(DATABASE_PATH)
    for sp in species_list[:3]:
        log_msg(f"  - {sp.scientific_name} (GBIF: {sp.gbif_key})")

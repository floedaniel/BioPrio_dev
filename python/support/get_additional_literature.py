"""
Additional Literature Fetcher for BioPRIO

Complements get_species_literature.R by searching sources not covered by it:
- Semantic Scholar
- CORE (open access aggregator)

Saves PDFs to the same literature/ subfolder used by get_species_literature.R.
Deduplicates by DOI against existing files before downloading.
"""

import time
import re
from pathlib import Path
from typing import List, Dict, Optional, Set
from dataclasses import dataclass
from datetime import datetime

import requests

# =============================================================================
# CONFIGURATION
# =============================================================================

# Output path (same as R script and hybrid populator)
SPECIES_DOCS_BASE_PATH = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\Prosjektdata - Dokumenter\VKM Data\27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species"

# Subfolder for PDFs — same as get_species_literature.R to keep all PDFs together
LITERATURE_SUBFOLDER = "literature"

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
    """Species information derived from folder name."""
    scientific_name: str
    gbif_key: str


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
# SPECIES DISCOVERY
# =============================================================================

def get_species_from_folders(base_dir: str) -> List[Species]:
    """Derive species list from existing folder structure.

    Folders follow the naming convention used by get_species_literature.R:
        {GBIF_KEY}_{Genus}_{species}[_optional_extra]
    e.g. 11700741_Lasius_aphidicola
    """
    base_path = Path(base_dir)
    if not base_path.exists():
        log_msg(f"Base directory not found: {base_dir}")
        return []

    species_list = []
    for folder in sorted(base_path.iterdir()):
        if not folder.is_dir():
            continue
        # Match {digits}_{UppercaseLetter}{lowercase}_{lowercase} pattern
        m = re.match(r"^(\d+)_([A-Z][a-z]+)_([a-z]+)", folder.name)
        if not m:
            continue
        gbif_key = m.group(1)
        scientific_name = f"{m.group(2)} {m.group(3)}"
        species_list.append(Species(scientific_name=scientific_name, gbif_key=gbif_key))

    log_msg(f"Found {len(species_list)} species from folder structure")
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
    """Get set of DOIs already downloaded in the shared literature/ folder."""
    existing_dois = set()

    lit_path = species_folder / LITERATURE_SUBFOLDER
    if lit_path.exists():
        for pdf_file in lit_path.glob("*.pdf"):
            # Filenames are safe_filename(doi).pdf — reverse the substitution
            doi = pdf_file.stem.replace("_", "/")
            existing_dois.add(normalize_doi(doi))

    return existing_dois


# =============================================================================
# SEMANTIC SCHOLAR SEARCH (using REST API directly for reliability)
# =============================================================================

def search_semantic_scholar(species_name: str, limit: int = 100) -> List[Paper]:
    """Search Semantic Scholar for papers about a species using REST API."""
    try:
        url = "https://api.semanticscholar.org/graph/v1/paper/search"
        params = {
            "query": species_name,
            "limit": min(limit, 100),  # API max is 100 per request
            "fields": "title,authors,year,externalIds,citationCount,isOpenAccess,openAccessPdf"
        }

        response = requests.get(url, params=params, timeout=30)

        if response.status_code == 429:
            log_msg("  Semantic Scholar: rate limited, skipping")
            return []

        if response.status_code != 200:
            log_msg(f"  Semantic Scholar: HTTP {response.status_code}")
            return []

        data = response.json()
        results = data.get("data", [])

        papers = []
        for item in results:
            # Extract DOI
            doi = None
            external_ids = item.get("externalIds") or {}
            doi = external_ids.get("DOI")

            if not doi:
                continue  # Skip papers without DOI

            # Extract PDF URL if available
            pdf_url = None
            oa_pdf = item.get("openAccessPdf")
            if oa_pdf:
                pdf_url = oa_pdf.get("url")

            # Format authors
            authors = ""
            author_list = item.get("authors") or []
            if author_list:
                author_names = [a.get("name", "") for a in author_list[:3] if a.get("name")]
                authors = ", ".join(author_names)
                if len(author_list) > 3:
                    authors += " et al."

            papers.append(Paper(
                title=item.get("title") or "",
                doi=doi,
                year=item.get("year"),
                authors=authors,
                source="SemanticScholar",
                pdf_url=pdf_url,
                citations=item.get("citationCount") or 0
            ))

        log_msg(f"  Semantic Scholar: found {len(papers)} papers with DOIs")
        return papers

    except requests.Timeout:
        log_msg("  Semantic Scholar: timeout")
        return []
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
    log_msg(f"  Found {len(existing_dois)} existing PDFs")

    # Search both sources
    all_papers = []

    log_msg("  Searching Semantic Scholar...")
    ss_papers = search_semantic_scholar(species.scientific_name, MAX_RESULTS_PER_SOURCE)
    all_papers.extend(ss_papers)
    time.sleep(DELAY_BETWEEN_SEARCHES)

    log_msg("  Searching CORE...")
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

    log_msg(f"  Total unique papers: {len(unique_papers)}")

    # Filter out already downloaded
    new_papers = [p for p in unique_papers if normalize_doi(p.doi) not in existing_dois]
    log_msg(f"  New papers to download: {len(new_papers)}")

    # Download PDFs
    stats = {"downloaded": 0, "failed": 0, "skipped": len(unique_papers) - len(new_papers)}

    for i, paper in enumerate(new_papers, 1):
        log_msg(f"  [{i}/{len(new_papers)}] {paper.title[:50]}...")

        pdf_url = find_pdf_url(paper, UNPAYWALL_EMAIL)
        if not pdf_url:
            log_msg(f"    No PDF URL found")
            stats["failed"] += 1
            continue

        filepath = lit_folder / f"{safe_filename(paper.doi)}.pdf"
        result = download_pdf(pdf_url, filepath)

        if result["success"]:
            log_msg(f"    Downloaded ({result['size']} bytes)")
            stats["downloaded"] += 1
        else:
            log_msg(f"    Failed: {result['reason']}")
            stats["failed"] += 1

        time.sleep(DELAY_BETWEEN_DOWNLOADS)

    # Save metadata to species folder root (alongside R's metadata.csv)
    metadata_file = species_folder / "metadata_additional.csv"
    with open(metadata_file, "w", encoding="utf-8") as f:
        f.write("title,doi,year,authors,source,citations\n")
        for paper in unique_papers:
            title = paper.title.replace('"', '""')
            f.write(f'"{title}","{paper.doi}",{paper.year or ""},"{paper.authors}","{paper.source}",{paper.citations}\n')

    log_msg(f"  Results: {stats['downloaded']} downloaded, {stats['failed']} failed, {stats['skipped']} skipped")
    return stats


def main(species_filter: List[str] = None):
    """Main entry point."""
    log_msg("=" * 60)
    log_msg("ADDITIONAL LITERATURE FETCHER")
    log_msg("Sources: Semantic Scholar, CORE")
    log_msg("=" * 60)

    log_msg(f"Output path: {SPECIES_DOCS_BASE_PATH}")
    log_msg(f"Semantic Scholar: Available (REST API)")
    log_msg(f"CORE API key: {'Loaded' if CORE_API_KEY else 'Not found'}")

    # Derive species list from existing folders (same source as get_species_literature.R)
    species_list = get_species_from_folders(SPECIES_DOCS_BASE_PATH)
    if not species_list:
        log_msg("No species folders found")
        return

    # Apply species filter if provided
    if species_filter:
        filter_lower = [s.lower() for s in species_filter]
        species_list = [sp for sp in species_list if sp.scientific_name.lower() in filter_lower]
        if not species_list:
            log_msg(f"No species matched filter: {species_filter}")
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
    import argparse

    parser = argparse.ArgumentParser(description="Additional Literature Fetcher for BioPRIO")
    parser.add_argument("--output", type=str, default=SPECIES_DOCS_BASE_PATH,
                        help="Base directory containing species folders")
    parser.add_argument("--species", type=str, nargs="+", default=None,
                        help="Filter by species names (e.g., --species 'Lasius aphidicola')")
    parser.add_argument("--limit", type=int, default=MAX_RESULTS_PER_SOURCE,
                        help="Max results per source")

    cli_args = parser.parse_args()

    # Override globals with args
    SPECIES_DOCS_BASE_PATH = cli_args.output
    MAX_RESULTS_PER_SOURCE = cli_args.limit

    main(species_filter=cli_args.species)

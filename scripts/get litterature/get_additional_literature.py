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


if __name__ == "__main__":
    log_msg("Additional Literature Fetcher")
    log_msg(f"Species docs path: {SPECIES_DOCS_BASE_PATH}")
    log_msg(f"Database path: {DATABASE_PATH}")
    log_msg(f"Semantic Scholar available: {SEMANTIC_SCHOLAR_AVAILABLE}")
    log_msg(f"CORE API key loaded: {bool(CORE_API_KEY)}")

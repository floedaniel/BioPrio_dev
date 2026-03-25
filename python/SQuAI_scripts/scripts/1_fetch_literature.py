"""
fetch_literature.py
-------------------
Downloads scientific literature per species into separate folders,
ready for pdf_to_squai_corpus.py to index.

Sources (in priority order):
  1. Europe PMC  – search + direct PDF download (biology-focused, incl. Agricola)
  2. Unpaywall   – legal open-access PDF via DOI for articles without direct PDF
  3. Semantic Scholar – broad biology coverage, PDF links
  4. OpenAlex    – fallback metadata + abstract if no PDF found anywhere

Output structure:
  <LIT_DIR>/
      Thrips_palmi/
          Murai_2000_Thrips_palmi.pdf
          ...
          _metadata.jsonl      ← bibliographic records for all downloaded articles
          _abstracts.jsonl     ← abstracts for articles where no PDF was obtained
      Liriomyza_huidobrensis/
          ...

APIs used (all free, no authentication required except Unpaywall email):
  - https://www.ebi.ac.uk/europepmc/webservices/rest/search
  - https://api.unpaywall.org/v2/{doi}?email={EMAIL}
  - https://api.semanticscholar.org/graph/v1/paper/search
  - https://api.openalex.org/works

Dependencies:
    pip install requests tqdm
"""

# ==============================================================================
# USER CONFIGURATION
# ==============================================================================

# Species to fetch literature for.
# Use the same names as in 2_generate_finnprio_questions.py (spaces, not underscores).
SPECIES_LIST = [
    "Thrips palmi",
    "Liriomyza huidobrensis",
    "Liriomyza trifolii",
    # add more species here ...
]

# Root folder where species sub-folders will be created.
# Must match LIT_DIR in pdf_to_squai_corpus.py.
LIT_DIR = r"C:\Users\dafl\Python\SQuAI\literature"           # <-- SET THIS

# Your email address – required by Unpaywall API (free, no account needed).
# See: https://unpaywall.org/products/api
UNPAYWALL_EMAIL = "email.uncut083@passmail.net"      # <-- SET THIS

# Maximum number of articles to download per species per source.
# Total max per species = MAX_PER_SOURCE * number of sources (deduplication applied).
MAX_PER_SOURCE = 20                             # <-- SET THIS

# Search query template. {species} is replaced with the species name.
# Extend with plant health / invasion biology terms as needed.
QUERY_TEMPLATE = (
    '"{species}" AND ('
    'pest OR invasive OR "host plant" OR "plant health" OR '
    'biology OR distribution OR establishment OR "life cycle" OR '
    '"host range" OR "economic impact" OR ecology'
    ')'
)

# Minimum year filter (set to None for no filter).
MIN_YEAR = 1990                                 # <-- SET THIS (or None)

# Pause between HTTP requests (seconds) – be polite to APIs.
REQUEST_DELAY = 1.0

# Extra delay before each Semantic Scholar request (seconds).
# S2 enforces a strict rate limit; 5–10 s between calls avoids 429 errors.
SS_REQUEST_DELAY = 8.0

# Also write abstracts as plain-text .txt files alongside PDFs so that
# pdf_to_squai_corpus.py can index them directly (no PDF extraction needed).
# Set False if you only want PDFs.
INDEX_ABSTRACTS = False

# ==============================================================================
# END OF USER CONFIGURATION
# ==============================================================================

import re
import json
import time
import logging
import argparse
from pathlib import Path
from datetime import datetime
from urllib.parse import quote_plus

import requests
from tqdm import tqdm

logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
log = logging.getLogger(__name__)

SESSION = requests.Session()
SESSION.headers.update({"User-Agent": "fetch_literature/1.0 (VKM BioPRIO pipeline)"})


# ── helpers ────────────────────────────────────────────────────────────────────

def safe_filename(species: str, title: str, year: str, idx: int) -> str:
    """Generate a readable, filesystem-safe PDF filename."""
    sp   = species.replace(" ", "_")
    ttl  = re.sub(r"[^\w\s-]", "", title or "untitled")[:60].strip().replace(" ", "_")
    yr   = str(year or "unknown")
    return f"{sp}_{yr}_{ttl}_{idx}.pdf"


def sleep():
    time.sleep(REQUEST_DELAY)


def download_pdf(url: str, dest: Path) -> bool:
    """Download a PDF from url to dest. Returns True on success."""
    try:
        r = SESSION.get(url, timeout=30, stream=True)
        if r.status_code == 200 and "pdf" in r.headers.get("Content-Type", "").lower():
            dest.write_bytes(r.content)
            return True
        # some servers don't set Content-Type correctly – check magic bytes
        content = r.content
        if content[:4] == b"%PDF":
            dest.write_bytes(content)
            return True
    except Exception as e:
        log.debug("PDF download failed (%s): %s", url, e)
    return False


# ── Europe PMC ─────────────────────────────────────────────────────────────────

def search_europepmc(species: str, max_results: int) -> list[dict]:
    """Search Europe PMC and return article metadata list."""
    query  = QUERY_TEMPLATE.format(species=species)
    params = {
        "query":       query,
        "format":      "json",
        "resultType":  "core",
        "pageSize":    min(max_results, 100),
        "sort":        "CITED desc",
    }
    if MIN_YEAR:
        params["query"] += f" AND (FIRST_PDATE:[{MIN_YEAR}-01-01 TO *])"

    url = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
    try:
        r = SESSION.get(url, params=params, timeout=20)
        r.raise_for_status()
        data = r.json()
        return data.get("resultList", {}).get("result", [])
    except Exception as e:
        log.warning("Europe PMC search failed for '%s': %s", species, e)
        return []


def europepmc_pdf_url(pmcid: str) -> str | None:
    """Return direct PDF URL for a PMC article if open access."""
    if not pmcid:
        return None
    return f"https://europepmc.org/backend/ptpmcrender.fcgi?accid={pmcid}&blobtype=pdf"


# ── Unpaywall ──────────────────────────────────────────────────────────────────

def unpaywall_pdf_url(doi: str) -> str | None:
    """Look up a legal open-access PDF URL via Unpaywall."""
    if not doi or not UNPAYWALL_EMAIL or UNPAYWALL_EMAIL == "your.email@example.com":
        return None
    url = f"https://api.unpaywall.org/v2/{quote_plus(doi)}?email={UNPAYWALL_EMAIL}"
    try:
        r = SESSION.get(url, timeout=15)
        if r.status_code == 200:
            data = r.json()
            loc  = data.get("best_oa_location") or {}
            return loc.get("url_for_pdf") or loc.get("url")
    except Exception as e:
        log.debug("Unpaywall lookup failed for DOI %s: %s", doi, e)
    return None


# ── Semantic Scholar ───────────────────────────────────────────────────────────

def search_semanticscholar(species: str, max_results: int) -> list[dict]:
    """Search Semantic Scholar with retry/backoff to handle 429 rate limits."""
    query  = f"{species} pest biology invasive plant health"
    params = {
        "query":  query,
        "limit":  min(max_results, 100),
        "fields": "title,year,authors,externalIds,openAccessPdf,abstract",
    }
    url     = "https://api.semanticscholar.org/graph/v1/paper/search"
    retries = 3
    for attempt in range(retries):
        time.sleep(SS_REQUEST_DELAY)   # always wait before S2 calls
        try:
            r = SESSION.get(url, params=params, timeout=20)
            if r.status_code == 429:
                wait = 30 * (attempt + 1)
                log.warning(
                    "Semantic Scholar 429 for '%s' – waiting %ds (attempt %d/%d)",
                    species, wait, attempt + 1, retries
                )
                time.sleep(wait)
                continue
            r.raise_for_status()
            results = r.json().get("data", [])
            normalised = []
            for p in results:
                doi = (p.get("externalIds") or {}).get("DOI", "")
                normalised.append({
                    "_source":   "semanticscholar",
                    "title":     p.get("title", ""),
                    "year":      p.get("year", ""),
                    "doi":       doi,
                    "pmcid":     (p.get("externalIds") or {}).get("PubMedCentral", ""),
                    "abstract":  p.get("abstract", ""),
                    "pdf_url":   (p.get("openAccessPdf") or {}).get("url", ""),
                })
            return normalised
        except Exception as e:
            log.warning("Semantic Scholar search failed for '%s': %s", species, e)
    log.warning("Semantic Scholar: giving up on '%s' after %d attempts", species, retries)
    return []


# ── OpenAlex ───────────────────────────────────────────────────────────────────

def search_openalex(species: str, max_results: int) -> list[dict]:
    """Search OpenAlex and return normalised metadata list."""
    query  = f"{species} pest invasive biology plant health"
    params = {
        "search":    query,
        "per-page":  min(max_results, 200),
        "select":    "id,title,publication_year,doi,open_access,abstract_inverted_index,primary_location",
        "sort":      "cited_by_count:desc",
    }
    if MIN_YEAR:
        params["filter"] = f"publication_year:>{MIN_YEAR - 1}"

    url = "https://api.openalex.org/works"
    try:
        r = SESSION.get(url, params=params, timeout=20)
        r.raise_for_status()
        results = r.json().get("results", [])
        normalised = []
        for p in results:
            doi = (p.get("doi") or "").replace("https://doi.org/", "")
            oa  = p.get("open_access", {})
            pdf = oa.get("oa_url", "")
            # reconstruct abstract from inverted index
            inv = p.get("abstract_inverted_index") or {}
            abstract = ""
            if inv:
                words = {}
                for word, positions in inv.items():
                    for pos in positions:
                        words[pos] = word
                abstract = " ".join(words[k] for k in sorted(words))
            normalised.append({
                "_source":  "openalex",
                "title":    p.get("title", ""),
                "year":     p.get("publication_year", ""),
                "doi":      doi,
                "pmcid":    "",
                "abstract": abstract,
                "pdf_url":  pdf,
            })
        return normalised
    except Exception as e:
        log.warning("OpenAlex search failed for '%s': %s", species, e)
        return []


# ── normalise Europe PMC records ───────────────────────────────────────────────

def normalise_epmc(rec: dict) -> dict:
    return {
        "_source":  "europepmc",
        "title":    rec.get("title", ""),
        "year":     rec.get("firstPublicationDate", "")[:4],
        "doi":      rec.get("doi", ""),
        "pmcid":    rec.get("pmcid", ""),
        "abstract": rec.get("abstractText", ""),
        "pdf_url":  "",   # resolved below
    }


# ── per-species downloader ─────────────────────────────────────────────────────

def fetch_species(species: str, lit_dir: Path) -> dict:
    """
    Full download pipeline for one species.
    Returns summary dict with counts.
    """
    species_key = species.replace(" ", "_")
    out_dir     = lit_dir / species_key
    out_dir.mkdir(parents=True, exist_ok=True)

    log.info("[%s] Searching literature…", species)

    # ── 1. collect candidates from all sources ─────────────────────────────
    candidates: list[dict] = []

    epmc_raw = search_europepmc(species, MAX_PER_SOURCE)
    sleep()
    candidates += [normalise_epmc(r) for r in epmc_raw]

    ss_results = search_semanticscholar(species, MAX_PER_SOURCE)
    sleep()
    candidates += ss_results

    oa_results = search_openalex(species, MAX_PER_SOURCE)
    sleep()
    candidates += oa_results

    # ── 2. deduplicate on DOI (keep first occurrence) ──────────────────────
    seen_dois: set  = set()
    seen_titles: set = set()
    unique: list[dict] = []
    for c in candidates:
        doi   = (c.get("doi") or "").strip().lower()
        title = (c.get("title") or "").strip().lower()[:80]
        key   = doi if doi else title
        if key and key not in seen_dois:
            seen_dois.add(key)
            seen_titles.add(title)
            unique.append(c)
        elif not key:
            unique.append(c)   # no doi/title – keep anyway

    log.info("[%s] %d unique candidates after deduplication", species, len(unique))

    # ── 3. resolve PDF URLs and download ──────────────────────────────────
    downloaded   = 0
    no_pdf       = []
    metadata_log = []

    for idx, rec in enumerate(tqdm(unique, desc=f"  {species}", leave=False)):
        pdf_url = rec.get("pdf_url", "")

        # try PMC direct download
        if not pdf_url and rec.get("pmcid"):
            pdf_url = europepmc_pdf_url(rec["pmcid"])

        # try Unpaywall
        if not pdf_url and rec.get("doi"):
            pdf_url = unpaywall_pdf_url(rec["doi"])
            sleep()

        fname = safe_filename(species, rec.get("title", ""), rec.get("year", ""), idx)
        dest  = out_dir / fname

        if pdf_url and not dest.exists():
            ok = download_pdf(pdf_url, dest)
            sleep()
            if ok:
                downloaded += 1
                rec["local_pdf"] = fname
                log.debug("  Downloaded: %s", fname)
            else:
                rec["local_pdf"] = None
                no_pdf.append(rec)
        elif dest.exists():
            rec["local_pdf"] = fname
            downloaded += 1
        else:
            rec["local_pdf"] = None
            no_pdf.append(rec)

        metadata_log.append(rec)

    # ── 4. write metadata and abstracts ───────────────────────────────────
    meta_path = out_dir / "_metadata.jsonl"
    with open(meta_path, "w", encoding="utf-8") as f:
        for rec in metadata_log:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    # write abstracts for articles without PDF:
    #   a) _abstracts.jsonl  – structured, for reference
    #   b) individual .txt files  – picked up by pdf_to_squai_corpus.py as text corpus
    abs_path = out_dir / "_abstracts.jsonl"
    abs_txt_count = 0
    with open(abs_path, "w", encoding="utf-8") as f:
        for rec in no_pdf:
            abstract = rec.get("abstract", "").strip()
            if not abstract:
                continue
            f.write(json.dumps({
                "species":  species,
                "title":    rec.get("title", ""),
                "year":     rec.get("year", ""),
                "doi":      rec.get("doi", ""),
                "abstract": abstract,
                "_source":  rec.get("_source", ""),
            }, ensure_ascii=False) + "\n")

            # write as .txt so pdf_to_squai_corpus.py can index it
            if INDEX_ABSTRACTS:
                txt_name = safe_filename(
                    species, rec.get("title", ""), rec.get("year", ""),
                    9000 + abs_txt_count        # offset avoids collision with PDF indices
                ).replace(".pdf", ".txt")
                txt_path = out_dir / txt_name
                if not txt_path.exists():
                    header = (
                        f"Title: {rec.get('title', '')}\n"
                        f"Year: {rec.get('year', '')}\n"
                        f"DOI: {rec.get('doi', '')}\n"
                        f"Source: {rec.get('_source', '')}\n\n"
                    )
                    txt_path.write_text(header + abstract, encoding="utf-8")
                    abs_txt_count += 1

    summary = {
        "species":       species,
        "candidates":    len(unique),
        "pdfs":          downloaded,
        "abstracts_txt": abs_txt_count,
        "abstracts_only": len([r for r in no_pdf if r.get("abstract")]),
        "output_dir":    str(out_dir),
    }
    log.info(
        "[%s] Done: %d PDFs + %d abstract .txt files → %s",
        species, downloaded, abs_txt_count, out_dir
    )
    return summary


# ── main ───────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Download scientific literature per species for SQuAI indexing"
    )
    parser.add_argument(
        "--species", nargs="+", default=None,
        help="Override SPECIES_LIST (e.g. --species 'Thrips palmi' 'Liriomyza trifolii')"
    )
    parser.add_argument(
        "--lit_dir", default=LIT_DIR,
        help=f"Output root literature directory (default: {LIT_DIR})"
    )
    args = parser.parse_args()

    species_list = args.species if args.species else SPECIES_LIST
    lit_dir      = Path(args.lit_dir)
    lit_dir.mkdir(parents=True, exist_ok=True)

    log.info("Fetching literature for %d species → %s", len(species_list), lit_dir)

    summaries = []
    for species in species_list:
        summary = fetch_species(species, lit_dir)
        summaries.append(summary)

    # write run summary
    summary_path = lit_dir / f"_fetch_summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summaries, f, indent=2, ensure_ascii=False)

    log.info("\n── Summary ──────────────────────────────")
    for s in summaries:
        log.info(
            "  %-35s  %3d PDFs   %3d abstracts-only",
            s["species"], s["pdfs"], s["abstracts_only"]
        )
    log.info("Summary written → %s", summary_path)
    log.info("\nNext step: run pdf_to_squai_corpus.py to index the downloaded PDFs.")


if __name__ == "__main__":
    main()

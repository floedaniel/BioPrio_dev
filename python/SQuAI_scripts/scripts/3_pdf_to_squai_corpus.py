"""
3_pdf_to_squai_corpus.py
------------------------
Build per-species SQuAI corpus + indices from curated EndNote PDF libraries.

Expected folder structure:
    literature/
        Liriomyza_huidobrensis/
            paper1.pdf
            paper2.pdf
            ...
        Thrips_palmi/
            ...

For each species sub-folder the script:
  1. Extracts full text from all PDFs (PyMuPDF)
  2. Chunks text with overlap
  3. Builds FAISS (E5 dense) + BM25 (sparse) indices
  4. Writes corpus.jsonl in SQuAI format
  5. Updates $HOME/data_dir pointer so run_SQuAI.py finds the active species

Usage:
    # Process all species in literature/
    python 3_pdf_to_squai_corpus.py --lit_dir ./literature --output_dir ./squai_corpus

    # Process single species
    python 3_pdf_to_squai_corpus.py --lit_dir ./literature --output_dir ./squai_corpus \\
        --species "Liriomyza_huidobrensis"

    # Run SQuAI on a species after indexing
    python 3_pdf_to_squai_corpus.py --lit_dir ./literature --output_dir ./squai_corpus \\
        --species "Liriomyza_huidobrensis" --run_squai --questions finnprio_questions.jsonl

Dependencies:
    pip install pymupdf sentence-transformers faiss-cpu rank-bm25 tqdm
"""


# ==============================================================================
# USER CONFIGURATION  –  edit this block before running
# ==============================================================================

# --- Required paths -----------------------------------------------------------

# Root folder containing one sub-folder per species, each with PDFs inside.
# Sub-folder names become the species identifiers used throughout the pipeline.
#   literature/
#       Liriomyza_huidobrensis/   ← sub-folder name = species ID
#           paper1.pdf
#           paper2.pdf
#       Thrips_palmi/
#           ...
LIT_DIR = r"C:\Users\dafl\Python\SQuAI\literature"          # <-- SET THIS

# Where corpus JSONL files and FAISS/BM25 indices are written.
# One sub-folder is created per species: <OUTPUT_DIR>/<species_name>/
OUTPUT_DIR = r"C:\Users\dafl\Python\SQuAI\squai_corpus"     # <-- SET THIS

# Path to the cloned SQuAI repository (only needed if RUN_SQUAI = True).
# Clone with: git clone https://github.com/faerber-lab/SQuAI.git
SQUAI_DIR = r"C:\Users\dafl\Python\SQuAI\squai_repo"             # <-- SET THIS

# JSONL file with FinnPRIO questions fed to SQuAI agents.
# (only needed if RUN_SQUAI = True)
QUESTIONS_FILE = r"C:\Users\dafl\Python\SQuAI\finnprio\finnprio_questions.jsonl"   # <-- SET THIS

# --- Species selection --------------------------------------------------------

# Process only this species sub-folder.  Set to None to process ALL sub-folders.
# Must match the sub-folder name exactly (case-sensitive on Linux/WSL2).
#   Example:  SPECIES_FILTER = "Liriomyza_huidobrensis"
#             SPECIES_FILTER = None   ← all species
SPECIES_FILTER = "Thrips_palmi"                           # <-- SET THIS (or leave None)

# --- Run control --------------------------------------------------------------

# Set True to automatically invoke run_SQuAI.py after indexing each species.
# Requires SQUAI_DIR and QUESTIONS_FILE to be set correctly above.
RUN_SQUAI = True                               # <-- SET THIS

# Set True to skip indexing and run SQuAI directly on already-built indices.
# Use this when indices already exist and you just want to (re-)run the agents.
SQUAI_ONLY = True                              # <-- SET THIS

# --- SQuAI agent parameters (advanced, defaults match SQuAI paper) ------------

# Model options:
#   Local (GPU):   "tiiuae/Falcon3-10B-Instruct"   (best quality, needs GPU)
#   Local (CPU):   "tiiuae/Falcon3-1B-Instruct"    (fast, runs on CPU)
#   OpenAI API:    "gpt-4o-mini"  /  "gpt-4o"      (requires OPENAI_API_KEY env var)
#   Anthropic API: "claude-sonnet-4-6"              (requires ANTHROPIC_API_KEY env var)
SQUAI_MODEL = "tiiuae/Falcon3-1B-Instruct"    # LLM used by SQuAI agents
SQUAI_ALPHA = 0.65    # hybrid retrieval weight: 1.0 = dense only, 0.0 = BM25 only
SQUAI_TOP_K = 20      # number of passages retrieved per sub-question
SQUAI_N     = 0.5     # Judge bar adjustment factor (higher = stricter filtering)

# --- Chunking parameters (advanced) ------------------------------------------

CHUNK_SIZE      = 400   # words per chunk
CHUNK_OVERLAP   = 60    # word overlap between consecutive chunks
MIN_CHUNK_WORDS = 40    # discard chunks shorter than this (headers, captions)

# --- Embedding model (advanced) -----------------------------------------------

# Must match the model used when SQuAI runs dense retrieval.
# "intfloat/e5-base-v2" is the SQuAI default; change only if you reconfigure SQuAI.
EMBEDDING_MODEL = "intfloat/e5-base-v2"

# ==============================================================================
# END OF USER CONFIGURATION  –  do not edit below unless you know what you do
# ==============================================================================

import os
import re
import sys
import json
import pickle
import hashlib
import logging
import argparse
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Optional

import numpy as np
from tqdm import tqdm

# ── dependency guards ──────────────────────────────────────────────────────────
try:
    import fitz  # PyMuPDF
    HAS_FITZ = True
except ImportError:
    HAS_FITZ = False
    print("WARNING: PyMuPDF not installed. Run: pip install pymupdf")

try:
    import faiss
    from sentence_transformers import SentenceTransformer
    HAS_FAISS = True
except ImportError:
    HAS_FAISS = False
    print("WARNING: faiss / sentence-transformers not installed. Run: pip install faiss-cpu sentence-transformers")

try:
    from rank_bm25 import BM25Okapi
    HAS_BM25 = True
except ImportError:
    HAS_BM25 = False
    print("WARNING: rank_bm25 not installed. Run: pip install rank-bm25")

# ── config (values drawn from USER CONFIGURATION block above) ─────────────────
# EMBEDDING_MODEL, CHUNK_SIZE, CHUNK_OVERLAP, MIN_CHUNK_WORDS already defined.

_log_path = Path(OUTPUT_DIR).parent / "logs" / f"pdf_to_squai_corpus_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
_log_path.parent.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(_log_path, encoding="utf-8"),
    ],
)
log = logging.getLogger(__name__)
log.info("Log file: %s", _log_path)


# ── PDF extraction ─────────────────────────────────────────────────────────────

def extract_pdf_text(pdf_path: Path) -> Optional[str]:
    """Extract full text from a PDF using PyMuPDF."""
    if not HAS_FITZ:
        raise RuntimeError("PyMuPDF (fitz) not installed")
    try:
        doc  = fitz.open(str(pdf_path))
        pages = [page.get_text("text") for page in doc]
        doc.close()
        text = "\n".join(pages)
        # basic cleanup: collapse whitespace, remove lone page numbers
        text = re.sub(r"\n{3,}", "\n\n", text)
        text = re.sub(r"(?m)^\s*\d+\s*$", "", text)
        return text.strip()
    except Exception as e:
        log.warning("Could not extract %s: %s", pdf_path.name, e)
        return None


def pdf_metadata(pdf_path: Path) -> dict:
    """Extract title / author metadata from PDF if available."""
    if not HAS_FITZ:
        return {}
    try:
        doc  = fitz.open(str(pdf_path))
        meta = doc.metadata or {}
        doc.close()
        return {
            "title":  meta.get("title", pdf_path.stem),
            "author": meta.get("author", ""),
        }
    except Exception:
        return {"title": pdf_path.stem, "author": ""}


# ── chunking ───────────────────────────────────────────────────────────────────

def chunk_text(text: str) -> list[str]:
    """Split text into overlapping word-level chunks."""
    words = text.split()
    chunks, i = [], 0
    while i < len(words):
        chunk = " ".join(words[i: i + CHUNK_SIZE])
        if len(chunk.split()) >= MIN_CHUNK_WORDS:
            chunks.append(chunk)
        i += CHUNK_SIZE - CHUNK_OVERLAP
    return chunks


# ── corpus document format ─────────────────────────────────────────────────────

def make_doc(species: str, pdf_path: Path, chunk: str,
             chunk_idx: int, meta: dict) -> dict:
    """
    SQuAI corpus document schema (mirrors unarXive layout expected by
    hybrid_retriever.py and run_SQuAI.py).
    """
    uid = hashlib.md5(
        f"{species}|{pdf_path.name}|{chunk_idx}".encode()
    ).hexdigest()[:12]

    return {
        "paper_id":  uid,
        "title":     meta.get("title", pdf_path.stem),
        "abstract":  chunk if chunk_idx == 0 else "",
        "body_text": [{"section": "content", "text": chunk}],
        "metadata":  {
            "species":   species,
            "source":    pdf_path.name,
            "chunk_idx": chunk_idx,
            "author":    meta.get("author", ""),
        },
    }


# ── index builders ─────────────────────────────────────────────────────────────

def build_faiss_index(corpus: list[dict], species_dir: Path) -> None:
    if not HAS_FAISS:
        log.warning("Skipping FAISS – missing dependencies")
        return

    log.info("  Building FAISS index (%d chunks)…", len(corpus))
    model = SentenceTransformer(EMBEDDING_MODEL)

    texts = [
        d["abstract"] if d["abstract"] else d["body_text"][0]["text"]
        for d in corpus
    ]
    embeddings = model.encode(
        texts, batch_size=64, show_progress_bar=False,
        normalize_embeddings=True
    )

    dim   = embeddings.shape[1]
    index = faiss.IndexFlatIP(dim)
    index.add(np.array(embeddings, dtype=np.float32))

    faiss_dir = species_dir / "faiss_index"
    faiss_dir.mkdir(parents=True, exist_ok=True)
    faiss.write_index(index, str(faiss_dir / "index.faiss"))

    with open(faiss_dir / "id_map.json", "w") as f:
        json.dump([d["paper_id"] for d in corpus], f)

    log.info("  FAISS saved → %s (%d vectors, dim=%d)",
             faiss_dir, index.ntotal, dim)


def build_bm25_index(corpus: list[dict], species_dir: Path) -> None:
    if not HAS_BM25:
        log.warning("Skipping BM25 – missing dependencies")
        return

    log.info("  Building BM25 index…")
    tokenised = [
        (d["abstract"] or d["body_text"][0]["text"]).lower().split()
        for d in corpus
    ]
    bm25 = BM25Okapi(tokenised)

    bm25_dir = species_dir / "bm25_index"
    bm25_dir.mkdir(parents=True, exist_ok=True)

    with open(bm25_dir / "bm25.pkl", "wb") as f:
        pickle.dump(bm25, f)
    with open(bm25_dir / "id_map.json", "w") as f:
        json.dump([d["paper_id"] for d in corpus], f)

    log.info("  BM25 saved → %s", bm25_dir)


# ── per-species pipeline ───────────────────────────────────────────────────────

def process_species(species_name: str, pdf_dir: Path,
                    output_dir: Path, force: bool = False) -> Path:
    """
    Full indexing pipeline for one species.
    Indexes PDFs (full text) found recursively under pdf_dir.
    Returns path to the species output directory.
    Skips indexing if indices already exist unless force=True.
    """
    species_out = output_dir / species_name
    faiss_done  = (species_out / "faiss_index" / "index.faiss").exists()
    bm25_done   = (species_out / "bm25_index"  / "bm25.pkl").exists()
    corpus_done = (species_out / "corpus.jsonl").exists()

    if faiss_done and bm25_done and corpus_done and not force:
        log.info("[%s] Indices already exist – skipping indexing (use --force_index to rebuild)", species_name)
        return species_out

    pdfs = sorted(pdf_dir.rglob("*.pdf"))

    if not pdfs:
        log.warning("[%s] No PDFs found under %s", species_name, pdf_dir)
        return None

    log.info("[%s] Processing %d PDFs…", species_name, len(pdfs))

    corpus: list[dict] = []
    seen_hashes: set   = set()

    # ── PDFs ──────────────────────────────────────────────────────────────
    for pdf_path in tqdm(pdfs, desc=f"  {species_name} PDFs", leave=False):
        text = extract_pdf_text(pdf_path)
        if not text:
            continue
        meta   = pdf_metadata(pdf_path)
        chunks = chunk_text(text)

        for idx, chunk in enumerate(chunks):
            h = hashlib.md5(chunk.encode()).hexdigest()
            if h in seen_hashes:
                continue
            seen_hashes.add(h)
            corpus.append(make_doc(species_name, pdf_path, chunk, idx, meta))

    if not corpus:
        log.warning("[%s] No text extracted – skipping", species_name)
        return None

    log.info("[%s] %d chunks from %d PDFs", species_name, len(corpus), len(pdfs))

    # output directory for this species
    species_out = output_dir / species_name
    species_out.mkdir(parents=True, exist_ok=True)

    # write corpus JSONL
    corpus_path = species_out / "corpus.jsonl"
    with open(corpus_path, "w", encoding="utf-8") as f:
        for doc in corpus:
            f.write(json.dumps(doc, ensure_ascii=False) + "\n")

    # build indices
    build_faiss_index(corpus, species_out)
    build_bm25_index(corpus, species_out)

    # metadata
    meta_out = {
        "species":         species_name,
        "created":         datetime.now().isoformat(),
        "n_pdfs":          len(pdfs),
        "n_chunks":        len(corpus),
        "embedding_model": EMBEDDING_MODEL,
        "chunk_size":      CHUNK_SIZE,
        "chunk_overlap":   CHUNK_OVERLAP,
        "pdfs":            [p.name for p in pdfs],
    }
    with open(species_out / "meta.json", "w") as f:
        json.dump(meta_out, f, indent=2)

    log.info("[%s] Done → %s", species_name, species_out)
    return species_out


def set_squai_data_dir(species_dir: Path) -> None:
    """Write $HOME/data_dir so run_SQuAI.py uses this species corpus."""
    data_dir_file = Path.home() / "data_dir"
    data_dir_file.write_text(str(species_dir.resolve()))
    log.info("SQuAI data_dir → %s", species_dir.resolve())


def filter_questions_for_species(questions_file: Path,
                                  species_name: str,
                                  tmp_dir: Path) -> Path:
    """
    Extract only the questions belonging to this species from the full
    finnprio_questions.jsonl and write to a temporary per-species file.

    Matches on the 'species' field (spaces) OR the species_key embedded
    in the 'id' field (underscores), so both naming conventions work.
    """
    species_key = species_name.replace(" ", "_")
    matched = []

    with open(questions_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            # match on explicit species field or id suffix
            if (rec.get("species", "") == species_name or
                    rec.get("id", "").endswith(f"__{species_key}")):
                matched.append(rec)

    if not matched:
        raise ValueError(
            f"No questions found for '{species_name}' in {questions_file}. "
            f"Run 2_generate_finnprio_questions.py first and make sure the species "
            f"name matches exactly (spaces, not underscores)."
        )

    tmp_dir.mkdir(parents=True, exist_ok=True)
    tmp_path = tmp_dir / f"{species_key}_questions.jsonl"
    with open(tmp_path, "w", encoding="utf-8") as f:
        for rec in matched:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    log.info("  [%s] %d questions extracted → %s",
             species_name, len(matched), tmp_path)
    return tmp_path


def run_squai(species_dir: Path, questions_file: Path,
              squai_dir: Path, model: str, alpha: float,
              top_k: int, n: float) -> None:
    """
    Invoke run_SQuAI.py for one species:
      1. Set $HOME/data_dir to this species' corpus index
      2. Filter finnprio_questions.jsonl to only this species' questions
      3. Call run_SQuAI.py with the filtered question file
    """
    set_squai_data_dir(species_dir)
    species_name = species_dir.name.replace("_", " ")   # restore spaces for matching

    results_dir = species_dir / "squai_results"
    results_dir.mkdir(exist_ok=True)

    tmp_dir      = species_dir / "_tmp"
    species_qfile = filter_questions_for_species(
        questions_file, species_name, tmp_dir
    )

    cmd = [
        sys.executable, str(squai_dir / "run_SQuAI.py"),
        "--model",         model,
        "--alpha",         str(alpha),
        "--top_k",         str(top_k),
        "--n",             str(n),
        "--data_file",     str(species_qfile),
        "--output_format", "jsonl",
        "--output_dir",    str(results_dir),
    ]
    log.info("[%s] Running SQuAI…", species_name)
    subprocess.run(cmd, check=True)
    log.info("[%s] SQuAI results → %s", species_name, results_dir)


# ── CLI ────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Build per-species SQuAI corpus from curated PDF libraries"
    )
    parser.add_argument(
        "--lit_dir", default=LIT_DIR,
        help=f"Root literature directory (default: {LIT_DIR})"
    )
    parser.add_argument(
        "--output_dir", default=OUTPUT_DIR,
        help=f"Output root for corpus + indices (default: {OUTPUT_DIR})"
    )
    parser.add_argument(
        "--species", default=SPECIES_FILTER,
        help="Process only this species sub-folder (default: all)"
    )
    parser.add_argument(
        "--run_squai", action="store_true", default=RUN_SQUAI,
        help="Run run_SQuAI.py after indexing"
    )
    parser.add_argument(
        "--questions", default=QUESTIONS_FILE,
        help=f"JSONL file with FinnPRIO questions (default: {QUESTIONS_FILE})"
    )
    parser.add_argument(
        "--squai_dir", default=SQUAI_DIR,
        help=f"Path to cloned SQuAI repo (default: {SQUAI_DIR})"
    )
    parser.add_argument(
        "--model", default=SQUAI_MODEL,
        help=f"LLM for SQuAI agents (default: {SQUAI_MODEL})"
    )
    parser.add_argument("--alpha",       type=float, default=SQUAI_ALPHA)
    parser.add_argument("--top_k",       type=int,   default=SQUAI_TOP_K)
    parser.add_argument("--n",           type=float, default=SQUAI_N)
    parser.add_argument(
        "--force_index", action="store_true", default=False,
        help="Force rebuilding indices even if they already exist"
    )
    parser.add_argument(
        "--squai_only", action="store_true", default=SQUAI_ONLY,
        help="Skip indexing; run SQuAI directly on already-indexed corpus species"
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # --squai_only: skip literature scan, operate directly on corpus output_dir
    if args.squai_only:
        if args.species:
            candidate_dirs = [output_dir / args.species]
        else:
            candidate_dirs = sorted([d for d in output_dir.iterdir() if d.is_dir()])
        indexed: list[Path] = [
            d for d in candidate_dirs
            if (d / "faiss_index" / "index.faiss").exists()
            and (d / "bm25_index" / "bm25.pkl").exists()
        ]
        log.info("squai_only mode: %d indexed species found", len(indexed))
    else:
        lit_dir = Path(args.lit_dir)
        # collect species directories from literature folder
        if args.species:
            species_dirs = [lit_dir / args.species]
        else:
            species_dirs = sorted(
                [d for d in lit_dir.iterdir() if d.is_dir()]
            )

        if not species_dirs:
            log.error("No species sub-folders found in %s", lit_dir)
            return

        log.info("Found %d species to process", len(species_dirs))

        for sp_dir in species_dirs:
            process_species(sp_dir.name, sp_dir, output_dir, force=args.force_index)

        # Collect all species that now have complete indices (regardless of this run)
        indexed = [
            output_dir / sp_dir.name
            for sp_dir in species_dirs
            if (output_dir / sp_dir.name / "faiss_index" / "index.faiss").exists()
            and (output_dir / sp_dir.name / "bm25_index"  / "bm25.pkl").exists()
        ]
        log.info("Indexing complete: %d / %d species have indices", len(indexed), len(species_dirs))

    # optionally loop SQuAI over all indexed species
    if args.run_squai:
        questions_file = Path(args.questions)
        squai_dir      = Path(args.squai_dir)
        if not questions_file.exists():
            log.error("Questions file not found: %s", questions_file)
            return
        if not (squai_dir / "run_SQuAI.py").exists():
            log.error("run_SQuAI.py not found in %s", squai_dir)
            return

        for sp_out in indexed:
            run_squai(
                species_dir=sp_out,
                questions_file=questions_file,
                squai_dir=squai_dir,
                model=args.model,
                alpha=args.alpha,
                top_k=args.top_k,
                n=args.n,
            )

    log.info("All done.")


if __name__ == "__main__":
    main()

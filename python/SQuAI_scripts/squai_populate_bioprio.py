"""
squai_populate_bioprio.py
--------------------------
Replaces populate_bioprio_justifications.py (GPT Researcher) with a local
PDF-based RAG pipeline using SQuAI + Falcon.

Pipeline per species:
  1. Find PDF folder in SPECIES_LIT_ROOT
  2. Index PDFs (FAISS + BM25) via 3_pdf_to_squai_corpus.py
  3. Generate question JSONL from Instructions_BioPrio_assessments.rmd
  4. Run run_SQuAI.py as subprocess
  5. Read SQuAI output JSONL
  6. Write justifications to BioPRIO DB

Usage:
    python squai_populate_bioprio.py
    python squai_populate_bioprio.py --species "Lasius neglectus"
    python squai_populate_bioprio.py --question ENT1
    python squai_populate_bioprio.py --force_index
    python squai_populate_bioprio.py --db path/to/database.db
    python squai_populate_bioprio.py --db_only
    python squai_populate_bioprio.py --force_squai
"""

import sys
import os
import json
import shutil
import sqlite3
import logging
import argparse
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple

# ── sys.path: make gpt_researcher_scripts importable ─────────────────────────
_HERE = Path(__file__).parent                           # .../python/SQuAI_scripts/
_GPT_DIR = _HERE.parent / "gpt_researcher_scripts"
if str(_GPT_DIR) not in sys.path:
    sys.path.insert(0, str(_GPT_DIR))

# ── sys.path: make 3_pdf_to_squai_corpus importable ──────────────────────────
_SCRIPTS_DIR = _HERE / "scripts"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

# ==============================================================================
# USER CONFIGURATION
# ==============================================================================

# BioPRIO database to enhance (copy will be written to same directory)
DEFAULT_DB_PATH = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\FinnPrio\BioiPRIO_development\databases\ant_test\clean_ants.db"

# Root folder: one sub-folder per species named {GBIF_KEY}_{Species_Name}/
SPECIES_LIT_ROOT = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\VKM Data\27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species"

# SQuAI repo path — resolved relative to this script
SQUAI_DIR  = _HERE / "squai_repo"

# Corpus output dir — FAISS/BM25 indices + results per species
CORPUS_DIR = _HERE / "squai_corpus"

# LLM for SQuAI agents (local CPU model — no API key needed)
SQUAI_MODEL          = "tiiuae/Falcon3-1B-Instruct"
SQUAI_ALPHA          = 0.65      # hybrid weight: 1.0 = dense only, 0.0 = BM25 only
SQUAI_TOP_K          = 20        # passages retrieved per sub-question
SQUAI_N              = 0.5       # judge bar adjustment (higher = stricter)
SQUAI_RETRIEVER_TYPE = "hybrid"  # "hybrid" | "bm25" | "e5"

# Filters — same semantics as populate_bioprio_justifications.py
SPECIES_FILTER  = []    # empty = all species; supports scientific name or GBIF key
QUESTION_FILTER = None  # e.g. "ENT1"; None = all questions
SKIP_EXISTING_JUSTIFICATION = True  # skip questions already answered in DB

# ==============================================================================
# END OF USER CONFIGURATION
# ==============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
log = logging.getLogger(__name__)


# ==============================================================================
# PDF FOLDER DISCOVERY
# ==============================================================================

def find_species_pdf_folder(
    species_name: str,
    gbif_key: str,
    lit_root: Path
) -> Optional[Path]:
    """
    Find the PDF folder for a species in SPECIES_LIT_ROOT.

    Strategy 1: folder starting with "{gbif_key}_"
    Strategy 2: folder containing species name (spaces -> underscores)
    Returns None if not found.
    """
    if not lit_root.exists():
        log.warning("SPECIES_LIT_ROOT not found: %s", lit_root)
        return None

    # Strategy 1: match by GBIF key prefix
    if gbif_key:
        for d in lit_root.iterdir():
            if d.is_dir() and d.name.startswith(f"{gbif_key}_"):
                log.info("  Found PDF folder (GBIF key): %s", d.name)
                return d

    # Strategy 2: fuzzy match on scientific name
    name_key = species_name.replace(" ", "_").lower()
    for d in lit_root.iterdir():
        if d.is_dir() and name_key in d.name.lower():
            log.info("  Found PDF folder (name match): %s", d.name)
            return d

    log.warning("  No PDF folder found for '%s' (gbifKey=%s)", species_name, gbif_key)
    return None


# ==============================================================================
# DATABASE FUNCTIONS
# ==============================================================================

def copy_database(source_path: str) -> str:
    """
    Copy DB to {same_dir}/{base}_squai_enhanced_{YYYYMMDD}.db.
    Returns path to the copy. Safe to re-run same day (detects existing copy).
    Note: date format is ISO YYYYMMDD, intentionally different from the older
    ai_enhanced_DD_MM_YYYY pattern in populate_bioprio_justifications.py.
    """
    src = Path(source_path)
    base = src.stem
    # Strip existing squai_enhanced suffix if re-running
    if "_squai_enhanced_" in base:
        base = base.split("_squai_enhanced_")[0]
    datestamp = datetime.now().strftime("%Y%m%d")
    out_name = f"{base}_squai_enhanced_{datestamp}.db"
    out_path = src.parent / out_name

    if src.resolve() == out_path.resolve():
        log.info("DB copy already exists (same-day re-run): %s", out_path)
        return str(out_path)

    log.info("Copying DB: %s → %s", src.name, out_path.name)
    shutil.copy2(src, out_path)
    return str(out_path)


def get_all_assessments(db_path: str, species_filter: List[str] = None) -> List[Dict]:
    """
    Return list of {idAssessment, scientificName, eppoCode, gbifTaxonKey}
    for all assessments, optionally filtered by species identifiers.
    """
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    if species_filter:
        placeholders = ",".join(["?" for _ in species_filter])
        upper = [f.upper() for f in species_filter]
        cur.execute(f"""
            SELECT a.idAssessment, p.scientificName, p.eppoCode, p.gbifTaxonKey
            FROM assessments a
            JOIN pests p ON a.idPest = p.idPest
            WHERE UPPER(p.eppoCode) IN ({placeholders})
               OR UPPER(p.scientificName) IN ({placeholders})
               OR p.gbifTaxonKey IN ({placeholders})
            ORDER BY a.idAssessment
        """, upper + upper + species_filter)
    else:
        cur.execute("""
            SELECT a.idAssessment, p.scientificName, p.eppoCode, p.gbifTaxonKey
            FROM assessments a
            JOIN pests p ON a.idPest = p.idPest
            ORDER BY a.idAssessment
        """)

    rows = cur.fetchall()
    conn.close()
    return [
        {"idAssessment": r[0], "scientificName": r[1],
         "eppoCode": r[2] or "", "gbifTaxonKey": str(r[3] or "")}
        for r in rows
    ]


def get_answer_rows(db_path: str, assessment_id: int) -> List[Dict]:
    """
    Get answer rows for an assessment. Creates missing rows (empty strings)
    matching app behavior. Returns list of {idAnswer, code, existing_justification}.
    """
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
        SELECT idQuestion, "group", number, subgroup
        FROM questions ORDER BY idQuestion
    """)
    questions = cur.fetchall()

    rows = []
    created = 0
    for id_q, grp, num, subgrp in questions:
        cur.execute("""
            SELECT idAnswer, justification FROM answers
            WHERE idAssessment = ? AND idQuestion = ?
        """, (assessment_id, id_q))
        row = cur.fetchone()
        if row:
            id_ans, just = row
        else:
            cur.execute("""
                INSERT INTO answers (idAssessment, idQuestion, min, likely, max, justification)
                VALUES (?, ?, '', '', '', '')
            """, (assessment_id, id_q))
            id_ans = cur.lastrowid
            just = ""
            created += 1

        code = f"{grp}{num}.{subgrp}" if subgrp else f"{grp}{num}"
        rows.append({"idAnswer": id_ans, "code": code,
                     "existing_justification": just or ""})

    if created:
        conn.commit()
        log.info("  Created %d answer rows", created)
    conn.close()
    return rows


def update_answer_justification(db_path: str, id_answer: int, justification: str):
    """Write justification to answers table."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("UPDATE answers SET justification = ? WHERE idAnswer = ?",
                (justification, id_answer))
    if cur.rowcount == 0:
        conn.close()
        raise RuntimeError(f"No answers row for idAnswer={id_answer}")
    conn.commit()
    conn.close()


def get_assessment_pathways(db_path: str, assessment_id: int) -> List[Dict]:
    """Get selected pathways for an assessment."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("""
        SELECT ep.idEntryPathway, ep.idPathway, p.name
        FROM entryPathways ep
        JOIN pathways p ON ep.idPathway = p.idPathway
        WHERE ep.idAssessment = ?
        ORDER BY p.idPathway
    """, (assessment_id,))
    rows = [{"idEntryPathway": r[0], "idPathway": r[1], "name": r[2]}
            for r in cur.fetchall()]
    conn.close()
    return rows


def get_pathway_questions(db_path: str) -> List[Dict]:
    """Get pathway questions with their codes (ENT2A/B, ENT3, ENT4)."""
    # idPathQuestion 1=ENT2A, 2=ENT2B, 3=ENT3, 4=ENT4 (hardcoded in DB)
    id_to_code = {1: "ENT2A", 2: "ENT2B", 3: "ENT3", 4: "ENT4"}
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("""
        SELECT idPathQuestion, "group", number FROM pathwayQuestions ORDER BY idPathQuestion
    """)
    rows = [{"idPathQuestion": r[0],
             "code": id_to_code.get(r[0], f"{r[1]}{r[2]}")}
            for r in cur.fetchall()]
    conn.close()
    return rows


def get_existing_pathway_justification(db_path: str, id_entry_pathway: int,
                                       id_path_question: int) -> str:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("""
        SELECT justification FROM pathwayAnswers
        WHERE idEntryPathway = ? AND idPathQuestion = ?
    """, (id_entry_pathway, id_path_question))
    result = cur.fetchone()
    conn.close()
    return result[0] if result and result[0] else ""


def update_pathway_justification(db_path: str, id_entry_pathway: int,
                                 id_path_question: int, justification: str):
    """Upsert justification in pathwayAnswers."""
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute("""
        SELECT idPathAnswer FROM pathwayAnswers
        WHERE idEntryPathway = ? AND idPathQuestion = ?
    """, (id_entry_pathway, id_path_question))
    result = cur.fetchone()
    if result:
        cur.execute("UPDATE pathwayAnswers SET justification = ? WHERE idPathAnswer = ?",
                    (justification, result[0]))
    else:
        cur.execute("""
            INSERT INTO pathwayAnswers (idEntryPathway, idPathQuestion, min, likely, max, justification)
            VALUES (?, ?, '', '', '', ?)
        """, (id_entry_pathway, id_path_question, justification))
    conn.commit()
    conn.close()


# ==============================================================================
# QUESTION JSONL GENERATION
# ==============================================================================

def generate_question_jsonl(
    species_name: str,
    assessment_id: int,
    db_path: str,
    output_dir: Path,
    question_filter: Optional[str] = None,
) -> Path:
    """
    Generate per-species question JSONL for SQuAI from the BioPRIO Rmd instructions.

    Regular questions: id = "{CODE}__{species_underscored}"
    Pathway questions: id = "{CODE}__{pathway_slug}__{species_underscored}"

    Returns path to written JSONL file.
    """
    from bioprio_instructions_loader import (
        build_justification_prompt,
        get_all_question_codes,
        get_pathway_question_codes,
    )

    species_key = species_name.replace(" ", "_")
    records = []

    # ── regular questions ─────────────────────────────────────────────────────
    all_codes = get_all_question_codes()
    pathway_codes = set(get_pathway_question_codes())
    regular_codes = [c for c in all_codes if c not in pathway_codes]

    for code in regular_codes:
        if question_filter and not code.upper().startswith(question_filter.upper()):
            continue
        try:
            prompt = build_justification_prompt(code, species_name)
            records.append({
                "id": f"{code}__{species_key}",
                "species": species_name,
                "question": prompt,
            })
        except KeyError as e:
            log.warning("  Skipping question %s: %s", code, e)

    # ── pathway questions ─────────────────────────────────────────────────────
    pathways = get_assessment_pathways(db_path, assessment_id)
    path_q_codes = get_pathway_question_codes()

    for pathway in pathways:
        for code in path_q_codes:
            if question_filter and not code.upper().startswith(question_filter.upper()):
                continue
            try:
                prompt = build_justification_prompt(
                    code, species_name, pathway_name=pathway["name"]
                )
                pathway_slug = pathway["name"].replace(" ", "_")[:30]
                records.append({
                    "id": f"{code}__{pathway_slug}__{species_key}",
                    "species": species_name,
                    "question": prompt,
                })
            except KeyError as e:
                log.warning("  Skipping pathway question %s (%s): %s",
                            code, pathway["name"], e)

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"{species_key}_questions.jsonl"
    with open(out_path, "w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    log.info("  Generated %d questions → %s", len(records), out_path.name)
    return out_path


# ==============================================================================
# SQUAI INVOCATION AND RESULT READING
# ==============================================================================

def find_latest_result(results_dir: Path) -> Optional[Path]:
    """Return most-recently-modified *.jsonl in results_dir, or None."""
    jsonl_files = list(results_dir.glob("*.jsonl"))
    if not jsonl_files:
        return None
    return max(jsonl_files, key=lambda p: p.stat().st_mtime)


def run_squai_for_species(
    species_name: str,
    corpus_dir: Path,
    questions_file: Path,
    squai_dir: Path,
) -> Optional[Path]:
    """
    Write data_dir, invoke run_SQuAI.py as subprocess, return path to result JSONL.
    Returns None on failure.
    IMPORTANT: must be subprocess (not import) — config.py reads data_dir at import time.
    """
    # Point SQuAI at the per-species corpus (import via importlib; filename starts with digit)
    import importlib
    _corpus_mod = importlib.import_module("3_pdf_to_squai_corpus")
    _corpus_mod.set_squai_data_dir(corpus_dir)
    log.info("  Set data_dir → %s", corpus_dir)

    results_dir = corpus_dir / "squai_results"
    results_dir.mkdir(exist_ok=True)

    cmd = [
        sys.executable,
        str(squai_dir / "run_SQuAI.py"),
        "--model",          SQUAI_MODEL,
        "--alpha",          str(SQUAI_ALPHA),
        "--top_k",          str(SQUAI_TOP_K),
        "--n",              str(SQUAI_N),
        "--retriever_type", SQUAI_RETRIEVER_TYPE,
        "--data_file",      str(questions_file.resolve()),
        "--output_format",  "jsonl",
        "--output_dir",     str(results_dir.resolve()),
    ]

    log.info("  Running SQuAI for %s…", species_name)
    try:
        subprocess.run(cmd, check=True, cwd=str(squai_dir))
    except subprocess.CalledProcessError as e:
        log.error("  SQuAI subprocess failed for %s: %s", species_name, e)
        return None

    return find_latest_result(results_dir)


def read_squai_results(result_file: Path) -> Tuple[Dict[str, str], Dict[Tuple[str, str], str]]:
    """
    Parse SQuAI output JSONL.
    Returns (regular_results, pathway_results).

    ID formats handled:
      "ENT1__Lasius_neglectus"                    -> regular question ENT1
      "ENT2A__Intentional_introduction__Lasius_n" -> pathway question ENT2A,
                                                     pathway slug = Intentional_introduction
    The 'answer' field is used (not 'model_answer' which is an internal field).
    """
    results: Dict[str, str] = {}
    pathway_results: Dict[Tuple[str, str], str] = {}  # (code, pathway_slug) -> answer

    with open(result_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue

            rid = rec.get("id", "")
            answer = rec.get("answer", "").strip()
            if not answer:
                continue

            parts = rid.split("__")
            if len(parts) == 2:
                # Regular: "ENT1__Lasius_neglectus"
                results[parts[0]] = answer
            elif len(parts) == 3:
                # Pathway: "ENT2A__pathway_slug__species"
                pathway_results[(parts[0], parts[1])] = answer

    return results, pathway_results


# ==============================================================================
# SPECIES PIPELINE ORCHESTRATOR
# ==============================================================================

def process_species(
    assessment: Dict,
    db_path: str,
    lit_root: Path,
    corpus_dir: Path,
    squai_dir: Path,
    skip_existing: bool,
    question_filter: Optional[str],
    force_index: bool,
    force_squai: bool,
    db_only: bool,
) -> Dict:
    """
    Full pipeline for one species. Returns summary dict with counts.
    """
    species_name = assessment["scientificName"]
    gbif_key     = assessment["gbifTaxonKey"]
    assessment_id = assessment["idAssessment"]
    species_key  = species_name.replace(" ", "_")
    species_corpus = corpus_dir / species_key

    log.info("── %s (assessment %d) ──", species_name, assessment_id)
    summary = {"species": species_name, "written": 0, "skipped": 0,
               "errors": 0, "warnings": []}

    # ── 1. Find PDF folder ────────────────────────────────────────────────────
    if not db_only:
        pdf_folder = find_species_pdf_folder(species_name, gbif_key, lit_root)
        if pdf_folder is None:
            summary["warnings"].append("No PDF folder found — skipped")
            return summary

        # ── 2. Index PDFs ─────────────────────────────────────────────────────
        # Module name starts with digit — must use importlib
        import importlib
        _corpus_mod = importlib.import_module("3_pdf_to_squai_corpus")
        index_species = _corpus_mod.process_species
        indexed = index_species(
            species_name=species_key,
            pdf_dir=pdf_folder,
            output_dir=corpus_dir,
            force=force_index,
        )
        if indexed is None:
            summary["warnings"].append("Indexing failed (no PDFs or extraction error)")
            return summary

    # ── 3. Check for existing SQuAI results ──────────────────────────────────
    result_file = None
    if not force_squai and skip_existing:
        result_file = find_latest_result(species_corpus / "squai_results")
        if result_file:
            log.info("  Reusing existing SQuAI result: %s", result_file.name)

    # ── 4 & 5. Generate questions + run SQuAI ────────────────────────────────
    if result_file is None and not db_only:
        tmp_dir = species_corpus / "_tmp"
        questions_file = generate_question_jsonl(
            species_name, assessment_id, db_path, tmp_dir, question_filter
        )
        result_file = run_squai_for_species(
            species_name, species_corpus, questions_file, squai_dir
        )
        if result_file is None:
            summary["warnings"].append("SQuAI run failed — no results written")
            return summary

    if db_only and result_file is None:
        result_file = find_latest_result(species_corpus / "squai_results")
        if result_file is None:
            summary["warnings"].append("--db_only: no squai_results found")
            return summary

    # ── 6. Read SQuAI output ──────────────────────────────────────────────────
    regular_results, pathway_results = read_squai_results(result_file)
    log.info("  SQuAI answers: %d regular, %d pathway",
             len(regular_results), len(pathway_results))

    # ── 7. Write regular question justifications ──────────────────────────────
    answer_rows = get_answer_rows(db_path, assessment_id)

    for row in answer_rows:
        code = row["code"]
        if question_filter and not code.upper().startswith(question_filter.upper()):
            continue
        if skip_existing and row["existing_justification"].strip():
            summary["skipped"] += 1
            continue
        answer_text = regular_results.get(code)
        if not answer_text:
            log.warning("  No SQuAI answer for %s", code)
            summary["warnings"].append(f"No answer: {code}")
            continue
        try:
            update_answer_justification(db_path, row["idAnswer"], answer_text)
            summary["written"] += 1
        except Exception as e:
            log.error("  DB write error %s: %s", code, e)
            summary["errors"] += 1

    # ── 7b. Write pathway question justifications ─────────────────────────────
    pathways     = get_assessment_pathways(db_path, assessment_id)
    path_questions = get_pathway_questions(db_path)

    for pathway in pathways:
        for pq in path_questions:
            code = pq["code"]
            if question_filter and not code.upper().startswith(question_filter.upper()):
                continue
            existing = get_existing_pathway_justification(
                db_path, pathway["idEntryPathway"], pq["idPathQuestion"]
            )
            if skip_existing and existing.strip():
                summary["skipped"] += 1
                continue
            pathway_slug = pathway["name"].replace(" ", "_")[:30]
            answer_text = pathway_results.get((code, pathway_slug))
            if not answer_text:
                log.warning("  No SQuAI answer for %s / %s", code, pathway["name"])
                summary["warnings"].append(f"No answer: {code}/{pathway['name']}")
                continue
            try:
                update_pathway_justification(
                    db_path, pathway["idEntryPathway"],
                    pq["idPathQuestion"], answer_text
                )
                summary["written"] += 1
            except Exception as e:
                log.error("  DB write error %s/%s: %s", code, pathway["name"], e)
                summary["errors"] += 1

    return summary


# ==============================================================================
# MAIN ENTRY POINT
# ==============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Populate BioPRIO justifications using SQuAI PDF RAG pipeline"
    )
    parser.add_argument("--db",           default=DEFAULT_DB_PATH,
                        help="Path to BioPRIO SQLite database")
    parser.add_argument("--species",      default=None,
                        help="Process only this species (scientific name or GBIF key)")
    parser.add_argument("--question",     default=QUESTION_FILTER,
                        help="Process only this question code (e.g. ENT1)")
    parser.add_argument("--lit_root",     default=str(SPECIES_LIT_ROOT),
                        help="Root folder of species PDF sub-folders")
    parser.add_argument("--corpus_dir",   default=str(CORPUS_DIR),
                        help="Output folder for FAISS/BM25 indices")
    parser.add_argument("--squai_dir",    default=str(SQUAI_DIR),
                        help="Path to squai_repo/")
    parser.add_argument("--force_index",  action="store_true",
                        help="Rebuild FAISS/BM25 indices even if they exist")
    parser.add_argument("--force_squai",  action="store_true",
                        help="Re-run SQuAI even if results already exist")
    parser.add_argument("--db_only",      action="store_true",
                        help="Skip indexing/SQuAI; write existing results to DB only")
    args = parser.parse_args()

    lit_root   = Path(args.lit_root)
    corpus_dir = Path(args.corpus_dir)
    squai_dir  = Path(args.squai_dir)
    skip_existing = SKIP_EXISTING_JUSTIFICATION
    species_filter = [args.species] if args.species else SPECIES_FILTER

    # Copy DB — all writes go to the copy
    working_db = copy_database(args.db)
    log.info("Working DB: %s", working_db)

    # Get assessments
    assessments = get_all_assessments(working_db, species_filter or None)
    log.info("Processing %d assessment(s)", len(assessments))

    if not assessments:
        log.warning("No assessments found — check SPECIES_FILTER or DB path")
        return

    # Main loop
    all_summaries = []
    for assessment in assessments:
        summary = process_species(
            assessment=assessment,
            db_path=working_db,
            lit_root=lit_root,
            corpus_dir=corpus_dir,
            squai_dir=squai_dir,
            skip_existing=skip_existing,
            question_filter=args.question,
            force_index=args.force_index,
            force_squai=args.force_squai,
            db_only=args.db_only,
        )
        all_summaries.append(summary)

    # Print summary
    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)
    total_written = sum(s["written"] for s in all_summaries)
    total_skipped = sum(s["skipped"] for s in all_summaries)
    total_errors  = sum(s["errors"] for s in all_summaries)
    print(f"Species processed : {len(all_summaries)}")
    print(f"Justifications written : {total_written}")
    print(f"Justifications skipped : {total_skipped}")
    print(f"Errors                 : {total_errors}")
    for s in all_summaries:
        if s["warnings"]:
            print(f"\n  {s['species']}:")
            for w in s["warnings"]:
                print(f"    ⚠  {w}")
    print(f"\nOutput DB: {working_db}")
    print("="*60)
    print("Done. Run populate_bioprio_values.py next to select min/likely/max values.")


if __name__ == "__main__":
    main()

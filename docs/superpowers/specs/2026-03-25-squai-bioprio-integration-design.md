# SQuAI → BioPRIO Integration Design

**Date:** 2026-03-25
**Status:** Approved
**Scope:** Single new script that reads species PDFs via SQuAI and writes justifications to the BioPRIO SQLite database, replacing GPT Researcher as the justification source.

---

## Goal

Replace `populate_bioprio_justifications.py` (GPT Researcher / web search) with a PDF-based RAG pipeline using SQuAI. The new script reads local species literature PDFs, runs the SQuAI 4-agent RAG system, and writes the resulting answers as justifications into the BioPRIO database — ready for `populate_bioprio_values.py` to run unchanged afterward.

---

## New File

```
python/SQuAI_scripts/squai_populate_bioprio.py
```

`populate_bioprio_values.py` is **not modified**.

---

## Configuration

Same style as existing populate scripts (top-of-file constants + CLI overrides):

```python
# BioPRIO database to enhance
DB_PATH = r"C:\Users\dafl\...\databases\ant_test\clean_ants.db"

# Root folder containing one sub-folder per species: {GBIF_KEY}_{Species_Name}/
SPECIES_LIT_ROOT = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\VKM Data\
    27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species"

# SQuAI repo path (contains run_SQuAI.py) — resolved relative to this script
SQUAI_DIR  = Path(__file__).parent / "squai_repo"

# Output dir for FAISS/BM25 indices and SQuAI results (one sub-folder per species)
CORPUS_DIR = Path(__file__).parent / "squai_corpus"

# LLM for SQuAI agents
SQUAI_MODEL = "tiiuae/Falcon3-1B-Instruct"   # local CPU model

# SQuAI retrieval parameters (defaults match SQuAI paper)
SQUAI_ALPHA         = 0.65      # hybrid weight: 1.0 = dense only, 0.0 = BM25 only
SQUAI_TOP_K         = 20        # passages retrieved per sub-question
SQUAI_N             = 0.5       # judge bar adjustment (higher = stricter)
SQUAI_RETRIEVER_TYPE = "hybrid" # "hybrid" | "bm25" | "e5"

# Filters — same semantics as populate_bioprio_justifications.py
SPECIES_FILTER  = []    # empty = all species; supports scientific name or GBIF key
QUESTION_FILTER = None  # e.g. "ENT1"; None = all questions
SKIP_EXISTING_JUSTIFICATION = True   # skip questions already answered in DB
```

---

## Dependencies

`bioprio_instructions_loader.py` must be importable. It lives at
`python/gpt_researcher_scripts/bioprio_instructions_loader.py` and is currently
untracked in git — it must be committed or the `sys.path` must include its directory.
The script adds `gpt_researcher_scripts/` to `sys.path` at the top to ensure the
import works regardless of working directory.

Function signature used:
```python
build_justification_prompt(
    question_code: str,       # e.g. "ENT1"
    species_name: str,        # scientific name, e.g. "Lasius neglectus"
    pathway_name: str = None  # optional; only for pathway questions
) -> str
```

---

## Data Flow (per species)

```
BioPRIO DB
  └─ query: get all pests + assessments (same JOIN as gpt_researcher script)
       │
       ▼ for each species
  1. Find PDF folder
       Scan SPECIES_LIT_ROOT/ for folder starting with "{gbifKey}_"
       Fallback: fuzzy match on scientific name (spaces → underscores)
       If not found: log warning, skip species

  2. Index PDFs  [imported from 3_pdf_to_squai_corpus.py]
       → extract text (PyMuPDF)
       → chunk (400 words, 60 overlap)
       → build FAISS (E5-base-v2) + BM25 indices
       → write corpus.jsonl
       → output: CORPUS_DIR/{scientific_name_underscored}/
       Skip if indices already exist (unless --force_index)
       NOTE: corpus folder uses clean scientific name (e.g. "Lasius_neglectus"),
             NOT the GBIF-prefixed folder name, to avoid key collision in questions

  3. Check for existing SQuAI results
       If CORPUS_DIR/{species}/squai_results/ contains *.jsonl files
       AND SKIP_EXISTING_JUSTIFICATION is True:
         → reuse the most-recently-modified .jsonl (skip running SQuAI again)
       Otherwise: proceed to step 4

  4. Generate question JSONL  [via bioprio_instructions_loader.build_justification_prompt]
       → one record per question code: {"id": "ENT1__Lasius_neglectus", "species": ..., "question": ...}
       → id format: "{QUESTION_CODE}__{species_underscored}"
       → pathway questions: one record per selected pathway (pathway_name substituted)
       → write to CORPUS_DIR/{species}/_tmp/{species}_questions.jsonl

  5. Run SQuAI  [subprocess only — never import; config.py reads data_dir at import time]
       → write CORPUS_DIR/{species}/ to $HOME/data_dir file before subprocess
       → subprocess: run_SQuAI.py
             --model           {SQUAI_MODEL}
             --alpha           {SQUAI_ALPHA}
             --top_k           {SQUAI_TOP_K}
             --n               {SQUAI_N}
             --retriever_type  {SQUAI_RETRIEVER_TYPE}
             --data_file       {absolute path to questions.jsonl}
             --output_format   jsonl
             --output_dir      {absolute path: CORPUS_DIR/{species}/squai_results/}
       → output filename is non-deterministic (timestamp + random suffix)
         → find result: most-recently-modified *.jsonl in squai_results/

  6. Read SQuAI output
       → parse records from most-recently-modified .jsonl in squai_results/
       → each record has field "answer" (not "model_answer" — that is an internal field)
       → id format: "ENT1__Lasius_neglectus" → strip suffix → question code "ENT1"
       → build dict: {question_code: answer_text}

  7. Write justifications to DB
       Regular questions  → answers table
       Pathway questions  → pathwayAnswers table
       Respects SKIP_EXISTING_JUSTIFICATION flag (checked against DB, not SQuAI output)
```

---

## Question Generation

Questions are sourced from `Instructions_BioPrio_assessments.rmd` via the existing
`bioprio_instructions_loader.py` — **not** from `finnprio_questions_template.jsonl`
(which contains outdated plant-pest language).

`build_justification_prompt(question_code, species_name, pathway_name=None)` produces
the full structured prompt (question text + options + guidance) used as the SQuAI
input question.

---

## Pathway Question Handling

Pathway questions (ENT2A, ENT2B, ENT3, ENT4) are per-pathway in the DB:

1. Query selected pathways for the assessment from `entryPathways`
2. For each pathway: call `build_justification_prompt(code, species, pathway_name=pathway.name)`
3. Include as separate records in the question JSONL with id `"ENT2A__{pathway_slug}__{species}"`
4. After SQuAI run, match by id prefix to route to the correct pathway row
5. Write to `pathwayAnswers.justification` (keyed by assessmentId + pathwayQuestionId + pathwayId)

This mirrors the GPT Researcher script's pathway handling exactly.

---

## DB Safety: Database Copy

Before any writes, the script copies the input DB to:
```
{same directory as input DB}/{original_name}_squai_enhanced_{YYYYMMDD}.db
```
All writes go to the copy. The original is never modified.

Note: the separator word (`squai_enhanced`) and date format (ISO `YYYYMMDD`) differ
intentionally from the older GPT Researcher pattern (`ai_enhanced_DD_MM_YYYY`).

Also note: the value written to `$HOME/data_dir` before each subprocess call must be
the per-species corpus path (`CORPUS_DIR/{species}/`), not the root `CORPUS_DIR/`,
because `config.py` derives all index sub-paths (`/faiss_index`, `/bm25_index`) from
that value at import time. See `3_pdf_to_squai_corpus.py` `set_squai_data_dir()` for
the reference implementation.

---

## DB Write Pattern

```python
# Regular questions
UPDATE answers
SET justification = ?
WHERE assessmentId = ? AND questionId = ?

# Pathway questions
UPDATE pathwayAnswers
SET justification = ?
WHERE assessmentId = ? AND pathwayQuestionId = ? AND pathwayId = ?
```

---

## Error Handling

| Situation | Behaviour |
|---|---|
| No PDF folder found for species | Log warning, skip species |
| No PDFs in folder | Log warning, skip species |
| SQuAI subprocess crash | Log error, skip species, continue loop |
| SQuAI produces no answer for a question | Log warning, skip question |
| DB write failure | Log error, continue to next question |

All skips and errors collected and printed in a summary at end of run.

---

## Reused Components

| Component | Source | How used |
|---|---|---|
| PDF indexing functions | `3_pdf_to_squai_corpus.py` | Direct import |
| Question prompts | `bioprio_instructions_loader.py` | Direct import (via sys.path) |
| SQuAI RAG engine | `squai_repo/run_SQuAI.py` | Subprocess only (never import) |
| DB query patterns | `populate_bioprio_justifications.py` | Mirrored |

---

## What Is NOT Changed

- `populate_bioprio_values.py` — unchanged, runs after this script as before
- `3_pdf_to_squai_corpus.py` — unchanged, still usable independently
- `bioprio_instructions_loader.py` — unchanged
- `squai_repo/run_SQuAI.py` — unchanged
- BioPRIO DB schema — no schema changes

---

## CLI Usage

```bash
# All species, all questions
python squai_populate_bioprio.py

# Single species
python squai_populate_bioprio.py --species "Lasius neglectus"

# Single question
python squai_populate_bioprio.py --question ENT1

# Force rebuild of indices
python squai_populate_bioprio.py --force_index

# Custom DB
python squai_populate_bioprio.py --db path/to/database.db

# Skip SQuAI inference — write existing squai_results to DB only
python squai_populate_bioprio.py --db_only

# Force re-run SQuAI even if results already exist
python squai_populate_bioprio.py --force_squai
```

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

# SQuAI repo path (contains run_SQuAI.py)
SQUAI_DIR  = r"...\python\SQuAI_scripts\squai_repo"

# Output dir for FAISS/BM25 indices and SQuAI results (one sub-folder per species)
CORPUS_DIR = r"...\python\SQuAI_scripts\squai_corpus"

# LLM for SQuAI agents
SQUAI_MODEL = "tiiuae/Falcon3-1B-Instruct"   # local CPU model

# SQuAI retrieval parameters (defaults match SQuAI paper)
SQUAI_ALPHA = 0.65   # hybrid weight: 1.0 = dense only, 0.0 = BM25 only
SQUAI_TOP_K = 20     # passages retrieved per sub-question
SQUAI_N     = 0.5    # judge bar adjustment (higher = stricter)

# Filters — same semantics as populate_bioprio_justifications.py
SPECIES_FILTER  = []    # empty = all species; supports scientific name or GBIF key
QUESTION_FILTER = None  # e.g. "ENT1"; None = all questions
SKIP_EXISTING_JUSTIFICATION = True   # skip questions already answered in DB
```

---

## Data Flow (per species)

```
BioPRIO DB
  └─ query: get all pests + assessments (same JOIN as gpt_researcher script)
       │
       ▼ for each species
  1. Find PDF folder
       SPECIES_LIT_ROOT/{GBIF_KEY}_{Species_Name}/
       Matching: scan for folder starting with "{gbifKey}_"
       Fallback: fuzzy match on scientific name (spaces → underscores)
       If not found: log warning, skip species

  2. Index PDFs  [imported from 3_pdf_to_squai_corpus.py]
       → extract text (PyMuPDF)
       → chunk (400 words, 60 overlap)
       → build FAISS (E5-base-v2) + BM25 indices
       → write corpus.jsonl
       → output: CORPUS_DIR/{Species_Name}/
       Skip if indices already exist (unless --force_index)

  3. Generate question JSONL  [via bioprio_instructions_loader.py]
       → build_justification_prompt(question_code, species_name)
       → one record per question code: {id, species, question}
       → pathway questions: one record per selected pathway
       → write to CORPUS_DIR/{Species_Name}/_tmp/{species}_questions.jsonl

  4. Run SQuAI  [subprocess: run_SQuAI.py]
       → set $HOME/data_dir to CORPUS_DIR/{Species_Name}/
       → run_SQuAI.py --model ... --data_file {questions.jsonl} --output_dir {results/}
       → output: CORPUS_DIR/{Species_Name}/squai_results/*.jsonl

  5. Read SQuAI output
       → parse records: {id: "ENT1__Species_Name", answer: "..."}
       → strip species suffix → question code (e.g. "ENT1")
       → build dict: {question_code: answer_text}

  6. Write justifications to DB
       Regular questions  → answers table
       Pathway questions  → pathwayAnswers table
       Respects SKIP_EXISTING_JUSTIFICATION flag
```

---

## Question Generation

Questions are sourced from `Instructions_BioPrio_assessments.rmd` via the existing `bioprio_instructions_loader.py` — **not** from `finnprio_questions_template.jsonl` (which contains outdated plant-pest language).

`build_justification_prompt(question_code, species_name, pathway_name)` produces the full structured prompt (question text + options + guidance) used as the SQuAI input question.

---

## Pathway Question Handling

Pathway questions (ENT2A, ENT2B, ENT3, ENT4) are per-pathway in the DB:

1. Query selected pathways for the assessment from `entryPathways`
2. For each pathway: generate question with pathway name substituted
3. Run SQuAI with pathway-specific question
4. Write to `pathwayAnswers.justification` (keyed by assessmentId + pathwayQuestionId + pathwayId)

This mirrors the GPT Researcher script's pathway handling exactly.

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

The script creates a **copy of the database** before writing (same safety pattern as `populate_bioprio_justifications.py`) so the original is never modified.

---

## Error Handling

| Situation | Behaviour |
|---|---|
| No PDF folder found for species | Log warning, skip species |
| No PDFs in folder | Log warning, skip species |
| SQuAI produces no answer for a question | Log warning, skip question |
| DB write failure | Log error, continue to next question |
| SQuAI subprocess crash | Log error, skip species, continue loop |

All skips and errors collected and printed in a summary at end of run.

---

## Reused Components

| Component | Source | How used |
|---|---|---|
| PDF indexing functions | `3_pdf_to_squai_corpus.py` | Direct import |
| Question prompts | `bioprio_instructions_loader.py` | Direct import |
| SQuAI RAG engine | `squai_repo/run_SQuAI.py` | Subprocess |
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
```

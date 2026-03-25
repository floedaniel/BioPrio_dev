# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SQuAI is a multi-agent RAG system for scientific question-answering, published as a CIKM 2025 demo paper. It uses 4 collaborative LLM agents and hybrid retrieval (BM25 + E5 embeddings) to answer scientific questions with fine-grained citations.

## Installation

```bash
# Linux/WSL2
bash install.sh

# Windows
install.bat

# Manual
pip install -r requirements.txt
```

## Running the System

**Single question (CLI):**
```bash
python squai_repo/run_SQuAI.py \
  --model tiiuae/Falcon3-10B-Instruct \
  --n 0.5 --alpha 0.65 --top_k 20 \
  --single_question "Your question here?"
```

**Batch questions from file:**
```bash
python squai_repo/run_SQuAI.py \
  --model tiiuae/Falcon3-10B-Instruct \
  --n 0.5 --alpha 0.65 --top_k 20 \
  --data_file questions.jsonl --output_format jsonl
```

**Key parameters:**
- `--model`: LLM to use (default: `tiiuae/falcon-3-10b-instruct`)
- `--alpha`: Sparse/dense balance for hybrid retrieval (0–1, default: 0.65; higher = more dense)
- `--n`: Adaptive judge threshold adjustment factor (default: 0.5)
- `--top_k`: Number of documents to retrieve (default: 20)
- `--output_format`: `json`, `jsonl`, or `debug`

**Web UI:**
```bash
# Backend (FastAPI) — typically on HPC
python squai_repo/main.py

# Frontend (Streamlit)
bash squai_repo/frontend.sh  # handles SSH tunneling to HPC
```

## Data Pipeline

Run these scripts in order to build a new corpus:

```bash
# 1. Download papers for species
python finnprio/1_fetch_literature.py

# 2. Generate FinnPRIO questions (must exist before running SQuAI)
python finnprio/2_generate_finnprio_questions.py

# 3. Build FAISS + BM25 indices from PDFs and run SQuAI
python finnprio/3_pdf_to_squai_corpus.py

# 4. Convert results to Word documents
python finnprio/4_squai_to_word.py
```

## Testing

```bash
python squai_repo/test_bm25.py
```

No formal test framework — `test_bm25.py` verifies BM25 imports and basic initialization.

## Architecture

### 4-Agent Pipeline (`squai_repo/run_SQuAI.py`)

1. **Question Splitter** — Detects complex multi-part queries and splits them into sub-questions
2. **Answer Generator** — Retrieves documents and generates Q-A-E triplets (Question, Answer, Evidence) per sub-question
3. **Judge** — Scores Q-A-E triplets; filters weak evidence using adaptive confidence thresholds
4. **Final Synthesizer** — Merges filtered triplets into a coherent answer with inline citations

### Hybrid Retrieval

`hybrid_retriever.py` + `unified_arxiv_retriever.py` implement:
- **Sparse**: BM25 (`bm25_retrieval.py`, `fast_llamaindex_retriever.py`)
- **Dense**: E5 embeddings (`intfloat/e5-large-v2`, dim=1024) with FAISS indices
- **Scoring**: `S_hybrid = α·S_sparse + (1-α)·S_dense`
- Indices stored per-species under `squai_corpus/<Species>/bm25_index/` and `faiss_index/`
- LRU caching for abstracts, full texts, and documents

### Corpus Structure

```
squai_corpus/<Species>/
  bm25_index/      # BM25 sparse retrieval index
  faiss_index/     # FAISS dense retrieval index
  corpus.jsonl     # Chunked document metadata
literature/<Species>/  # Source PDFs
```

### Configuration (`squai_repo/config.py`)

- Embedding model and dimension set here
- Data directory resolved dynamically via `get_paths.py` — supports HPC workspaces (`ws_list`), `/projects/`, `/data/horse/`, and local fallback
- HPC credentials in `squai_repo/defaults.ini`

### Backend/Frontend Split

- `main.py` — FastAPI server, typically deployed on HPC cluster
- `app.py` — Streamlit UI, connects to backend via SSH tunnel (`smartproxy.py`)
- Language detection in `app.py` rejects non-English queries

### Performance Monitoring

`performance_monitor.py` provides a timing decorator and context manager. Records per-operation success/failure with rolling window of last 100 measurements; logs to timestamped files.

## Scalability TODO

These improvements are needed before running at 100 species / 1000 PDFs per species:

1. **Keep LLM loaded across species** — currently `run_SQuAI.py` is launched as a subprocess per species, so the model (2-20 GB) is loaded and discarded 100 times. Fix: refactor `3_pdf_to_squai_corpus.py` to run the species loop inside a single `run_SQuAI.py` process, or accept a list of species + question files in one invocation.

2. **Use API models for large runs** — GPT-4o-mini or Claude Haiku eliminate model load time entirely and allow parallel species processing. Set `SQUAI_MODEL = "gpt-4o-mini"` with `OPENAI_API_KEY` env var.

3. **Parallel species processing** — with API models, multiple species can be processed simultaneously. Add a `--parallel_species N` flag to `3_pdf_to_squai_corpus.py` that runs N species concurrently via `ThreadPoolExecutor`.

4. **GPU for indexing** — at 1000 PDFs/species, E5 embedding on CPU takes ~50 min per species. Install CUDA PyTorch (`pip install torch --index-url https://download.pytorch.org/whl/cu126`) to reduce to ~3 min.

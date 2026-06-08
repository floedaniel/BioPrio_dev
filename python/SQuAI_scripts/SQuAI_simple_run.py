"""
squai_ask.py
------------
Simple SQuAI runner — edit QUESTION and SPECIES_FOLDER below, hit Run in PyCharm.
Builds the FAISS/BM25 index from PDFs if it doesn't exist yet.
"""

import sys
import os
import json
import importlib
import subprocess
import tempfile
from pathlib import Path

# ── Edit these ────────────────────────────────────────────────────────────────

QUESTION = "What Trirachys sartus establish in cold climates?"

# Folder containing PDFs for the species (e.g. the AELSSA folder)
SPECIES_FOLDER = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\Prosjektdata - Dokumenter\VKM Data\26.08.2024_lopende_oppdrag_plantehelse\Species\AELSSA"

# ── Settings (usually fine as-is) ─────────────────────────────────────────────

_HERE = Path(__file__).parent
_SCRIPTS_DIR = _HERE / "scripts"
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

SQUAI_DIR        = _HERE / "squai_repo"
CORPUS_DIR       = _HERE / "squai_corpus"       # index output goes here
MODEL            = "tiiuae/Falcon3-3B-Instruct"
ALPHA            = 0.65
TOP_K            = 20
N                = 0.5
RETRIEVER_TYPE   = "hybrid"

_HF_TOKEN_FILE = r"C:\Users\dafl\Desktop\API keys\hugging_face.txt"
if Path(_HF_TOKEN_FILE).exists():
    os.environ.setdefault("HF_TOKEN", Path(_HF_TOKEN_FILE).read_text().strip())

# ── Run ───────────────────────────────────────────────────────────────────────

def main():
    species_folder = Path(SPECIES_FOLDER)
    corpus_dir     = Path(CORPUS_DIR)
    squai_dir      = Path(SQUAI_DIR).resolve()
    species_key    = species_folder.name  # e.g. "AELSSA"

    # ── 1. Build FAISS/BM25 index if needed ───────────────────────────────────
    species_corpus = corpus_dir / species_key
    corpus_mod = importlib.import_module("3_pdf_to_squai_corpus")

    index_exists = (species_corpus / "faiss_index").exists()
    if not index_exists:
        print(f"Building index from PDFs in {species_folder} ...")
        corpus_mod.process_species(
            species_name=species_key,
            pdf_dir=species_folder,
            output_dir=corpus_dir,
            force=False,
        )
    else:
        print(f"Index already exists at {species_corpus / 'faiss_index'}")

    # ── 2. Point SQuAI at the corpus ──────────────────────────────────────────
    corpus_mod.set_squai_data_dir(species_corpus)

    # ── 3. Write question to temp JSONL ───────────────────────────────────────
    tmp = tempfile.NamedTemporaryFile(
        mode="w", suffix=".jsonl", delete=False, encoding="utf-8"
    )
    json.dump({"id": "q1", "question": QUESTION}, tmp, ensure_ascii=False)
    tmp.write("\n")
    tmp.close()

    results_dir = species_corpus / "squai_results"
    results_dir.mkdir(exist_ok=True)

    # ── 4. Run SQuAI ─────────────────────────────────────────────────────────
    cmd = [
        sys.executable,
        str(squai_dir / "run_SQuAI.py"),
        "--model",          MODEL,
        "--alpha",          str(ALPHA),
        "--top_k",          str(TOP_K),
        "--n",              str(N),
        "--retriever_type", RETRIEVER_TYPE,
        "--data_file",      str(Path(tmp.name).resolve()),
        "--output_format",  "jsonl",
        "--output_dir",     str(results_dir.resolve()),
    ]

    try:
        subprocess.run(cmd, check=True, cwd=str(squai_dir))
    except subprocess.CalledProcessError:
        pass  # SQuAI sometimes exits 1 but still writes results

    Path(tmp.name).unlink(missing_ok=True)

    # ── 5. Print answer ──────────────────────────────────────────────────────
    jsonl_files = list(results_dir.glob("*.jsonl"))
    if not jsonl_files:
        print("[ERROR] No output from SQuAI.")
        return

    result_file = max(jsonl_files, key=lambda p: p.stat().st_mtime)
    with open(result_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            answer = rec.get("answer", "").strip()
            if answer:
                print("\n" + "=" * 60)
                print(answer)
                print("=" * 60)
                return

    print("[ERROR] Result file contained no answer.")


if __name__ == "__main__":
    main()
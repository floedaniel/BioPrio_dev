#!/bin/bash
# install.sh  –  auto-install all dependencies for pdf_to_squai_corpus.py
# Run from the folder containing requirements.txt:  bash install.sh

set -e

echo ""
echo "============================================================"
echo " Installing pdf_to_squai_corpus dependencies"
echo "============================================================"
echo ""

pip install --upgrade pip
pip install -r requirements.txt --break-system-packages 2>/dev/null \
    || pip install -r requirements.txt

echo ""
echo "============================================================"
echo " Verifying key packages"
echo "============================================================"
python -c "import fitz;                  print('OK  PyMuPDF',         fitz.__version__)"
python -c "import faiss;                 print('OK  faiss')"
python -c "import sentence_transformers; print('OK  sentence-transformers')"
python -c "import rank_bm25;             print('OK  rank-bm25')"
python -c "import torch;                 print('OK  torch',           torch.__version__)"
python -c "import transformers;          print('OK  transformers',    transformers.__version__)"

echo ""
echo "Done."

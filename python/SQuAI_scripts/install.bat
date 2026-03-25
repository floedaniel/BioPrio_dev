@echo off
:: install.bat  –  auto-install all dependencies for pdf_to_squai_corpus.py
:: Run from the folder containing requirements.txt

echo.
echo ============================================================
echo  Installing pdf_to_squai_corpus dependencies
echo ============================================================
echo.

:: upgrade pip first
python -m pip install --upgrade pip

:: install all requirements
python -m pip install -r requirements.txt

echo.
echo ============================================================
echo  Verifying key packages
echo ============================================================
python -c "import fitz;                  print('OK  PyMuPDF',         fitz.__version__)"
python -c "import faiss;                 print('OK  faiss')"
python -c "import sentence_transformers; print('OK  sentence-transformers')"
python -c "import rank_bm25;             print('OK  rank-bm25')"
python -c "import torch;                 print('OK  torch',           torch.__version__)"
python -c "import transformers;          print('OK  transformers',    transformers.__version__)"

echo.
echo Done. If any line above shows an error, re-run this script or
echo install that package manually: python -m pip install ^<package^>
echo.
pause

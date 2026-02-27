# BioPRIO Hybrid Justification Populator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a new script that combines web research with local PDF/document analysis using GPT Researcher's hybrid mode.

**Architecture:** Copy existing `populate_bioprio_justifications.py` as base, add document handling functions for the `{GBIF_KEY}_{Scientific_Name}` folder pattern, modify GPTResearcher to use `report_source="hybrid"` when local docs exist.

**Tech Stack:** Python, GPT Researcher, SQLite, asyncio

---

## Task 1: Copy Base Script

**Files:**
- Source: `python/populate_bioprio_justifications.py`
- Create: `python/populate_bioprio_justifications_hybrid.py`

**Step 1: Copy the existing script**

```bash
cd "C:\Users\dafl\OneDrive - Folkehelseinstituttet\FinnPrio\BioiPRIO_development"
copy python\populate_bioprio_justifications.py python\populate_bioprio_justifications_hybrid.py
```

**Step 2: Verify copy succeeded**

Run: `dir python\populate_bioprio_justifications_hybrid.py`
Expected: File exists with same size as original

**Step 3: Commit**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: copy base script for hybrid justification populator"
```

---

## Task 2: Update Script Header and Configuration

**Files:**
- Modify: `python/populate_bioprio_justifications_hybrid.py:1-75`

**Step 1: Update docstring and add hybrid configuration**

Replace lines 1-74 with:

```python
"""
BioPRIO Database Justification Populator (Hybrid Research Version)

Adapted from FinnPRIO for terrestrial invertebrates. Uses HYBRID research mode
that combines web search with local PDF documents for each species.

Key features:
- HYBRID RESEARCH: Combines web search with local PDF documents
- Local docs loaded from Species/{GBIF_KEY}_{Scientific_Name}/ folder
- Falls back to web-only if no local docs found
- Copies entire database (preserves complete structure)
- Appends AI justifications to answers table
- Handles pathway questions for EACH selected pathway
- Clean plain text output (no markdown)
- Question-specific instructions
- Domain exclusions
- Full cost tracking with Excel export
"""

import os
import asyncio
import sqlite3
import shutil
import time
from pathlib import Path
from gpt_researcher import GPTResearcher
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, field
import re

# Import instructions loader (auto-generates JSON from Rmd if needed)
from bioprio_instructions_loader import build_justification_prompt

try:
    import openpyxl
    from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
    from openpyxl.utils.dataframe import dataframe_to_rows
    EXCEL_AVAILABLE = True
except ImportError:
    EXCEL_AVAILABLE = False
    print("⚠️  openpyxl not installed. Excel export disabled. Install with: pip install openpyxl")

# =============================================================================
# CONFIGURATION
# =============================================================================

#  IMPORTANT: READ BEFORE RUNNING
#  THIS SCRIPT CREATES A NEW COPY OF YOUR DATABASE EACH TIME IT RUNS!
#  Using original database again will lose all AI work!

# Skip Existing Justifications
#  True  = Skip questions that already have justification text (recommended for re-runs)
#  False = Append new AI text to existing justifications
SKIP_EXISTING_JUSTIFICATION = True

# DATABASE PATH - UPDATE THIS IF YOU ADDED PATHWAYS
DEFAULT_DB_PATH = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\FinnPrio\BioiPRIO_development\databases\ant_test\clean_ants.db"

# Output directory (new copy will be created here)
DEFAULT_OUTPUT_DIR = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\FinnPrio\BioiPRIO_development\databases\ant_test"

# Filter by species identifiers (empty list = process all species)
# Supports: EPPO codes, scientific names, or GBIF taxon keys ["1315155", "1317433"]
SPECIES_FILTER = []

# Filter by question code (None = process all questions)
# Example: QUESTION_FILTER = "EST2"  # Only process EST2
# Pathway questions: "ENT2A", "ENT2B", "ENT3", "ENT4"
QUESTION_FILTER = None

# =============================================================================
# HYBRID RESEARCH - LOCAL DOCUMENTS CONFIGURATION
# =============================================================================

# Base path where species folders with PDFs are stored
SPECIES_DOCS_BASE_PATH = r"C:\Users\dafl\OneDrive - Folkehelseinstituttet\VKM Data\27.02.2025_maur_forprosjekt_biologisk_mangfold\data\species"

# Temp folder name for GPT Researcher local docs (created in script directory)
TEMP_DOCS_FOLDER = "my-docs"

# File extensions to include in hybrid research
DOCUMENT_EXTENSIONS = {".pdf", ".txt", ".docx", ".doc"}
```

**Step 2: Verify syntax**

Run: `python -m py_compile python/populate_bioprio_justifications_hybrid.py`
Expected: No output (success)

**Step 3: Commit**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: add hybrid configuration constants"
```

---

## Task 3: Add Local Document Handling Functions

**Files:**
- Modify: `python/populate_bioprio_justifications_hybrid.py`

**Step 1: Add document handling functions after the `clean_markdown_formatting()` function**

Insert after line ~512 (after `clean_markdown_formatting` function ends):

```python
# =============================================================================
# LOCAL DOCUMENT FUNCTIONS
# =============================================================================

def find_species_docs_folder(gbif_key: str, scientific_name: str) -> Optional[Path]:
    """Find the species folder matching {GBIF_KEY}_{Scientific_Name} pattern.

    Args:
        gbif_key: GBIF taxon key (e.g., "11700741")
        scientific_name: Species name (e.g., "Lasius aphidicola")

    Returns:
        Path to folder if found, None otherwise.
    """
    if not gbif_key or not scientific_name:
        return None

    base_path = Path(SPECIES_DOCS_BASE_PATH)
    if not base_path.exists():
        print(f"  ⚠️  Species docs base path not found: {SPECIES_DOCS_BASE_PATH}")
        return None

    # Build expected folder name: {gbif_key}_{scientific_name_with_underscores}
    safe_name = scientific_name.replace(" ", "_")
    expected_folder = f"{gbif_key}_{safe_name}"

    # Try exact match first
    exact_path = base_path / expected_folder
    if exact_path.exists():
        return exact_path

    # Try case-insensitive search
    for folder in base_path.iterdir():
        if folder.is_dir() and folder.name.lower() == expected_folder.lower():
            return folder

    # Try partial match (folder starts with GBIF key)
    for folder in base_path.iterdir():
        if folder.is_dir() and folder.name.startswith(f"{gbif_key}_"):
            return folder

    return None


def copy_species_docs_to_temp(gbif_key: str, scientific_name: str) -> bool:
    """Copy all documents from species folder to temp my-docs folder.

    GPT Researcher's hybrid mode reads from a "my-docs" folder in the script directory.

    Args:
        gbif_key: GBIF taxon key
        scientific_name: Species scientific name

    Returns:
        True if docs were copied (use hybrid mode), False otherwise (use web-only).
    """
    # Get script directory for temp folder location
    script_dir = Path(__file__).parent
    temp_path = script_dir / TEMP_DOCS_FOLDER

    # Clear existing temp folder
    if temp_path.exists():
        shutil.rmtree(temp_path)
    temp_path.mkdir(parents=True, exist_ok=True)

    # Find species folder
    species_path = find_species_docs_folder(gbif_key, scientific_name)
    if not species_path:
        print(f"  ⚠️  No local documents folder found for {gbif_key}_{scientific_name}")
        return False

    print(f"  📂 Found species docs: {species_path.name}")

    # Recursively find all matching documents
    docs_copied = 0
    for ext in DOCUMENT_EXTENSIONS:
        for doc_file in species_path.rglob(f"*{ext}"):
            if doc_file.is_file():
                # Copy to flat structure with unique names (avoid collisions)
                dest_name = f"{docs_copied:04d}_{doc_file.name}"
                dest_path = temp_path / dest_name
                try:
                    shutil.copy2(doc_file, dest_path)
                    docs_copied += 1
                except Exception as e:
                    print(f"  ⚠️  Failed to copy {doc_file.name}: {e}")

    if docs_copied > 0:
        print(f"  📚 Copied {docs_copied} documents to temp folder for hybrid research")
        return True
    else:
        print(f"  ⚠️  No documents found in {species_path}")
        return False


def cleanup_temp_docs():
    """Remove temp my-docs folder."""
    script_dir = Path(__file__).parent
    temp_path = script_dir / TEMP_DOCS_FOLDER
    if temp_path.exists():
        try:
            shutil.rmtree(temp_path)
            print("🧹 Cleaned up temp documents folder")
        except Exception as e:
            print(f"⚠️  Failed to cleanup temp folder: {e}")
```

**Step 2: Verify syntax**

Run: `python -m py_compile python/populate_bioprio_justifications_hybrid.py`
Expected: No output (success)

**Step 3: Commit**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: add local document handling functions for hybrid mode"
```

---

## Task 4: Modify get_assessment_info to Return GBIF Key

**Files:**
- Modify: `python/populate_bioprio_justifications_hybrid.py`

**Step 1: Update the SQL query to include gbifTaxonKey**

Find the `get_assessment_info` function and update the SQL query from:

```python
    cursor.execute("""
        SELECT a.idAssessment, a.idPest, p.scientificName, p.eppoCode
        FROM assessments a
        JOIN pests p ON a.idPest = p.idPest
        WHERE a.idAssessment = ?
    """, (assessment_id,))
```

To:

```python
    cursor.execute("""
        SELECT a.idAssessment, a.idPest, p.scientificName, p.eppoCode, p.gbifTaxonKey
        FROM assessments a
        JOIN pests p ON a.idPest = p.idPest
        WHERE a.idAssessment = ?
    """, (assessment_id,))
```

**Step 2: Update the result unpacking**

Change from:

```python
    assessment_id, pest_id, species_name, eppo_code = result
```

To:

```python
    assessment_id, pest_id, species_name, eppo_code, gbif_key = result
```

**Step 3: Update the return dictionary**

Change from:

```python
    return {
        'idAssessment': assessment_id,
        'idPest': pest_id,
        'scientificName': species_name,
        'eppoCode': eppo_code,
        'answers': answers
    }
```

To:

```python
    return {
        'idAssessment': assessment_id,
        'idPest': pest_id,
        'scientificName': species_name,
        'eppoCode': eppo_code,
        'gbifTaxonKey': gbif_key or "",
        'answers': answers
    }
```

**Step 4: Verify syntax**

Run: `python -m py_compile python/populate_bioprio_justifications_hybrid.py`
Expected: No output (success)

**Step 5: Commit**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: include GBIF taxon key in assessment info"
```

---

## Task 5: Modify research_justification for Hybrid Mode

**Files:**
- Modify: `python/populate_bioprio_justifications_hybrid.py`

**Step 1: Add use_hybrid parameter to function signature**

Find the `research_justification` function and change from:

```python
async def research_justification(species_name: str, question_code: str, question_text: str,
                                 question_info: str = "", pathway_name: str = None,
                                 exclude_domains: List[str] = None,
                                 track_metrics: bool = True) -> Tuple[str, Optional[QuestionMetrics]]:
```

To:

```python
async def research_justification(species_name: str, question_code: str, question_text: str,
                                 question_info: str = "", pathway_name: str = None,
                                 exclude_domains: List[str] = None,
                                 track_metrics: bool = True,
                                 use_hybrid: bool = False) -> Tuple[str, Optional[QuestionMetrics]]:
```

**Step 2: Add research mode logging**

After the existing domain exclusion print statement, add:

```python
    print(f"🔬 Research mode: {'hybrid (web + local docs)' if use_hybrid else 'web-only'}")
```

**Step 3: Update GPTResearcher initialization**

Change from:

```python
    researcher = GPTResearcher(
        query=query,
        report_type="research_report",
        tone="formal",
        report_source="web",
    )
```

To:

```python
    report_source = "hybrid" if use_hybrid else "web"

    researcher = GPTResearcher(
        query=query,
        report_type="research_report",
        tone="formal",
        report_source=report_source,
    )
```

**Step 4: Verify syntax**

Run: `python -m py_compile python/populate_bioprio_justifications_hybrid.py`
Expected: No output (success)

**Step 5: Commit**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: add hybrid mode support to research_justification"
```

---

## Task 6: Modify process_assessment to Set Up Hybrid Mode

**Files:**
- Modify: `python/populate_bioprio_justifications_hybrid.py`

**Step 1: Extract GBIF key and set up hybrid mode after loading assessment**

In the `process_assessment` function, after these lines:

```python
    species_name = assessment_info['scientificName']
    eppo_code = assessment_info['eppoCode']
    answers = assessment_info['answers']
    assessment_id = assessment_info['idAssessment']
```

Add:

```python
    gbif_key = assessment_info.get('gbifTaxonKey', '')

    # Set up local documents for hybrid research
    use_hybrid = copy_species_docs_to_temp(gbif_key, species_name)
```

**Step 2: Pass use_hybrid to research_justification calls**

Find all calls to `research_justification` in `process_assessment` and add `use_hybrid=use_hybrid` parameter.

First call (for regular questions):

```python
            ai_text, metrics = await research_justification(
                species_name=species_name,
                question_code=answer['code'],
                question_text=answer['text'],
                question_info=answer['info'],
                exclude_domains=exclude_domains or [],
                track_metrics=track_costs,
                use_hybrid=use_hybrid
            )
```

Second call (for pathway questions):

```python
                        ai_text, metrics = await research_justification(
                            species_name=species_name,
                            question_code=pq['code'],
                            question_text=pq['text'],
                            question_info=pq['info'],
                            pathway_name=pathway_name,
                            exclude_domains=exclude_domains or [],
                            track_metrics=track_costs,
                            use_hybrid=use_hybrid
                        )
```

**Step 3: Verify syntax**

Run: `python -m py_compile python/populate_bioprio_justifications_hybrid.py`
Expected: No output (success)

**Step 4: Commit**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: set up hybrid mode in process_assessment"
```

---

## Task 7: Add Cleanup in main() Function

**Files:**
- Modify: `python/populate_bioprio_justifications_hybrid.py`

**Step 1: Wrap the processing loop in try/finally**

In the `main()` function, find the section that processes assessments:

```python
    # Process each assessment
    for idx, aid in enumerate(assessment_ids, 1):
        ...
```

Wrap it in a try/finally block to ensure cleanup:

```python
    # Process each assessment
    try:
        for idx, aid in enumerate(assessment_ids, 1):
            if len(assessment_ids) > 1:
                print("\n" + "=" * 80)
                print(f"ASSESSMENT {idx}/{len(assessment_ids)} (ID: {aid})")
                print("=" * 80)

            await process_assessment(
                db_path=working_db,
                assessment_id=aid,
                exclude_domains=exclude_domains,
                limit_questions=limit_questions,
                process_pathways=process_pathways,
                skip_existing=skip_existing,
                track_costs=track_costs,
                add_all_pathways=add_all_pathways,
                question_filter=effective_question_filter
            )
    finally:
        # Clean up temp documents folder
        cleanup_temp_docs()
```

**Step 2: Verify syntax**

Run: `python -m py_compile python/populate_bioprio_justifications_hybrid.py`
Expected: No output (success)

**Step 3: Commit**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: add cleanup in finally block for temp documents"
```

---

## Task 8: Update Print Statements for Hybrid Branding

**Files:**
- Modify: `python/populate_bioprio_justifications_hybrid.py`

**Step 1: Update the main banner**

Find:

```python
    print("BioPRIO JUSTIFICATION POPULATOR")
```

Change to:

```python
    print("BioPRIO JUSTIFICATION POPULATOR (HYBRID)")
```

**Step 2: Add hybrid mode info to startup output**

After the cost tracking print statement:

```python
    print(f"📊 Cost tracking: {'Enabled' if track_costs else 'Disabled'}")
```

Add:

```python
    print(f"🔬 Research mode: HYBRID (web + local documents)")
    print(f"📂 Species docs path: {SPECIES_DOCS_BASE_PATH}")
```

**Step 3: Verify syntax**

Run: `python -m py_compile python/populate_bioprio_justifications_hybrid.py`
Expected: No output (success)

**Step 4: Commit**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: update branding for hybrid version"
```

---

## Task 9: Final Verification

**Step 1: Run syntax check**

```bash
python -m py_compile python/populate_bioprio_justifications_hybrid.py
```

Expected: No output (success)

**Step 2: Check imports work**

```bash
cd python
python -c "from populate_bioprio_justifications_hybrid import find_species_docs_folder, copy_species_docs_to_temp, cleanup_temp_docs; print('Imports OK')"
```

Expected: `Imports OK`

**Step 3: Test folder detection (dry run)**

```bash
python -c "
from pathlib import Path
from populate_bioprio_justifications_hybrid import find_species_docs_folder, SPECIES_DOCS_BASE_PATH
print(f'Base path exists: {Path(SPECIES_DOCS_BASE_PATH).exists()}')
result = find_species_docs_folder('11700741', 'Lasius aphidicola')
print(f'Test folder found: {result}')
"
```

Expected: Shows whether the test folder is found

**Step 4: Final commit with all changes**

```bash
git add python/populate_bioprio_justifications_hybrid.py
git commit -m "feat: complete BioPRIO hybrid justification populator

Adds hybrid research mode that combines web search with local PDF documents.
Features:
- Loads docs from Species/{GBIF_KEY}_{Scientific_Name}/ folders
- Falls back to web-only if no local docs found
- Retains full cost tracking with Excel export
- All existing features preserved"
```

---

## Summary

The implementation creates `populate_bioprio_justifications_hybrid.py` with:

1. **New configuration**: `SPECIES_DOCS_BASE_PATH`, `TEMP_DOCS_FOLDER`, `DOCUMENT_EXTENSIONS`
2. **New functions**: `find_species_docs_folder()`, `copy_species_docs_to_temp()`, `cleanup_temp_docs()`
3. **Modified functions**:
   - `get_assessment_info()` - returns GBIF key
   - `research_justification()` - accepts `use_hybrid` parameter
   - `process_assessment()` - sets up hybrid mode per species
   - `main()` - cleanup in finally block

Usage remains identical to the web-only version:
```bash
python populate_bioprio_justifications_hybrid.py --species "Lasius aphidicola"
```

# Design: DAG Enforcement Port — BioPRIO

**Date:** 2026-06-08  
**Status:** Approved  
**Scope:** Port DAG (Directed Acyclic Graph) question-dependency enforcement layer from FinnPRIO to BioPRIO, enabling topologically-ordered processing, zero-forcing, sibling clamping, and scored prior-context injection in both the justifications and values AI pipelines.

---

## Background

FinnPRIO's AI pipeline (populate_finnprio_values.py, populate_finnprio_justifications.py) has a full DAG enforcement layer that:
- Processes questions in topological dependency order (upstream before downstream)
- Zero-forces downstream answers when upstream answer is 'a' (zero points)
- Clamps ENT2B ≤ ENT2A (management can only reduce, never increase entry probability)
- Injects already-scored/researched upstream answers as prior context into each GPT call

BioPRIO's equivalent scripts exist but are missing this entire layer. This port brings BioPRIO to parity.

---

## Files

### New files (created in `python/`, NOT in `gpt_researcher_scripts/`)

| File | Purpose |
|------|---------|
| `python/dag_config.py` | Question dependency structures (verbatim port from FinnPRIO) |
| `python/dag_values.py` | DAG enforcement functions (verbatim port, "finnprio" → "bioprio" in messages) |

### Modified files

| File | Change count |
|------|-------------|
| `python/gpt_researcher_scripts/populate_bioprio_values.py` | 8 targeted changes |
| `python/gpt_researcher_scripts/populate_bioprio_justifications.py` | 6 targeted changes |

---

## Import Path Strategy

Both modified scripts live in `gpt_researcher_scripts/`. The new dag modules live in the parent `python/` directory. Both scripts require:

```python
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from dag_config import ...
from dag_values import ...
```

`bioprio_instructions_loader` is in the same directory and needs no path adjustment.

---

## Part A: python/dag_config.py

Verbatim port of FinnPRIO's `dag_config.py`. Contains:
- `QUESTION_DEPENDENCIES` — main question dependency graph (which questions must be answered before others)
- `PATHWAY_DEPENDENCIES` — dependency graph for pathway questions (ENT2A → ENT3)
- `SIBLING_CONSTRAINTS` — ENT2B must be ≤ ENT2A

No EPPO-specific content exists in this file. Port is clean.

---

## Part B: python/dag_values.py

Verbatim port of FinnPRIO's `dag_values.py` with one change: any `"finnprio"` string in output messages → `"bioprio"`.

Functions ported:
- `topological_sort_answers()` — Kahn's algorithm over dependency graph
- `check_zero_forcing()` — when upstream answer is 'a', force downstream to zero
- `check_sibling_clamp()` — enforce ENT2B ≤ ENT2A
- `build_scored_prior_context()` — format already-scored answers as context string
- `append_dag_correction()` — write correction records to JSONL audit log

---

## Part C: populate_bioprio_values.py — 8 changes

### Change 1: sys.path + DAG imports
After the existing imports block:
```python
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from dag_values import (
    topological_sort_answers, check_zero_forcing, check_sibling_clamp,
    build_scored_prior_context, append_dag_correction,
)
```

### Change 2: Import get_question_instructions
Add alongside existing `bioprio_instructions_loader` import:
```python
from bioprio_instructions_loader import build_value_selection_prompt, get_question_instructions
```
`get_question_instructions` is confirmed at line 81 of `bioprio_instructions_loader.py`.

### Change 3: Fix default model
In `_call_gpt_for_values()`:
```python
# Before:
model=os.getenv("LLM_MODEL", "gpt-4o-mini")
# After:
model=os.getenv("LLM_MODEL", "gpt-4o")
```

### Change 4: Add _call_gpt_boolean() method
Port from FinnPRIO's `ValuePopulator._call_gpt_boolean()` with:
- System prompt: "invasive species/arthropod risk assessment" (not "plant pest")
- Return type: `Tuple[Optional[Dict], int, int]` (not `Optional[Dict]`) — read token counts from `response.usage.prompt_tokens` / `response.usage.completion_tokens`

### Change 5: Add prior_context parameter to determine_values_with_gpt()
New signature:
```python
async def determine_values_with_gpt(self, species_name, question_text,
    options, justification, question_type="minmax", question_code=None,
    prior_context: str = "")
```
- Add boolean routing before existing prompt logic:
  ```python
  if question_type == 'boolean' and options:
      yes_code = options[0]['opt']
      return await self._call_gpt_boolean(justification, question_code, yes_code)
  ```
- Prepend `prior_context` to prompt string if non-empty before calling `_call_gpt_for_values()`

### Change 6: Add load_scored_context() method
Port verbatim from FinnPRIO. Reads all existing min/likely/max values for an assessment from the `answers` table. Returns `dict` keyed by question code.

### Change 7: Add load_scored_context_pathway() method
Port verbatim from FinnPRIO. Reads existing values for one `idEntryPathway` from `pathwayAnswers`. Returns `dict` keyed by question code.

### Change 8: Replace processing loops in populate_values_for_assessment()
Replace existing arbitrarily-ordered loops (current lines ~620–708) with DAG-enforced versions from FinnPRIO lines 552–824.

**Regular answers loop:**
1. Enrich each answer dict with its `code` field (from question lookup)
2. `sorted_answers = topological_sort_answers(answers, is_pathway=False)`
3. `scored_context = await self.load_scored_context(assessment_id)`
4. For each answer:
   - `check_zero_forcing(answer, scored_context)` → may short-circuit to zero
   - `prior_ctx = build_scored_prior_context(answer['code'], scored_context)`
   - `result, in_tok, out_tok = await self.determine_values_with_gpt(..., prior_context=prior_ctx)`
   - `check_sibling_clamp(answer, result, scored_context)`
   - Write to DB
   - `scored_context[answer['code']] = result`
   - `append_dag_correction(...)` if correction was applied

**Pathway answers loop:**
1. Group by `idEntryPathway`
2. For each group: `topological_sort_answers(group, is_pathway=True)`
3. Fresh `scored_context = await self.load_scored_context_pathway(idEntryPathway)`
4. Same DAG loop per answer

**BioPRIO-specific logic preserved (not in FinnPRIO):**
- `track_costs` parameter and `cost_tracker.record_question()` calls — keep at same call sites
- `question_filter` support — filter answers before the loop runs
- **Intentional introduction pathway auto-max logic** (lines 665–683) — inside the pathway DAG loop, before the GPT call for each answer: if this is an Intentional introduction pathway and the question is ENT2A/ENT2B/ENT3, write the max value to DB, update `scored_context[code] = max_result`, then `continue` to skip the rest of the DAG logic for that answer. Updating scored_context is required so that ENT3 (which depends on ENT2A) gets correct prior context.

**Token count adaptation:** FinnPRIO's `determine_values_with_gpt()` returns `Optional[Dict]`. BioPRIO's returns `Tuple[Optional[Dict], int, int]`. Unpack the tuple at all call sites; pass `in_tok`/`out_tok` to cost tracker as BioPRIO already does.

---

## Part D: populate_bioprio_justifications.py — 6 changes

### Change 1: LLM model config
In the `os.environ.update({})` block:
```python
"FAST_LLM":         "openai:gpt-4.1-mini",   # was: gpt-4o-mini
"SMART_LLM":        "openai:gpt-4.1",          # already correct
"STRATEGIC_LLM":    "openai:o3",               # was: o4-mini
"REASONING_EFFORT": "medium",
"RETRIEVER":        "tavily,semantic_scholar,pubmed_central",  # no eppo_gd
```
All other env vars (TEMPERATURE, SIMILARITY_THRESHOLD, etc.) remain unchanged.

### Change 2: Versioned database naming
Replace current `copy_database()` (date-based, collision-prone: `_ai_enhanced_DD_MM_YYYY`) with FinnPRIO's version-incrementing variant that produces filenames like:
```
ants_v003_2026-05-16T10-04-27.db
```
Auto-increments version number by scanning existing `_v\d+_` files in the same directory.

### Change 3a: sys.path + DAG config imports
```python
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
from dag_config import QUESTION_DEPENDENCIES, PATHWAY_DEPENDENCIES
```

### Change 3b: Port topological_sort_questions()
Port the local `topological_sort_questions(answers, dependencies)` function from FinnPRIO's justifications script. (This is distinct from `topological_sort_answers()` in dag_values.py — it operates on question code lists rather than answer dicts.)

### Change 3c: Port build_prior_context()
Port `build_prior_context(db_path, assessment_id, question_code)` from FinnPRIO. Reads already-written justifications from DB for the upstream dependencies of `question_code` (per QUESTION_DEPENDENCIES / PATHWAY_DEPENDENCIES). Returns a formatted string to prepend to the research query.

### Change 3d: DAG context injection in process_assessment()
In `process_assessment()`:
1. After loading answers: `sorted_answers = topological_sort_questions(answers, QUESTION_DEPENDENCIES)`
2. Replace existing loop with sorted version
3. For each question: `prior_ctx = build_prior_context(db_path, assessment_id, question_code)`
4. Pass `prior_ctx` into `create_research_query()` and/or `research_justification()`
5. Add `prior_context` parameter to `create_research_query()` and `research_justification()` signatures

**Not ported from FinnPRIO:** NIBIO MCP context, SSB MCP context, EPPO retriever registration. These are plant-pest / Norway-statistics specific.

### Change 5: Species filter
Already done — BioPRIO's `get_all_assessment_ids()` already uses GBIF-aware query. No change.

---

## Validation Checklist

After all changes:
1. `grep -r "eppo_gd"` in both modified scripts → must return zero matches
2. `grep -r "plant pest"` in both modified scripts → must return zero matches
3. `sys.path.insert` appears before dag imports in both scripts
4. `_call_gpt_boolean()` returns a 3-tuple `(dict_or_none, int, int)`
5. Intentional introduction auto-max logic is preserved in values loop
6. Cost tracker calls are preserved in values loop
7. `copy_database()` produces `_vNNN_` versioned filenames

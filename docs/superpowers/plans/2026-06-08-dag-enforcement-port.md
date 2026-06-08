# DAG Enforcement Port — BioPRIO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port FinnPRIO's DAG question-dependency enforcement layer to BioPRIO so both the values and justifications AI pipelines process questions in topological order, zero-force downstream answers, clamp siblings, and inject prior-context into each GPT call.

**Architecture:** Two new utility modules (`python/dag_config.py`, `python/dag_values.py`) are created in the `python/` root — not inside `gpt_researcher_scripts/` — and imported with a `sys.path.insert` shim. Eight targeted edits to `populate_bioprio_values.py` layer in the enforcement, preserving BioPRIO-specific cost tracking and intentional-pathway auto-max. Six targeted edits to `populate_bioprio_justifications.py` add topological sort, DAG context building, versioned DB naming, and updated LLM models.

**Tech Stack:** Python 3.11, asyncio, openai, sqlite3, gpt_researcher, collections.deque (Kahn's algorithm).

**Design spec:** `docs/superpowers/specs/2026-06-08-dag-enforcement-port-design.md`

---

## Task 1: Create python/dag_config.py (Part A)

**Files:**
- Create: `python/dag_config.py`

- [ ] **Step 1: Create the file**

  Create `C:\Users\dafl\OneDrive - Folkehelseinstituttet\FinnPrio\BioPRIO_development\python\dag_config.py` with the following content (verbatim port; only the module docstring and one comment are updated for BioPRIO):

```python
"""
BioPRIO DAG configuration — question dependencies and sibling constraints.

This module encodes the logical dependency structure of the BioPRIO assessment
framework as machine-readable rules.  All entries are sourced directly from the
question guidance text in:

    Instructions_BioPrio_assessments.rmd

Do NOT modify these dicts without consulting the Rmd first.  The Rmd is the
authoritative source; these dicts are derived, not invented.
"""

# All question codes are dot-free canonical form: "EST2", "IMP2.1", "ENT2A".

# Regular question dependencies: {question_code: [list_of_dependency_codes]}
# Empty list means no dependencies — process in any order.
QUESTION_DEPENDENCIES = {
    "ENT1":   [],
    "EST1":   [],              # No Rmd-cited dependency; EST1 depends on pest biology vs
                               # Norwegian climate, not global range (ENT1 removed 2026-05-29).
    "EST2":   ["EST1"],
    "EST3":   ["EST1", "EST2"],
    "EST4":   [],
    "IMP1":   ["EST1", "EST2"],
    "IMP2.1": ["EST1", "EST2"],
    "IMP2.2": [],              # biological fact (vector status) — independent
    "IMP2.3": ["EST1", "EST2"],
    "IMP3":   ["EST1", "EST2"],
    "IMP4.1": ["EST1", "EST2"],
    "IMP4.2": ["EST1", "EST2"],
    "IMP4.3": ["EST1", "EST2"],
    "MAN1":   ["ENT1"],        # ENT1 is weak ordering context: global range gives approximate
                               # distance from Norway. The stronger prior — natural spread
                               # pathway assessment (ENT2A) — would require cross-table dep
                               # wiring not currently supported. Flag if interface is extended.
    "MAN2":   [],
    "MAN3":   [],
    "MAN4":   [],              # Possible EST1 dep (outdoor spread context) but not explicit
                               # in Rmd. Flagged 2026-05-29 — do not add without Rmd citation.
    "MAN5":   ["EST3", "EST2"], # EST3 = spread rate (Rmd: "Pest's natural potential to spread");
                               # EST2 = host distribution (Rmd: "Abundance and distribution of
                               # host plants"). Both explicitly listed in MAN5 guidance.
}

# Pathway question dependencies: {pathway_question_code: [list_of_dependency_codes]}
# Deps may be regular question codes (e.g. "ENT1") or same-pathway codes (e.g. "ENT2A").
# Cross-pathway dependencies do not exist — these are always re-instantiated per pathway.
PATHWAY_DEPENDENCIES = {
    "ENT2A": ["ENT1"],
    "ENT2B": ["ENT2A"],
    "ENT3":  [],
    "ENT4":  ["ENT2A"],        # ENT2A retained (same-pathway transport context).
                               # ENT3 removed 2026-05-29 — Rmd ENT4 guidance references
                               # season and destination/use, not trade volume. Same logic
                               # applies here as in QUESTION_DEPENDENCIES["ENT4"].
}

# Sibling constraints: qualitative rules enforced via prompt injection.
# These apply where two questions describe the same thing under different conditions
# and their conclusions must be logically consistent.
# Numeric enforcement (score comparison) belongs in populate_bioprio_values.py.
SIBLING_CONSTRAINTS = {
    "ENT2B": {
        "sibling": "ENT2A",
        "rule": (
            "ENT2B describes the same pathway WITH phytosanitary management. "
            "Your conclusion must be less favourable or equal to ENT2A — "
            "management can only reduce or maintain entry probability, never increase it."
        ),
    },
}
```

- [ ] **Step 2: Verify the file exists**

  Run:
  ```
  python -c "import sys; sys.path.insert(0, '.'); from dag_config import QUESTION_DEPENDENCIES, PATHWAY_DEPENDENCIES, SIBLING_CONSTRAINTS; print('OK', len(QUESTION_DEPENDENCIES), 'regular deps')"
  ```
  Run from `python/` directory.
  Expected: `OK 17 regular deps`

- [ ] **Step 3: Commit**

  ```
  git add python/dag_config.py
  git commit -m "feat(dag): add BioPRIO DAG config (Part A)"
  ```

---

## Task 2: Create python/dag_values.py (Part B)

**Files:**
- Create: `python/dag_values.py`

- [ ] **Step 1: Create the file**

  Create `python/dag_values.py` with this content (verbatim from FinnPRIO; module docstring updated for BioPRIO):

```python
"""
DAG enforcement layer for populate_bioprio_values.py.

Stateless functions only — no database connection, no global state.
The caller owns all mutable state: scored_context, scored_context_pathway,
options_map.

Reuses QUESTION_DEPENDENCIES, PATHWAY_DEPENDENCIES, SIBLING_CONSTRAINTS
from dag_config.py. Adds values-side enforcement: zero-forcing, topological
sort, sibling clamp, scored-value context builder, JSONL audit writer.
"""

import json
from collections import deque
from typing import Dict, List, Optional

from dag_config import QUESTION_DEPENDENCIES, PATHWAY_DEPENDENCIES, SIBLING_CONSTRAINTS


# ─── Enforcement constants ────────────────────────────────────────────────────

ZERO_FORCING_RULES: Dict[str, Dict] = {
    "EST1": {
        "zero_option": "a",
        "targets": [
            # IMP2.2 (vector status) excluded: it is a biological fact about the pest,
            # independent of establishment conditions in Norway (dag_config.py: "IMP2.2": []).
            "IMP1", "IMP2.1", "IMP2.3", "IMP3",
            "IMP4.1", "IMP4.2", "IMP4.3",
        ],
        "reason": (
            "EST1='a' (climate unsuitable): establishment score is zero by definition "
            "(Heikkila et al. 2016, p. 1832); direct impacts in Norway must be zero."
        ),
    },
    "EST2": {
        "zero_option": "a",
        "targets": [
            # IMP2.2 (vector status) excluded: it is a biological fact about the pest,
            # independent of establishment conditions in Norway (dag_config.py: "IMP2.2": []).
            "IMP1", "IMP2.1", "IMP2.3", "IMP3",
            "IMP4.1", "IMP4.2", "IMP4.3",
        ],
        "reason": (
            "EST2='a' (no host plants in Norway): establishment score is zero by definition "
            "(Heikkila et al. 2016, p. 1832); direct impacts in Norway must be zero."
        ),
    },
}

PATHWAY_ZERO_FORCING_RULES: Dict[str, Dict] = {
    "ENT2A": {
        "zero_option": "a",
        "targets": ["ENT3"],
        "reason": (
            "ENT2A='a' (pest cannot be transported via this pathway): ENT3 (trade volume) "
            "contributes zero regardless of volume (Heikkila et al. 2016, Table 2, p. 1830)."
        ),
    },
}

PATHWAY_VALUES_DEPENDENCIES: Dict[str, List[str]] = dict(PATHWAY_DEPENDENCIES)
PATHWAY_VALUES_DEPENDENCIES["ENT3"] = ["ENT2A"]
# Ordering-only. ENT2A must be scored before ENT3 so Tier 1 zero-forcing
# can read scored_context_pathway["ENT2A"]. Table 2 non-zero rows are
# applied at simulation time in simulations.R — ENT2A is NOT injected
# into the ENT3 GPT prompt. Do not add ENT2A to ENT3's context block.


# ─── Functions ───────────────────────────────────────────────────────────────

def _normalize(code: str) -> str:
    """Canonical question code: uppercase, no trailing dot."""
    return code.upper().rstrip('.')


def get_zero_option(options: List[Dict], question_type: str = "minmax") -> Optional[str]:
    """Return the opt code whose points == 0, or None for boolean questions.

    Uses float() cast to guard against DB-returned strings and non-integer
    values (EST1: 0/1.5/4.5/9; ENT2: 0/0.5/1/2/3).
    Raises ValueError if no zero-points option exists (degenerate — not in schema).
    """
    if question_type == "boolean":
        return None
    zero_opts = [o for o in options if float(o["points"]) == 0.0]
    if not zero_opts:
        raise ValueError(
            f"No zero-points option found. Options: {[o['opt'] for o in options]}"
        )
    return zero_opts[0]["opt"]


def topological_sort_answers(
    answers: List[Dict], is_pathway: bool = False
) -> List[Dict]:
    """Sort answers in dependency order using Kahn's algorithm.

    Uses PATHWAY_VALUES_DEPENDENCIES when is_pathway=True (which adds the
    ordering-only ENT2A→ENT3 edge), QUESTION_DEPENDENCIES otherwise.
    Questions not in the dependency map are treated as having no deps.
    """
    deps = PATHWAY_VALUES_DEPENDENCIES if is_pathway else QUESTION_DEPENDENCIES
    code_to_q = {_normalize(q["code"]): q for q in answers}
    codes = sorted(code_to_q.keys())

    in_degree: Dict[str, int] = {c: 0 for c in codes}
    adj: Dict[str, List[str]] = {c: [] for c in codes}

    for code in codes:
        for dep in deps.get(code, []):
            if dep in code_to_q:
                in_degree[code] += 1
                adj[dep].append(code)

    queue = deque(sorted(c for c in codes if in_degree[c] == 0))
    result: List[Dict] = []

    while queue:
        node = queue.popleft()
        result.append(code_to_q[node])
        for dependent in sorted(adj[node]):
            in_degree[dependent] -= 1
            if in_degree[dependent] == 0:
                queue.append(dependent)

    # Append any remaining (cycle guard — not expected in this schema)
    processed = {_normalize(q["code"]) for q in result}
    result.extend(code_to_q[c] for c in codes if c not in processed)

    return result


def check_zero_forcing(
    question_code: str,
    scored_context: Dict[str, Dict[str, str]],
    options: List[Dict],
    question_type: str = "minmax",
    is_pathway: bool = False,
) -> Optional[Dict]:
    """Tier 1 zero-force check.

    Returns a result dict when at least one parameter must be forced to the
    zero option, or None if no rule fires.

    result = {
        "min":    opt_or_None,   # forced value; None = this param not forced
        "likely": opt_or_None,
        "max":    opt_or_None,
        "flags": [{
            "parameter":       str,
            "rule_fired":      str,
            "original_option": None,   # filled by caller after GPT if GPT ran
            "forced_option":   str | None,
        }]
    }

    forced_option is None for boolean questions (the NO convention).
    """
    rules = PATHWAY_ZERO_FORCING_RULES if is_pathway else ZERO_FORCING_RULES
    code = _normalize(question_code)
    try:
        zero_opt = get_zero_option(options, question_type)
    except ValueError:
        # No zero-points option in the DB schema for this question (e.g. ENT3,
        # whose points are computed via Table 2 at simulation time).
        # Treat as None — forced parameters will be left unscored, which is
        # correct: if the upstream rule fires the question's contribution is
        # already zero by the model formula.
        zero_opt = None

    result: Dict = {"min": None, "likely": None, "max": None, "flags": []}
    any_forced = False

    for upstream_code, rule in rules.items():
        if code not in rule["targets"]:
            continue
        upstream = scored_context.get(upstream_code)
        if not upstream:
            continue
        for param in ("min", "likely", "max"):
            if upstream.get(param) == rule["zero_option"]:
                result[param] = zero_opt
                any_forced = True
                result["flags"].append({
                    "parameter": param,
                    "rule_fired": f"{upstream_code}={rule['zero_option']}→{code}=zero",
                    "original_option": None,
                    "forced_option": zero_opt,
                    "reason": rule["reason"],
                })

    return result if any_forced else None


def check_sibling_clamp(
    question_code: str,
    values: Dict[str, Optional[str]],
    scored_context: Dict[str, Dict[str, str]],
    options_map: Dict[str, List[Dict]],
) -> Optional[Dict]:
    """Post-GPT sibling clamp (currently ENT2B ≤ ENT2A).

    Compares each parameter's points to the sibling's corresponding parameter.
    Returns a clamped result dict with flags, or None if no clamp is needed.

    result = {
        "min": opt, "likely": opt, "max": opt,
        "flags": [{"parameter", "rule_fired", "original_option", "forced_option"}]
    }
    """
    code = _normalize(question_code)
    if code not in SIBLING_CONSTRAINTS:
        return None

    sc = SIBLING_CONSTRAINTS[code]
    sibling_code = _normalize(sc["sibling"])
    sibling_scored = scored_context.get(sibling_code)
    sibling_opts = options_map.get(sibling_code, [])
    own_opts = options_map.get(code, [])

    if not sibling_scored or not sibling_opts or not own_opts:
        return None

    sibling_pts: Dict[str, float] = {o["opt"]: float(o["points"]) for o in sibling_opts}
    own_pts: Dict[str, float] = {o["opt"]: float(o["points"]) for o in own_opts}

    result: Dict = {
        "min": values.get("min"),
        "likely": values.get("likely"),
        "max": values.get("max"),
        "flags": [],
    }
    any_clamped = False

    for param in ("min", "likely", "max"):
        own_val = values.get(param)
        sib_val = sibling_scored.get(param)
        if own_val is None or sib_val is None:
            continue
        if own_pts.get(own_val, 0.0) > sibling_pts.get(sib_val, 0.0):
            result[param] = sib_val
            any_clamped = True
            result["flags"].append({
                "parameter": param,
                "rule_fired": f"{code}>{sibling_code} clamp",
                "original_option": own_val,
                "forced_option": sib_val,
            })

    return result if any_clamped else None


def build_scored_prior_context(
    question_code: str,
    scored_context: Dict[str, Dict[str, str]],
    options_map: Dict[str, List[Dict]],
) -> str:
    """Build a scored-value context string for Tier 2 GPT prompt injection.

    Shows upstream scored option codes and their text descriptions.
    Returns empty string if no dependencies have been scored yet.
    """
    code = _normalize(question_code)
    is_pathway = code in PATHWAY_VALUES_DEPENDENCIES and code not in QUESTION_DEPENDENCIES
    deps = (
        PATHWAY_VALUES_DEPENDENCIES.get(code, [])
        if is_pathway
        else QUESTION_DEPENDENCIES.get(code, [])
    )
    if not deps:
        return ""

    lines = ["PRIOR SCORED VALUES (upstream dependencies):"]
    for dep in deps:
        dep_scored = scored_context.get(dep)
        dep_opts = options_map.get(dep, [])
        if not dep_scored or not dep_opts:
            continue
        opt_text = {o["opt"]: o["text"] for o in dep_opts}
        parts = []
        for param in ("min", "likely", "max"):
            val = dep_scored.get(param)
            if val is not None:
                parts.append(f'{param}="{val}" ({opt_text.get(val, val)})')
        if parts:
            lines.append(f"  {dep}: {', '.join(parts)}")

    if len(lines) == 1:
        return ""

    lines.append("Your scored options must be consistent with these upstream assessments.")
    return "\n".join(lines)


def append_dag_correction(jsonl_path: str, entry: Dict) -> None:
    """Append one JSONL line to the sidecar audit file (append mode, one call per entry)."""
    with open(jsonl_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")
```

- [ ] **Step 2: Smoke-test topological_sort_answers**

  Run from `python/` directory:
  ```python
  python -c "
  import sys; sys.path.insert(0, '.')
  from dag_values import topological_sort_answers
  answers = [
      {'code': 'IMP1', 'x': 1},
      {'code': 'EST1', 'x': 2},
      {'code': 'EST2', 'x': 3},
  ]
  result = topological_sort_answers(answers, is_pathway=False)
  codes = [a['code'] for a in result]
  assert codes.index('EST1') < codes.index('EST2'), 'EST1 must come before EST2'
  assert codes.index('EST2') < codes.index('IMP1'), 'EST2 must come before IMP1'
  print('PASS', codes)
  "
  ```
  Expected: `PASS ['EST1', 'EST2', 'IMP1']`

- [ ] **Step 3: Commit**

  ```
  git add python/dag_values.py
  git commit -m "feat(dag): add BioPRIO DAG values enforcement layer (Part B)"
  ```

---

## Task 3: populate_bioprio_values.py — imports and model fix (C1–C3)

**Files:**
- Modify: `python/gpt_researcher_scripts/populate_bioprio_values.py`

- [ ] **Step 1: Add `import sys` alongside the existing stdlib imports**

  Find:
  ```python
  import sqlite3
  import json
  import os
  import asyncio
  ```

  Replace with:
  ```python
  import sys
  import sqlite3
  import json
  import os
  import asyncio
  ```

- [ ] **Step 2: Add sys.path shim + dag_values imports after the bioprio_instructions_loader import**

  Find:
  ```python
  # Import instructions loader for Rmd-based value selection prompts
  from bioprio_instructions_loader import build_value_selection_prompt
  ```

  Replace with:
  ```python
  # Import instructions loader for Rmd-based value selection prompts
  from bioprio_instructions_loader import build_value_selection_prompt, get_question_instructions

  # DAG enforcement layer (modules live in parent python/ directory)
  sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
  from dag_values import (
      topological_sort_answers,
      check_zero_forcing,
      check_sibling_clamp,
      build_scored_prior_context,
      append_dag_correction,
  )
  ```

- [ ] **Step 3: Fix default model in `_call_gpt_for_values()`**

  Find:
  ```python
                  model=os.getenv("LLM_MODEL", "gpt-4o-mini"),
  ```

  Replace with:
  ```python
                  model=os.getenv("LLM_MODEL", "gpt-4o"),
  ```

- [ ] **Step 4: Verify imports load without error**

  Run from `python/gpt_researcher_scripts/`:
  ```
  python -c "import sys, os; sys.path.insert(0, os.path.dirname(os.getcwd())); from dag_values import topological_sort_answers; print('OK')"
  ```
  Expected: `OK`

- [ ] **Step 5: Commit**

  ```
  git add python/gpt_researcher_scripts/populate_bioprio_values.py
  git commit -m "feat(values): add DAG imports and fix default model (C1-C3)"
  ```

---

## Task 4: populate_bioprio_values.py — add `_call_gpt_boolean()` and update `determine_values_with_gpt()` (C4–C5)

**Files:**
- Modify: `python/gpt_researcher_scripts/populate_bioprio_values.py`

- [ ] **Step 1: Add `_call_gpt_boolean()` before `_call_gpt_for_values()`**

  Find:
  ```python
    async def _call_gpt_for_values(
          self,
          prompt: str,
          options: List[Dict]
      ) -> Tuple[Optional[Dict], int, int]:
  ```

  Replace with:
  ```python
    async def _call_gpt_boolean(
        self, justification: str, question_code: str, yes_code: str
    ) -> Tuple[Optional[Dict], int, int]:
        """Ask a simple yes/no question for boolean sub-questions (IMP2.x, IMP4.x).

        Returns ({min: yes_code, likely: yes_code, max: yes_code}, in_tok, out_tok) for YES,
                ({min: None, likely: None, max: None}, 0, 0) for NO,
                (None, 0, 0) on error.
        """
        try:
            q = get_question_instructions(question_code)
            question_text = f"{q['code']}: {q['text']}"
            guidance = q.get('guidance', [])
        except KeyError:
            question_text = question_code
            guidance = []

        guidance_block = (
            "\nGUIDANCE:\n" + "\n".join(f"- {g}" for g in guidance)
        ) if guidance else ""

        prompt = (
            f"Does the following justification indicate that this applies to the species?\n\n"
            f"QUESTION: {question_text}"
            f"{guidance_block}\n\n"
            f"JUSTIFICATION:\n{justification}\n\n"
            f"Answer YES if the justification supports it, "
            f"NO if it does not occur or is not mentioned.\n"
            f'Return ONLY: {{"answer": "YES"}} or {{"answer": "NO"}}'
        )

        try:
            response = await client.chat.completions.create(
                model=os.getenv("LLM_MODEL", "gpt-4o"),
                messages=[
                    {"role": "system", "content": "You are an expert in invasive species/arthropod risk assessment."},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.0,
                max_tokens=20
            )
            content = response.choices[0].message.content.strip()
            in_tok = response.usage.prompt_tokens if response.usage else 0
            out_tok = response.usage.completion_tokens if response.usage else 0
            if "```" in content:
                content = content.split("```")[1].split("```")[0].strip()
                if content.startswith("json"):
                    content = content[4:].strip()
            import json as _json
            result = _json.loads(content)
            if result.get("answer", "").upper() == "YES":
                return {"min": yes_code, "likely": yes_code, "max": yes_code}, in_tok, out_tok
            return {"min": None, "likely": None, "max": None}, in_tok, out_tok
        except Exception as e:
            print(f"  ⚠️  Error in boolean evaluation: {type(e).__name__}: {e}")
            return None, 0, 0

    async def _call_gpt_for_values(
          self,
          prompt: str,
          options: List[Dict]
      ) -> Tuple[Optional[Dict], int, int]:
  ```

  Note: `json` is already imported globally so `import json as _json` is redundant — use `json.loads` directly. The `import json as _json` above is just for clarity; remove the line and use `json.loads` instead.

  Corrected version of the JSON parse line:
  ```python
            result = json.loads(content)
  ```

- [ ] **Step 2: Update `determine_values_with_gpt()` signature and body**

  Find:
  ```python
    async def determine_values_with_gpt(
          self,
          species_name: str,
          question_text: str,
          options: List[Dict],
          justification: str,
          question_type: str = "minmax",
          question_code: str = None
      ) -> Tuple[Optional[Dict], int, int]:
          """
          Use GPT to determine appropriate min/likely/max values based on justification.

          Uses Rmd-based instructions via build_value_selection_prompt() for comprehensive
          prompts with options, guidance, and scoring criteria.

          Args:
              species_name: Scientific name of the species
              question_text: The question text (unused, kept for compatibility)
              options: List of option dicts with 'opt', 'text', 'points'
              justification: The AI-generated justification to analyze
              question_type: 'minmax' or 'boolean' (unused, derived from question_code)
              question_code: Question code (e.g., 'ENT1', 'EST4') - required for Rmd lookup

          Returns:
              Tuple of (values_dict, input_tokens, output_tokens) or (None, 0, 0) on error
          """
          # Use Rmd-based prompt builder for comprehensive instructions
          prompt = build_value_selection_prompt(question_code, species_name, justification, options)
          return await self._call_gpt_for_values(prompt, options)
  ```

  Replace with:
  ```python
    async def determine_values_with_gpt(
          self,
          species_name: str,
          question_text: str,
          options: List[Dict],
          justification: str,
          question_type: str = "minmax",
          question_code: str = None,
          prior_context: str = "",
      ) -> Tuple[Optional[Dict], int, int]:
          """
          Use GPT to determine appropriate min/likely/max values based on justification.

          Uses Rmd-based instructions via build_value_selection_prompt() for comprehensive
          prompts with options, guidance, and scoring criteria.

          Args:
              species_name: Scientific name of the species
              question_text: The question text (unused, kept for compatibility)
              options: List of option dicts with 'opt', 'text', 'points'
              justification: The AI-generated justification to analyze
              question_type: 'minmax' or 'boolean'
              question_code: Question code (e.g., 'ENT1', 'EST4') - required for Rmd lookup
              prior_context: Scored upstream values to inject into the prompt (may be empty)

          Returns:
              Tuple of (values_dict, input_tokens, output_tokens) or (None, 0, 0) on error
          """
          # Boolean sub-questions (IMP2.x, IMP4.x): route through yes/no path
          if question_type == 'boolean' and options:
              yes_code = options[0]['opt']
              return await self._call_gpt_boolean(justification, question_code, yes_code)

          prompt = build_value_selection_prompt(question_code, species_name, justification, options)
          if prior_context:
              prompt = prior_context + "\n\n" + prompt
          return await self._call_gpt_for_values(prompt, options)
  ```

- [ ] **Step 3: Commit**

  ```
  git add python/gpt_researcher_scripts/populate_bioprio_values.py
  git commit -m "feat(values): add _call_gpt_boolean() and prior_context to determine_values (C4-C5)"
  ```

---

## Task 5: populate_bioprio_values.py — add `load_scored_context()` and `load_scored_context_pathway()` (C6–C7)

**Files:**
- Modify: `python/gpt_researcher_scripts/populate_bioprio_values.py`

- [ ] **Step 1: Add `load_scored_context()` after `get_species_identifier()`**

  Find:
  ```python
    async def determine_values_with_gpt(
          self,
          species_name: str,
          question_text: str,
  ```

  Replace with:
  ```python
    def load_scored_context(self, assessment_id: int) -> Dict[str, Dict[str, str]]:
        """Read all currently-scored min/likely/max values for regular questions.

        Seeds scored_context so upstream values are available even when
        skip_existing=True filters them out of the processing loop.
        """
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT
                q."group" || q.number ||
                CASE WHEN q.subgroup IS NOT NULL THEN '.' || q.subgroup ELSE '' END AS code,
                a.min, a.likely, a.max
            FROM answers a
            JOIN questions q ON a.idQuestion = q.idQuestion
            WHERE a.idAssessment = ?
              AND a.min IS NOT NULL AND a.min != ''
              AND a.likely IS NOT NULL AND a.likely != ''
              AND a.max IS NOT NULL AND a.max != ''
        """, (assessment_id,))
        result: Dict[str, Dict[str, str]] = {}
        for row in cursor.fetchall():
            code = row["code"].upper()
            result[code] = {
                "min": row["min"],
                "likely": row["likely"],
                "max": row["max"],
            }
        return result

    def load_scored_context_pathway(
        self, id_entry_pathway: int
    ) -> Dict[str, Dict[str, str]]:
        """Read all currently-scored min/likely/max values for one pathway instance.

        Seeds scored_context_pathway so upstream pathway values (e.g. ENT2A)
        are available for zero-forcing even when skip_existing=True is set.
        """
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT
                pq."group" || pq.number AS code,
                pa.min, pa.likely, pa.max
            FROM pathwayAnswers pa
            JOIN pathwayQuestions pq ON pa.idPathQuestion = pq.idPathQuestion
            WHERE pa.idEntryPathway = ?
              AND pa.min IS NOT NULL AND pa.min != ''
              AND pa.likely IS NOT NULL AND pa.likely != ''
              AND pa.max IS NOT NULL AND pa.max != ''
        """, (id_entry_pathway,))
        result: Dict[str, Dict[str, str]] = {}
        for row in cursor.fetchall():
            code = row["code"].upper()
            result[code] = {
                "min": row["min"],
                "likely": row["likely"],
                "max": row["max"],
            }
        return result

    async def determine_values_with_gpt(
          self,
          species_name: str,
          question_text: str,
  ```

- [ ] **Step 2: Commit**

  ```
  git add python/gpt_researcher_scripts/populate_bioprio_values.py
  git commit -m "feat(values): add load_scored_context() and load_scored_context_pathway() (C6-C7)"
  ```

---

## Task 6: populate_bioprio_values.py — replace processing loops with DAG-enforced version (C8)

**Files:**
- Modify: `python/gpt_researcher_scripts/populate_bioprio_values.py`

This is the largest change. Replace the two processing loops inside `populate_values_for_assessment()`.

- [ ] **Step 1: Replace the processing loops**

  Find this block (starting at the `# Process regular answers` comment, ending at `return total`):
  ```python
            # Process regular answers
            for i, ans in enumerate(answers, 1):
                q_data = self.get_question_options(ans['idQuestion'], "questions")
                if not q_data:
                    continue

                q_code = q_data['code']  # Use proper question code (ENT1, EST4, etc.)
                print(f"[{i}/{len(answers)}] {q_code}...", end=" ")

                start = datetime.now()
                values, in_tok, out_tok = await self.determine_values_with_gpt(
                    species_name, q_data['question'], q_data['options'],
                    ans['justification'], q_data['type'], question_code=q_code
                )
                duration = (datetime.now() - start).total_seconds()

                metrics = QuestionMetrics(
                    species_name=species_name, question_code=q_code,
                    start_time=start, end_time=datetime.now(),
                    duration_seconds=duration, input_tokens=in_tok, output_tokens=out_tok,
                    total_tokens=in_tok + out_tok
                )

                if values and not all(v is None for v in [values['min'], values['likely'], values['max']]):
                    self.update_answer_values(ans['idAnswer'], values['min'], values['likely'], values['max'])
                    print(f"✅ {values['min']}/{values['likely']}/{values['max']}")
                    metrics.status = "success"
                else:
                    print("⏭️ skipped")
                    metrics.status = "skipped"

                if track_costs and cost_tracker:
                    cost_tracker.record_question(metrics)

            # Process pathway answers
            for i, ans in enumerate(pathway_answers, 1):
                q_data = self.get_question_options(ans['idPathQuestion'], "pathwayQuestions")
                if not q_data:
                    continue

                q_code = q_data['code']  # Use proper question code (ENT2A, ENT2B, etc.)
                pathway_name = ans.get('pathway_name', '')
                print(f"[{i}/{len(pathway_answers)}] {q_code} ({pathway_name})...", end=" ")

                # Special handling for "Intentional introduction" pathway
                # ENT2A, ENT2B, ENT3 should all be set to MAXIMUM values
                is_intentional = pathway_name.lower() == "intentional introduction"
                is_entry_question = q_code in ["ENT2A", "ENT2B", "ENT3"]

                if is_intentional and is_entry_question:
                    # Get maximum option and set all values to max
                    max_opt = self.get_max_option_for_question(ans['idPathQuestion'], "pathwayQuestions")
                    if max_opt:
                        self.update_pathway_answer_values(ans['idPathAnswer'], max_opt, max_opt, max_opt)
                        print(f"✅ {max_opt}/{max_opt}/{max_opt} (INTENTIONAL: auto-max)")

                        metrics = QuestionMetrics(
                            species_name=species_name, question_code=q_code,
                            start_time=datetime.now(), end_time=datetime.now(),
                            duration_seconds=0, input_tokens=0, output_tokens=0, total_tokens=0,
                            status="success"
                        )
                        if track_costs and cost_tracker:
                            cost_tracker.record_question(metrics)
                        continue

                start = datetime.now()
                values, in_tok, out_tok = await self.determine_values_with_gpt(
                    species_name, q_data['question'], q_data['options'],
                    ans['justification'], q_data['type'], question_code=q_code
                )
                duration = (datetime.now() - start).total_seconds()

                metrics = QuestionMetrics(
                    species_name=species_name, question_code=q_code,
                    start_time=start, end_time=datetime.now(),
                    duration_seconds=duration, input_tokens=in_tok, output_tokens=out_tok,
                    total_tokens=in_tok + out_tok
                )

                if values and not all(v is None for v in [values['min'], values['likely'], values['max']]):
                    self.update_pathway_answer_values(ans['idPathAnswer'], values['min'], values['likely'], values['max'])
                    print(f"✅ {values['min']}/{values['likely']}/{values['max']}")
                    metrics.status = "success"
                else:
                    print("⏭️ skipped")
                    metrics.status = "skipped"

                if track_costs and cost_tracker:
                    cost_tracker.record_question(metrics)

            if track_costs and cost_tracker:
                cost_tracker.end_species()

            return total
  ```

  Replace with:
  ```python
            # ── DAG init ─────────────────────────────────────────────────────
            scored_context: Dict[str, Dict[str, str]] = self.load_scored_context(assessment_id)
            options_map: Dict[str, List[Dict]] = {}
            jsonl_path = str(
                Path(self.db_path).parent / f"dag_corrections_{Path(self.db_path).stem}.jsonl"
            )

            # Pre-enrich regular answers with 'code' for topological sort
            for _a in answers:
                _qd = self.get_question_options(_a['idQuestion'], "questions")
                _a['code'] = _qd['code'] if _qd else f"UNKNOWN_{_a['idQuestion']}"
            answers = topological_sort_answers(answers, is_pathway=False)

            # Process regular answers
            print("=" * 60)
            print("Processing Regular Answers")
            print("=" * 60 + "\n")

            for i, ans in enumerate(answers, 1):
                q_data = self.get_question_options(ans['idQuestion'], "questions")
                if not q_data:
                    continue

                q_code = ans['code']
                options = q_data['options']
                question_type = q_data['type']
                options_map[q_code] = options

                print(f"[{i}/{len(answers)}] {q_code}...", end=" ")

                # Tier 1: zero-force check
                forcing = check_zero_forcing(
                    q_code, scored_context, options, question_type, is_pathway=False
                )
                forced_params = {f["parameter"] for f in forcing["flags"]} if forcing else set()
                all_forced = forced_params == {"min", "likely", "max"}

                final_values: Optional[Dict] = None
                in_tok = out_tok = 0

                if all_forced:
                    final_values = {
                        "min": forcing["min"],
                        "likely": forcing["likely"],
                        "max": forcing["max"],
                    }
                    print(f"⚡ zero-forced")
                else:
                    prior_ctx = build_scored_prior_context(q_code, scored_context, options_map)
                    start = datetime.now()
                    gpt_values, in_tok, out_tok = await self.determine_values_with_gpt(
                        species_name, q_data['question'], options,
                        ans['justification'], question_type, question_code=q_code,
                        prior_context=prior_ctx,
                    )
                    duration = (datetime.now() - start).total_seconds()

                    if gpt_values is None:
                        print("⏭️ error")
                        if track_costs and cost_tracker:
                            cost_tracker.record_question(QuestionMetrics(
                                species_name=species_name, question_code=q_code,
                                input_tokens=in_tok, output_tokens=out_tok,
                                total_tokens=in_tok + out_tok, status="error"
                            ))
                        continue

                    if forcing is not None:
                        final_values = dict(gpt_values)
                        for flag in forcing["flags"]:
                            flag["original_option"] = gpt_values.get(flag["parameter"])
                            final_values[flag["parameter"]] = forcing[flag["parameter"]]
                        print(f"⚡ partial zero-forcing")
                    else:
                        final_values = gpt_values

                # Post-GPT sibling clamp
                clamp = check_sibling_clamp(q_code, final_values, scored_context, options_map)
                if clamp is not None:
                    final_values = {
                        "min": clamp["min"],
                        "likely": clamp["likely"],
                        "max": clamp["max"],
                    }

                # Write and update scored_context
                status = "skipped"
                if final_values and not all(v is None for v in final_values.values()):
                    self.update_answer_values(
                        ans['idAnswer'],
                        final_values['min'], final_values['likely'], final_values['max']
                    )
                    scored_context[q_code] = {k: final_values[k] for k in ("min", "likely", "max")}
                    status = "success"
                    print(f"✅ {final_values['min']}/{final_values['likely']}/{final_values['max']}")
                else:
                    print("⏭️ skipped (NO/zero)")

                if track_costs and cost_tracker:
                    cost_tracker.record_question(QuestionMetrics(
                        species_name=species_name, question_code=q_code,
                        input_tokens=in_tok, output_tokens=out_tok,
                        total_tokens=in_tok + out_tok, status=status
                    ))

                # JSONL audit
                timestamp = datetime.now().isoformat(timespec="seconds")
                all_flags = list(forcing["flags"] if forcing else [])
                if clamp:
                    all_flags.extend(clamp["flags"])
                for flag in all_flags:
                    append_dag_correction(jsonl_path, {
                        "assessment_id": assessment_id,
                        "question_code": q_code,
                        "parameter": flag["parameter"],
                        "rule_fired": flag["rule_fired"],
                        "original_option": flag.get("original_option"),
                        "forced_option": flag.get("forced_option"),
                        "timestamp": timestamp,
                    })

            # Process pathway answers
            print("=" * 60)
            print("Processing Pathway Answers")
            print("=" * 60 + "\n")

            # Pre-enrich pathway answers with 'code' for topological sort
            for pa in pathway_answers:
                if 'code' not in pa:
                    pa['code'] = pa.get('question_code', f"UNKNOWN_{pa['idPathQuestion']}")

            # Group by idEntryPathway; DAG state is fresh per pathway instance
            pathway_groups: Dict[int, List[Dict]] = {}
            for pa in pathway_answers:
                pathway_groups.setdefault(pa['idEntryPathway'], []).append(pa)

            total_pathway_answers = len(pathway_answers)
            global_pathway_counter = 0

            for id_entry_pathway, group in pathway_groups.items():
                sorted_group = topological_sort_answers(group, is_pathway=True)
                scored_context_pathway: Dict[str, Dict[str, str]] = self.load_scored_context_pathway(
                    id_entry_pathway
                )
                pathway_options_map: Dict[str, List[Dict]] = {}

                for answer in sorted_group:
                    global_pathway_counter += 1
                    i = global_pathway_counter

                    id_path_answer = answer['idPathAnswer']
                    id_path_question = answer['idPathQuestion']
                    q_code = answer['code']
                    pathway_name = answer.get('pathway_name', '')
                    justification = answer['justification']

                    q_data = self.get_question_options(id_path_question, "pathwayQuestions")
                    if not q_data:
                        print(f"[{i}/{total_pathway_answers}] ⚠️ pathway question {id_path_question} not found")
                        continue

                    options = q_data['options']
                    question_type = q_data['type']
                    pathway_options_map[q_code] = options

                    print(f"[{i}/{total_pathway_answers}] {q_code} ({pathway_name})...", end=" ")

                    # Intentional introduction auto-max (BioPRIO-specific)
                    is_intentional = pathway_name.lower() == "intentional introduction"
                    is_entry_question = q_code in ["ENT2A", "ENT2B", "ENT3"]
                    if is_intentional and is_entry_question:
                        max_opt = self.get_max_option_for_question(id_path_question, "pathwayQuestions")
                        if max_opt:
                            self.update_pathway_answer_values(id_path_answer, max_opt, max_opt, max_opt)
                            scored_context_pathway[q_code] = {
                                "min": max_opt, "likely": max_opt, "max": max_opt
                            }
                            print(f"✅ {max_opt}/{max_opt}/{max_opt} (INTENTIONAL: auto-max)")
                            if track_costs and cost_tracker:
                                cost_tracker.record_question(QuestionMetrics(
                                    species_name=species_name, question_code=q_code,
                                    input_tokens=0, output_tokens=0, total_tokens=0,
                                    status="success"
                                ))
                            continue

                    # Tier 1: zero-force check (pathway-scoped)
                    forcing = check_zero_forcing(
                        q_code, scored_context_pathway, options, question_type, is_pathway=True
                    )
                    forced_params = {f["parameter"] for f in forcing["flags"]} if forcing else set()
                    all_forced = forced_params == {"min", "likely", "max"}

                    final_values = None
                    in_tok = out_tok = 0

                    if all_forced:
                        final_values = {
                            "min": forcing["min"],
                            "likely": forcing["likely"],
                            "max": forcing["max"],
                        }
                        print(f"⚡ zero-forced")
                    else:
                        prior_ctx = build_scored_prior_context(
                            q_code, scored_context_pathway, pathway_options_map
                        )
                        start = datetime.now()
                        gpt_values, in_tok, out_tok = await self.determine_values_with_gpt(
                            species_name, q_data['question'], options,
                            justification, question_type, question_code=q_code,
                            prior_context=prior_ctx,
                        )
                        duration = (datetime.now() - start).total_seconds()

                        if gpt_values is None:
                            print("⏭️ error")
                            if track_costs and cost_tracker:
                                cost_tracker.record_question(QuestionMetrics(
                                    species_name=species_name, question_code=q_code,
                                    input_tokens=in_tok, output_tokens=out_tok,
                                    total_tokens=in_tok + out_tok, status="error"
                                ))
                            continue

                        if forcing is not None:
                            final_values = dict(gpt_values)
                            for flag in forcing["flags"]:
                                flag["original_option"] = gpt_values.get(flag["parameter"])
                                final_values[flag["parameter"]] = forcing[flag["parameter"]]
                            print(f"⚡ partial zero-forcing")
                        else:
                            final_values = gpt_values

                    # Post-GPT sibling clamp
                    clamp = check_sibling_clamp(
                        q_code, final_values, scored_context_pathway, pathway_options_map
                    )
                    if clamp is not None:
                        final_values = {
                            "min": clamp["min"],
                            "likely": clamp["likely"],
                            "max": clamp["max"],
                        }

                    # Write and update per-pathway state
                    status = "skipped"
                    if final_values and not all(v is None for v in final_values.values()):
                        self.update_pathway_answer_values(
                            id_path_answer,
                            final_values['min'], final_values['likely'], final_values['max']
                        )
                        scored_context_pathway[q_code] = {
                            k: final_values[k] for k in ("min", "likely", "max")
                        }
                        status = "success"
                        print(f"✅ {final_values['min']}/{final_values['likely']}/{final_values['max']}")
                    else:
                        print("⏭️ skipped (NO/zero)")

                    if track_costs and cost_tracker:
                        cost_tracker.record_question(QuestionMetrics(
                            species_name=species_name, question_code=q_code,
                            input_tokens=in_tok, output_tokens=out_tok,
                            total_tokens=in_tok + out_tok, status=status
                        ))

                    # JSONL audit
                    timestamp = datetime.now().isoformat(timespec="seconds")
                    all_flags = list(forcing["flags"] if forcing else [])
                    if clamp:
                        all_flags.extend(clamp["flags"])
                    for flag in all_flags:
                        append_dag_correction(jsonl_path, {
                            "assessment_id": assessment_id,
                            "question_code": q_code,
                            "parameter": flag["parameter"],
                            "rule_fired": flag["rule_fired"],
                            "original_option": flag.get("original_option"),
                            "forced_option": flag.get("forced_option"),
                            "timestamp": timestamp,
                        })

            if track_costs and cost_tracker:
                cost_tracker.end_species()

            return total
  ```

- [ ] **Step 2: Quick syntax check**

  Run from `python/gpt_researcher_scripts/`:
  ```
  python -c "import ast, pathlib; ast.parse(pathlib.Path('populate_bioprio_values.py').read_text(encoding='utf-8')); print('Syntax OK')"
  ```
  Expected: `Syntax OK`

- [ ] **Step 3: Commit**

  ```
  git add python/gpt_researcher_scripts/populate_bioprio_values.py
  git commit -m "feat(values): replace processing loops with DAG-enforced versions (C8)"
  ```

---

## Task 7: populate_bioprio_justifications.py — LLM config + versioned DB naming (D1–D2)

**Files:**
- Modify: `python/gpt_researcher_scripts/populate_bioprio_justifications.py`

- [ ] **Step 1: Update FAST_LLM and STRATEGIC_LLM in the `os.environ.update({})` block**

  Find:
  ```python
      "FAST_LLM": "openai:gpt-4o-mini",   # Quick tasks: summarization, sub-queries
      "SMART_LLM": "openai:gpt-4.1",      # Complex reasoning: report writing
      "STRATEGIC_LLM": "openai:o4-mini",  # Planning: agent/query selection
  ```

  Replace with:
  ```python
      "FAST_LLM": "openai:gpt-4.1-mini",  # Quick tasks: summarization, sub-queries
      "SMART_LLM": "openai:gpt-4.1",      # Complex reasoning: report writing
      "STRATEGIC_LLM": "openai:o3",       # Planning: agent/query selection
  ```

- [ ] **Step 2: Replace `copy_database()` with FinnPRIO's versioned variant**

  Find:
  ```python
  def copy_database(source_path: str, output_dir: str) -> str:
      """Copy entire source database to new location."""
      # Get original database name without extension
      source_file = Path(source_path)
      original_name = source_file.stem  # filename without .db
  ```

  Read the full body of the existing `copy_database()` (from `def copy_database` to the next top-level `def`), then replace the entire function with:

  ```python
  def copy_database(source_path: str, output_dir: str) -> str:
      """Copy source database to a versioned, timestamped destination.

      Names follow `{base}_v{NNN}_{ISO8601}.db`, e.g.
          ants_v003_2026-05-16T10-04-27.db

      Version is auto-incremented based on existing `{base}_v*_*.db` files in
      `output_dir`. Timestamp uses ISO 8601 with ':' replaced by '-' so the
      filename is valid on Windows. Both parts together guarantee every run
      produces a unique, chronologically sortable, reproducible identifier.
      """
      source_file = Path(source_path)
      original_name = source_file.stem

      # Strip any existing versioned suffix first, then the legacy
      # `_ai_enhanced_...` suffix, to recover a clean base name.
      base_name = re.sub(r'_v\d+_\d{4}-\d{2}-\d{2}T.*$', '', original_name)
      base_name = re.sub(r'_ai_enhanced_.*$', '', base_name)

      output_dir_path = Path(output_dir)
      output_dir_path.mkdir(parents=True, exist_ok=True)

      # Next version: max existing + 1, or 1 if no prior versions exist.
      existing_versions = []
      for f in output_dir_path.glob(f"{base_name}_v*_*.db"):
          m = re.match(rf'{re.escape(base_name)}_v(\d+)_', f.stem)
          if m:
              existing_versions.append(int(m.group(1)))
      next_version = (max(existing_versions) + 1) if existing_versions else 1

      # ISO 8601 timestamp, filesystem-safe (colons → hyphens).
      timestamp = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")

      output_name = f"{base_name}_v{next_version:03d}_{timestamp}.db"
      output_path = output_dir_path / output_name

      # Safety guard: copying a file onto itself corrupts it.
      if source_file.resolve() == output_path.resolve():
          print(f"\n📋 Source and destination resolve to the same file; reusing it.")
          print(f"   Path: {output_path}")
          return str(output_path)

      print(f"\n📋 Copying database...")
      print(f"   From: {source_path}")
      print(f"   To:   {output_path}")

      shutil.copy2(source_path, output_path)

      if output_path.exists():
          print(f"✅ Database copied ({output_path.stat().st_size / 1024:.1f} KB)")
      else:
          raise FileNotFoundError(f"Failed to copy database to {output_path}")

      return str(output_path)
  ```

  Note: `re` is already imported at line 29. `shutil` is already imported. `datetime` is already imported. No new imports needed.

- [ ] **Step 3: Syntax check**

  ```
  python -c "import ast, pathlib; ast.parse(pathlib.Path('populate_bioprio_justifications.py').read_text(encoding='utf-8')); print('Syntax OK')"
  ```
  Expected: `Syntax OK`

- [ ] **Step 4: Commit**

  ```
  git add python/gpt_researcher_scripts/populate_bioprio_justifications.py
  git commit -m "feat(justifications): update LLM models and versioned copy_database (D1-D2)"
  ```

---

## Task 8: populate_bioprio_justifications.py — DAG context injection (D3a–D3d)

**Files:**
- Modify: `python/gpt_researcher_scripts/populate_bioprio_justifications.py`

- [ ] **Step 1: Add `sys` import and sys.path shim + dag_config import after the existing import block**

  Find:
  ```python
  import os
  import asyncio
  import sqlite3
  import shutil
  import time
  from pathlib import Path
  from gpt_researcher import GPTResearcher
  from gpt_researcher.utils.enum import Tone
  from datetime import datetime
  from typing import Dict, List, Tuple, Optional
  from dataclasses import dataclass, field
  import re

  # Import instructions loader (auto-generates JSON from Rmd if needed)
  from bioprio_instructions_loader import build_justification_prompt
  ```

  Replace with:
  ```python
  import os
  import sys
  import asyncio
  import sqlite3
  import shutil
  import time
  from pathlib import Path
  from collections import deque
  from gpt_researcher import GPTResearcher
  from gpt_researcher.utils.enum import Tone
  from datetime import datetime
  from typing import Dict, List, Tuple, Optional
  from dataclasses import dataclass, field
  import re

  # Import instructions loader (auto-generates JSON from Rmd if needed)
  from bioprio_instructions_loader import build_justification_prompt

  # DAG configuration (modules live in parent python/ directory)
  sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
  from dag_config import QUESTION_DEPENDENCIES, PATHWAY_DEPENDENCIES, SIBLING_CONSTRAINTS
  ```

- [ ] **Step 2: Add DAG context helper functions before `copy_database()`**

  Find:
  ```python
  # =============================================================================
  # DATABASE FUNCTIONS - GENERAL
  # =============================================================================

  def copy_database(source_path: str, output_dir: str) -> str:
  ```

  Replace with:
  ```python
  # =============================================================================
  # DAG CONTEXT FUNCTIONS
  # =============================================================================

  def normalize_code(code: str) -> str:
      """Canonical form: uppercase, no trailing dot."""
      return code.upper().rstrip('.')


  def _first_n_sentences(text: str, n: int = 3) -> str:
      """Return the first n sentences of text."""
      sentences = re.split(r'(?<=[.!?])\s+', text.strip())
      return ' '.join(sentences[:n])


  def get_regular_prior_answers(db_path: str, assessment_id: int,
                                 dep_codes: List[str]) -> Dict[str, str]:
      """Fetch justifications for regular question dependencies.

      Returns {normalized_code: justification_excerpt} for each dep that has a
      non-empty justification in the DB.
      """
      if not dep_codes:
          return {}

      conn = sqlite3.connect(db_path)
      cursor = conn.cursor()
      cursor.execute("""
          SELECT q."group" || q.number ||
                 CASE WHEN q.subgroup IS NOT NULL THEN '.' || q.subgroup ELSE '' END AS code_raw,
                 a.justification
          FROM answers a
          JOIN questions q ON a.idQuestion = q.idQuestion
          WHERE a.idAssessment = ?
            AND a.justification IS NOT NULL
            AND a.justification != ''
      """, (assessment_id,))
      rows = cursor.fetchall()
      conn.close()

      dep_set = set(dep_codes)
      result = {}
      for code_raw, justification in rows:
          code = normalize_code(code_raw)
          if code in dep_set:
              result[code] = justification
      return result


  def get_pathway_prior_answers(db_path: str, id_entry_pathway: int,
                                 dep_codes: List[str]) -> Dict[str, str]:
      """Fetch justifications for same-pathway question dependencies.

      Returns {normalized_code: justification} for each dep that has a non-empty
      justification for this specific pathway instance.
      """
      if not dep_codes:
          return {}

      conn = sqlite3.connect(db_path)
      cursor = conn.cursor()
      cursor.execute("""
          SELECT pq."group" || pq.number AS code_raw,
                 pa.justification
          FROM pathwayAnswers pa
          JOIN pathwayQuestions pq ON pa.idPathQuestion = pq.idPathQuestion
          WHERE pa.idEntryPathway = ?
            AND pa.justification IS NOT NULL
            AND pa.justification != ''
      """, (id_entry_pathway,))
      rows = cursor.fetchall()
      conn.close()

      dep_set = set(dep_codes)
      result = {}
      for code_raw, justification in rows:
          code = normalize_code(code_raw)
          if code in dep_set:
              result[code] = justification
      return result


  def format_prior_context(prior_answers: Dict[str, str],
                            sibling_rule: str = None) -> str:
      """Format prior answers + optional sibling constraint as an injectable context block.

      Each prior answer is truncated to the first 3 sentences.
      Returns empty string if there is nothing to inject.
      """
      if not prior_answers and not sibling_rule:
          return ""

      lines = ["PRIOR FINDINGS (established by earlier questions in this assessment):"]
      for code, justification in prior_answers.items():
          excerpt = _first_n_sentences(justification, 3)
          lines.append(f"\n{code}: {excerpt}")
      lines.append("\nDo not re-derive facts already stated above — build on them.")

      if sibling_rule:
          lines.append(f"\nCONSTRAINT: {sibling_rule}")

      return '\n'.join(lines)


  def topological_sort_questions(questions: List[Dict],
                                  dependencies: Dict[str, List[str]]) -> List[Dict]:
      """Sort questions in topological order using Kahn's algorithm.

      Only dependencies between questions present in `questions` are considered.
      Questions whose codes are not in `dependencies` are treated as having no deps.
      """
      code_to_q = {normalize_code(q['code']): q for q in questions}
      codes = sorted(code_to_q.keys())

      in_degree = {c: 0 for c in codes}
      adj: Dict[str, List[str]] = {c: [] for c in codes}

      for code in codes:
          for dep in dependencies.get(code, []):
              if dep in code_to_q:
                  in_degree[code] += 1
                  adj[dep].append(code)

      queue = deque(sorted(c for c in codes if in_degree[c] == 0))
      result = []

      while queue:
          node = queue.popleft()
          result.append(code_to_q[node])
          for dependent in sorted(adj[node]):
              in_degree[dependent] -= 1
              if in_degree[dependent] == 0:
                  queue.append(dependent)

      # Append any remaining (shouldn't happen with a valid DAG)
      processed = {normalize_code(q['code']) for q in result}
      result.extend(code_to_q[c] for c in codes if c not in processed)

      return result


  def build_prior_context(db_path: str, assessment_id: int, question_code: str,
                           id_entry_pathway: int = None) -> str:
      """Assemble the prior-context string to inject into a research query.

      Fetches dependency justifications from the correct table(s) and applies
      any sibling constraint rule from SIBLING_CONSTRAINTS.
      """
      code = normalize_code(question_code)
      is_pathway_q = (code in PATHWAY_DEPENDENCIES and
                      code not in QUESTION_DEPENDENCIES)

      if is_pathway_q and id_entry_pathway is not None:
          all_deps = PATHWAY_DEPENDENCIES.get(code, [])
          regular_deps = [d for d in all_deps if d in QUESTION_DEPENDENCIES]
          pathway_deps = [d for d in all_deps if d in PATHWAY_DEPENDENCIES]
          prior = {}
          prior.update(get_regular_prior_answers(db_path, assessment_id, regular_deps))
          prior.update(get_pathway_prior_answers(db_path, id_entry_pathway, pathway_deps))
      else:
          deps = QUESTION_DEPENDENCIES.get(code, [])
          prior = get_regular_prior_answers(db_path, assessment_id, deps)

      sibling_rule = None
      if code in SIBLING_CONSTRAINTS:
          sc = SIBLING_CONSTRAINTS[code]
          sib = sc['sibling']
          if id_entry_pathway is not None and sib in PATHWAY_DEPENDENCIES:
              sib_ans = get_pathway_prior_answers(db_path, id_entry_pathway, [sib])
          else:
              sib_ans = get_regular_prior_answers(db_path, assessment_id, [sib])
          prior.update(sib_ans)
          sibling_rule = sc['rule']

      return format_prior_context(prior, sibling_rule)


  # =============================================================================
  # DATABASE FUNCTIONS - GENERAL
  # =============================================================================

  def copy_database(source_path: str, output_dir: str) -> str:
  ```

- [ ] **Step 3: Add `prior_context` parameter to `create_research_query()`**

  Find:
  ```python
  def create_research_query(species_name: str, question_code: str, question_text: str,
                            question_info: str = "", pathway_name: str = None) -> str:
      """Create targeted research query.

      Note: question_info from database is IGNORED when Rmd instructions are available,
      as the Rmd provides more accurate and up-to-date guidance.
      """

      # Get specific instructions from Rmd (preferred) or hardcoded fallback
      specific = get_question_specific_instructions(question_code, species_name, pathway_name)
  ```

  Replace with:
  ```python
  def create_research_query(species_name: str, question_code: str, question_text: str,
                            question_info: str = "", pathway_name: str = None,
                            prior_context: str = "") -> str:
      """Create targeted research query.

      prior_context (if non-empty) is injected after the metadata header and
      before the question block so the LLM reads established facts first.

      Note: question_info from database is IGNORED when Rmd instructions are available,
      as the Rmd provides more accurate and up-to-date guidance.
      """

      # Get specific instructions from Rmd (preferred) or hardcoded fallback
      specific = get_question_specific_instructions(question_code, species_name, pathway_name)
  ```

  Then find the line where the query string is assembled and inject prior_context. The current code builds `query` as a multi-line f-string. Find the section that returns `query` at the end of the function (after all the if/else blocks for using_rmd_instructions):

  Find:
  ```python
      # Note: formal academic register is delivered via tone=Tone.Formal on GPTResearcher.
      # Inline citations and reference list are enforced by the research_report prompt itself.
      return query
  ```

  Replace with:
  ```python
      if prior_context:
          query = prior_context + "\n\n" + query

      # Note: formal academic register is delivered via tone=Tone.Formal on GPTResearcher.
      # Inline citations and reference list are enforced by the research_report prompt itself.
      return query
  ```

- [ ] **Step 4: Add `prior_context` parameter to `research_justification()`**

  Find:
  ```python
  async def research_justification(species_name: str, question_code: str, question_text: str,
                                   question_info: str = "", pathway_name: str = None,
                                   exclude_domains: List[str] = None,
                                   track_metrics: bool = True) -> Tuple[str, Optional[QuestionMetrics]]:
      """Research a single justification using GPT Researcher.

      Returns:
          Tuple of (report_text, metrics) where metrics may be None if tracking disabled.
      """
      global cost_tracker

      pathway_text = f" (Pathway: {pathway_name})" if pathway_name else ""
      print(f"\n{'=' * 80}")
      print(f"Researching: {species_name} - {question_code}{pathway_text}")
      print(f"{'=' * 80}\n")

      if exclude_domains:
          print(f"⛔ Excluding: {', '.join(exclude_domains)}")

      # Initialize metrics
      metrics = QuestionMetrics(
          species_name=species_name,
          question_code=question_code,
          question_text=question_text[:100],  # Truncate for storage
          pathway_name=pathway_name,
          start_time=datetime.now()
      ) if track_metrics else None

      query = create_research_query(species_name, question_code, question_text,
                                    question_info, pathway_name)
  ```

  Replace with:
  ```python
  async def research_justification(species_name: str, question_code: str, question_text: str,
                                   question_info: str = "", pathway_name: str = None,
                                   exclude_domains: List[str] = None,
                                   track_metrics: bool = True,
                                   prior_context: str = "") -> Tuple[str, Optional[QuestionMetrics]]:
      """Research a single justification using GPT Researcher.

      Returns:
          Tuple of (report_text, metrics) where metrics may be None if tracking disabled.
      """
      global cost_tracker

      pathway_text = f" (Pathway: {pathway_name})" if pathway_name else ""
      print(f"\n{'=' * 80}")
      print(f"Researching: {species_name} - {question_code}{pathway_text}")
      print(f"{'=' * 80}\n")

      if exclude_domains:
          print(f"⛔ Excluding: {', '.join(exclude_domains)}")

      if prior_context:
          print(f"🔗 Injecting prior context ({len(prior_context)} chars)")

      # Initialize metrics
      metrics = QuestionMetrics(
          species_name=species_name,
          question_code=question_code,
          question_text=question_text[:100],  # Truncate for storage
          pathway_name=pathway_name,
          start_time=datetime.now()
      ) if track_metrics else None

      query = create_research_query(species_name, question_code, question_text,
                                    question_info, pathway_name, prior_context=prior_context)
  ```

- [ ] **Step 5: Update `process_assessment()` to add topological sort and prior context**

  In `process_assessment()`, find the block that processes regular questions:

  Find:
  ```python
      # Filter to specific questions if requested
      if question_filter:
          filter_codes = {c.upper().rstrip('.') for c in question_filter}
          answers = [a for a in answers if a['code'].upper().rstrip('.') in filter_codes]
          print(f"🔍 Filtering to questions: {', '.join(sorted(filter_codes))}")
          if not answers:
              print(f"⚠️  No matching regular questions found for {filter_codes}")

      # Auto-add all pathways if requested
  ```

  Replace with:
  ```python
      # Filter to specific questions if requested
      if question_filter:
          filter_codes = {c.upper().rstrip('.') for c in question_filter}
          answers = [a for a in answers if a['code'].upper().rstrip('.') in filter_codes]
          print(f"🔍 Filtering to questions: {', '.join(sorted(filter_codes))}")
          if not answers:
              print(f"⚠️  No matching regular questions found for {filter_codes}")

      # Topological sort: process questions in dependency order so prior context
      # is always written to DB before it is needed by dependent questions.
      answers = topological_sort_questions(answers, QUESTION_DEPENDENCIES)

      # Auto-add all pathways if requested
  ```

  Then find the `research_justification` call inside the regular questions loop:

  Find:
  ```python
          try:
              ai_text, metrics = await research_justification(
                  species_name=species_name,
                  question_code=answer['code'],
                  question_text=answer['text'],
                  question_info=answer['info'],
                  exclude_domains=exclude_domains or [],
                  track_metrics=track_costs
              )
  ```

  Replace with:
  ```python
          try:
              prior_ctx = build_prior_context(db_path, assessment_id, answer['code'])
              ai_text, metrics = await research_justification(
                  species_name=species_name,
                  question_code=answer['code'],
                  question_text=answer['text'],
                  question_info=answer['info'],
                  exclude_domains=exclude_domains or [],
                  track_metrics=track_costs,
                  prior_context=prior_ctx,
              )
  ```

  Then find the pathway questions loop. Add topological sort for pathway_questions and prior context for each pathway question call.

  Find:
  ```python
              # Sort pathway questions in dependency order (if not already)
              # Note: pathway_questions currently processed in DB order
              total = len(pathways) * len(pathway_questions)
              count = 0
  ```

  If this exact comment doesn't exist, find:
  ```python
              total = len(pathways) * len(pathway_questions)
              count = 0
  ```

  Replace with:
  ```python
              # Sort pathway questions in dependency order
              sorted_pqs = topological_sort_questions(pathway_questions, PATHWAY_DEPENDENCIES)
              pathway_questions = sorted_pqs

              total = len(pathways) * len(pathway_questions)
              count = 0
  ```

  Then find the `research_justification` call inside the pathway loop:

  Find:
  ```python
                  try:
                      ai_text, metrics = await research_justification(
                          species_name=species_name,
                          question_code=pq['code'],
                          question_text=pq['text'],
                          question_info=pq['info'],
                          pathway_name=pathway_name,
                          exclude_domains=exclude_domains or [],
                          track_metrics=track_costs
                      )
  ```

  Replace with:
  ```python
                  try:
                      pq_prior_ctx = build_prior_context(
                          db_path, assessment_id, pq['code'],
                          id_entry_pathway=pathway['idEntryPathway'])
                      ai_text, metrics = await research_justification(
                          species_name=species_name,
                          question_code=pq['code'],
                          question_text=pq['text'],
                          question_info=pq['info'],
                          pathway_name=pathway_name,
                          exclude_domains=exclude_domains or [],
                          track_metrics=track_costs,
                          prior_context=pq_prior_ctx,
                      )
  ```

- [ ] **Step 6: Syntax check**

  Run from `python/gpt_researcher_scripts/`:
  ```
  python -c "import ast, pathlib; ast.parse(pathlib.Path('populate_bioprio_justifications.py').read_text(encoding='utf-8')); print('Syntax OK')"
  ```
  Expected: `Syntax OK`

- [ ] **Step 7: Commit**

  ```
  git add python/gpt_researcher_scripts/populate_bioprio_justifications.py
  git commit -m "feat(justifications): add DAG context injection, topological sort, prior context (D3a-D3d)"
  ```

---

## Task 9: Validation

**Files:** (read-only checks)

- [ ] **Step 1: Check no `eppo_gd` in either modified script**

  Run from `python/gpt_researcher_scripts/`:
  ```
  python -c "
  import pathlib
  for f in ['populate_bioprio_values.py', 'populate_bioprio_justifications.py']:
      text = pathlib.Path(f).read_text(encoding='utf-8')
      count = text.lower().count('eppo_gd')
      print(f'{f}: eppo_gd count = {count}')
      assert count == 0, f'FAIL: found eppo_gd in {f}'
  print('PASS: no eppo_gd found')
  "
  ```
  Expected: `PASS: no eppo_gd found`

- [ ] **Step 2: Check no `plant pest` in prompts**

  Run from `python/gpt_researcher_scripts/`:
  ```
  python -c "
  import pathlib
  for f in ['populate_bioprio_values.py', 'populate_bioprio_justifications.py']:
      text = pathlib.Path(f).read_text(encoding='utf-8')
      count = text.lower().count('plant pest')
      print(f'{f}: plant pest count = {count}')
      assert count == 0, f'FAIL: found \"plant pest\" in {f}'
  print('PASS: no plant pest found')
  "
  ```
  Expected: `PASS: no plant pest found`

- [ ] **Step 3: Verify `_call_gpt_boolean` returns a 3-tuple**

  Run from `python/gpt_researcher_scripts/`:
  ```
  python -c "
  import ast, pathlib
  tree = ast.parse(pathlib.Path('populate_bioprio_values.py').read_text(encoding='utf-8'))
  found = False
  for node in ast.walk(tree):
      if isinstance(node, ast.AsyncFunctionDef) and node.name == '_call_gpt_boolean':
          found = True
          src = pathlib.Path('populate_bioprio_values.py').read_text(encoding='utf-8')
          # Check return annotation mentions Tuple
          assert 'Tuple' in src[src.find('async def _call_gpt_boolean'):src.find('async def _call_gpt_boolean')+200], 'missing Tuple return annotation'
  assert found, 'FAIL: _call_gpt_boolean not found'
  print('PASS: _call_gpt_boolean present with Tuple annotation')
  "
  ```
  Expected: `PASS`

- [ ] **Step 4: Verify `sys.path.insert` appears before dag imports in both scripts**

  Run from `python/gpt_researcher_scripts/`:
  ```
  python -c "
  import pathlib
  for f in ['populate_bioprio_values.py', 'populate_bioprio_justifications.py']:
      lines = pathlib.Path(f).read_text(encoding='utf-8').splitlines()
      path_lines = [i for i, l in enumerate(lines) if 'sys.path.insert' in l]
      dag_lines  = [i for i, l in enumerate(lines) if 'from dag_' in l or 'import dag_' in l]
      assert path_lines, f'{f}: sys.path.insert not found'
      assert dag_lines,  f'{f}: dag import not found'
      assert min(path_lines) < min(dag_lines), f'{f}: sys.path.insert must come before dag import'
      print(f'{f}: OK (sys.path.insert @ line {min(path_lines)+1}, dag import @ line {min(dag_lines)+1})')
  print('PASS')
  "
  ```
  Expected: both files print `OK` then `PASS`

- [ ] **Step 5: Final commit with validation note**

  ```
  git add -A
  git commit -m "chore: validation pass — all DAG enforcement port checks green"
  ```

"""
2_generate_finnprio_questions.py
---------------------------------
Generates a per-species SQuAI question JSONL from the FinnPRIO template.

For each species in SPECIES_LIST the script substitutes {species} in every
question and appends all records to OUTPUT_FILE.  run_SQuAI.py then loops
over the file automatically.

Output format (one JSON object per line):
    {"id": "ENT1__Thrips_palmi", "species": "Thrips palmi",
     "question": "What is the current global geographical distribution of Thrips palmi? ..."}

Usage:
    python 2_generate_finnprio_questions.py
    python 2_generate_finnprio_questions.py --species "Thrips palmi" "Liriomyza huidobrensis"
"""

# ==============================================================================
# USER CONFIGURATION
# ==============================================================================

# List of species to generate questions for.
# Use the same names as the sub-folder names in your literature directory,
# but with spaces instead of underscores (underscores are added automatically).
SPECIES_LIST = [
    "Thrips palmi",
    "Liriomyza huidobrensis",
    "Liriomyza trifolii",
    # add more species here ...
]

# Path to the template JSONL (questions with {species} placeholder).
TEMPLATE_FILE = r"C:\Users\dafl\Python\SQuAI\finnprio\finnprio_questions_template.jsonl"

# Output file – this is what run_SQuAI.py reads via --data_file.
OUTPUT_FILE = r"C:\Users\dafl\Python\SQuAI\finnprio\finnprio_questions.jsonl"

# ==============================================================================
# END OF USER CONFIGURATION
# ==============================================================================

import json
import argparse
from pathlib import Path


def load_template(template_file: str) -> list[dict]:
    records = []
    with open(template_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def generate(species_list: list[str], template: list[dict]) -> list[dict]:
    output = []
    for species in species_list:
        species_key = species.replace(" ", "_")
        for rec in template:
            output.append({
                "id":       f"{rec['id']}__{species_key}",
                "species":  species,
                "question": rec["question"].replace("{species}", species),
            })
    return output


def main():
    parser = argparse.ArgumentParser(
        description="Generate per-species BioPRIO question JSONL from FinnPRIO template"
    )
    parser.add_argument(
        "--species", nargs="+", default=None,
        help="Override SPECIES_LIST with these species (space-separated, use quotes)"
    )
    parser.add_argument(
        "--template", default=TEMPLATE_FILE,
        help=f"Template JSONL file (default: {TEMPLATE_FILE})"
    )
    parser.add_argument(
        "--output", default=OUTPUT_FILE,
        help=f"Output JSONL file (default: {OUTPUT_FILE})"
    )
    args = parser.parse_args()

    species_list   = args.species if args.species else SPECIES_LIST
    template_file  = args.template
    output_file    = args.output

    print(f"Template : {template_file}")
    print(f"Output   : {output_file}")
    print(f"Species  : {len(species_list)}")

    template = load_template(template_file)
    records  = generate(species_list, template)

    Path(output_file).parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, "w", encoding="utf-8") as f:
        for rec in records:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    print(f"\nWrote {len(records)} questions "
          f"({len(template)} criteria × {len(species_list)} species) → {output_file}")


if __name__ == "__main__":
    main()

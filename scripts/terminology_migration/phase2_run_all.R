# scripts/terminology_migration/phase2_run_all.R
# Master script to run all phase 2 migration scripts in order
#
# USAGE:
#   cd "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development"
#   Rscript scripts/terminology_migration/phase2_run_all.R

cat("========================================\n")
cat("BioPRIO Phase 2 Terminology Migration\n")
cat("========================================\n\n")

# Set working directory to project root
# (scripts use relative paths from project root)
if (!file.exists("databases/clean_database/clean.db")) {
  stop("ERROR: Must run from project root directory")
}

# Step 1: Backup
cat("\n[Step 1/6] Creating backup...\n")
cat("----------------------------------------\n")
source("scripts/terminology_migration/phase2_1_backup_database.R")

# Step 2: Replace "pest" with "species"
cat("\n[Step 2/6] Replacing 'pest' with 'species'...\n")
cat("----------------------------------------\n")
source("scripts/terminology_migration/phase2_2_pest_to_species.R")

# Step 3: Update main question specific wording
cat("\n[Step 3/6] Updating main question terminology...\n")
cat("----------------------------------------\n")
source("scripts/terminology_migration/phase2_3_update_main_questions.R")

# Step 4: Update pathway question wording
cat("\n[Step 4/6] Updating pathway question terminology...\n")
cat("----------------------------------------\n")
source("scripts/terminology_migration/phase2_4_update_pathway_questions.R")

# Step 5: Validate changes
cat("\n[Step 5/6] Validating changes...\n")
cat("----------------------------------------\n")
source("scripts/terminology_migration/phase2_5_validate_changes.R")

# Step 6: Extract final questions for review
cat("\n[Step 6/6] Extracting final questions...\n")
cat("----------------------------------------\n")
source("scripts/terminology_migration/phase2_6_extract_final_questions.R")

cat("\n========================================\n")
cat("Phase 2 Migration Complete!\n")
cat("========================================\n")
cat("\nNext steps:\n")
cat("1. Review: scripts/terminology_migration/phase2_final_questions.txt\n")
cat("2. Test the app: Rscript -e \"shiny::runApp('.', port=3838)\"\n")
cat("3. If issues, rollback: cp databases/clean_database/clean_backup_phase2_*.db databases/clean_database/clean.db\n")
cat("4. If satisfied, update CHANGELOG.md and commit\n")

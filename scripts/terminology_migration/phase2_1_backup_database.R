# scripts/terminology_migration/phase2_1_backup_database.R
# Create backup before phase 2 terminology changes
# Run this FIRST before any other phase 2 scripts

library(DBI)
library(RSQLite)

DB_FILE <- "databases/clean_database/clean.db"
BACKUP_FILE <- sprintf("databases/clean_database/clean_backup_phase2_%s.db",
                       format(Sys.Date(), "%Y%m%d"))

cat("=== BioPRIO Phase 2: Database Backup ===\n\n")

if (!file.exists(DB_FILE)) {
  stop("ERROR: Database file not found: ", DB_FILE)
}

if (file.exists(BACKUP_FILE)) {
  cat("WARNING: Backup file already exists:", BACKUP_FILE, "\n")
  cat("Skipping backup creation.\n")
} else {
  file.copy(DB_FILE, BACKUP_FILE)
  cat("Backup created:", BACKUP_FILE, "\n")
}

cat("\nBackup complete. Safe to proceed with migration.\n")

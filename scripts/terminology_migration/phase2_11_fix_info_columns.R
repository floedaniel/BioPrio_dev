# Phase 2.11: Fix info columns in questions and pathwayQuestions tables
# The Phase 2 migration missed updating the 'info' column which contains
# the guidance text shown in (i) popups

library(DBI)
library(RSQLite)

db_path <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development/databases/clean_database/clean.db"

cat("=== Phase 2.11: Fix info columns ===\n\n")

# Connect to database
con <- dbConnect(SQLite(), db_path)

# Function to apply terminology replacements
apply_terminology_fixes <- function(text) {
  if (is.na(text) || text == "") return(text)

  # 1. PRA area -> risk assessment area (do this first, it's unambiguous)
  text <- gsub("PRA area", "risk assessment area", text, ignore.case = FALSE)

  # 2. host plant(s) -> suitable host(s)
  text <- gsub("host plants", "suitable hosts", text, ignore.case = FALSE)
  text <- gsub("host plant", "suitable host", text, ignore.case = FALSE)
  text <- gsub("Host plants", "Suitable hosts", text, ignore.case = FALSE)
  text <- gsub("Host plant", "Suitable host", text, ignore.case = FALSE)

  # 3. pest -> species (careful replacements)
  # First, protect phrases we want to keep
  text <- gsub("other pests", "OTHER_PESTS_PLACEHOLDER", text)
  text <- gsub("control pests", "CONTROL_PESTS_PLACEHOLDER", text)
  text <- gsub("biological pest control", "BIOLOGICAL_PEST_CONTROL_PLACEHOLDER", text)

  # Now replace pest/Pest with species/Species
  text <- gsub("the pest's", "the species'", text)
  text <- gsub("The pest's", "The species'", text)
  text <- gsub("the pest", "the species", text)
  text <- gsub("The pest", "The species", text)
  text <- gsub("a pest", "a species", text)
  text <- gsub("A pest", "A species", text)

  # Restore protected phrases
  text <- gsub("OTHER_PESTS_PLACEHOLDER", "other pests", text)
  text <- gsub("CONTROL_PESTS_PLACEHOLDER", "control pests", text)
  text <- gsub("BIOLOGICAL_PEST_CONTROL_PLACEHOLDER", "biological pest control", text)

  return(text)
}

# ========== Update questions.info ==========
cat("Updating questions.info column...\n")

questions <- dbGetQuery(con, "SELECT idQuestion, info FROM questions WHERE info IS NOT NULL AND info != ''")
cat(sprintf("  Found %d questions with info text\n", nrow(questions)))

updated_count <- 0
for (i in 1:nrow(questions)) {
  old_info <- questions$info[i]
  new_info <- apply_terminology_fixes(old_info)

  if (old_info != new_info) {
    dbExecute(con, "UPDATE questions SET info = ? WHERE idQuestion = ?",
              params = list(new_info, questions$idQuestion[i]))
    updated_count <- updated_count + 1
  }
}
cat(sprintf("  Updated %d question info texts\n", updated_count))

# ========== Update pathwayQuestions.info ==========
cat("\nUpdating pathwayQuestions.info column...\n")

pathway_questions <- dbGetQuery(con, "SELECT idPathQuestion, info FROM pathwayQuestions WHERE info IS NOT NULL AND info != ''")
cat(sprintf("  Found %d pathway questions with info text\n", nrow(pathway_questions)))

updated_count <- 0
for (i in 1:nrow(pathway_questions)) {
  old_info <- pathway_questions$info[i]
  new_info <- apply_terminology_fixes(old_info)

  if (old_info != new_info) {
    dbExecute(con, "UPDATE pathwayQuestions SET info = ? WHERE idPathQuestion = ?",
              params = list(new_info, pathway_questions$idPathQuestion[i]))
    updated_count <- updated_count + 1
  }
}
cat(sprintf("  Updated %d pathway question info texts\n", updated_count))

# ========== Validation ==========
cat("\n=== Validation ===\n")

# Check for remaining old terminology
all_info <- dbGetQuery(con, "
  SELECT 'questions' as tbl, info FROM questions WHERE info IS NOT NULL AND info != ''
  UNION ALL
  SELECT 'pathwayQuestions' as tbl, info FROM pathwayQuestions WHERE info IS NOT NULL AND info != ''
")

combined_text <- paste(all_info$info, collapse = " ")

pra_count <- length(gregexpr("PRA area", combined_text, ignore.case = FALSE)[[1]])
if (pra_count > 0 && gregexpr("PRA area", combined_text)[[1]][1] != -1) {
  cat(sprintf("WARNING: Found %d remaining 'PRA area' occurrences\n", pra_count))
} else {
  cat("OK: No 'PRA area' remaining\n")
}

host_plant_count <- length(gregexpr("host plant", combined_text, ignore.case = TRUE)[[1]])
if (host_plant_count > 0 && gregexpr("host plant", combined_text, ignore.case = TRUE)[[1]][1] != -1) {
  cat(sprintf("WARNING: Found %d remaining 'host plant' occurrences\n", host_plant_count))
} else {
  cat("OK: No 'host plant' remaining\n")
}

# Count species (should be present now)
species_matches <- gregexpr("species", combined_text, ignore.case = FALSE)[[1]]
species_count <- if(species_matches[1] == -1) 0 else length(species_matches)
cat(sprintf("INFO: Found %d 'species' occurrences (terminology updated)\n", species_count))

# Count remaining pest (should be minimal - only intentional ones)
pest_matches <- gregexpr("pest", combined_text, ignore.case = FALSE)[[1]]
pest_count <- if(pest_matches[1] == -1) 0 else length(pest_matches)
cat(sprintf("INFO: Found %d remaining 'pest' occurrences (should be intentional only)\n", pest_count))

dbDisconnect(con)

cat("\n=== Done ===\n")
cat("Backup saved to: clean_backup_before_info_fix_20260218.db\n")

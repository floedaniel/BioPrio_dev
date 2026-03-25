# scripts/terminology_migration/phase2_4_update_pathway_questions.R
# Update pathway question wording for BioPRIO terrestrial invertebrates
# Based on reformulated_questions.Rmd proposals
# CRITICAL: Only change text, NEVER change points values

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"

con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Phase 2: Pathway Question Terminology Updates ===\n")
cat("Database:", DB_FILE, "\n\n")

updates_made <- 0

# Helper function to update pathway question text with full replacement
update_pathway_question_full <- function(con, group_val, number_val, new_question) {
  query <- sprintf(
    "SELECT idPathQuestion, question FROM pathwayQuestions WHERE [group] = '%s' AND number = '%s'",
    group_val, number_val
  )
  q <- dbGetQuery(con, query)

  if (nrow(q) == 0) {
    cat(sprintf("WARNING: Pathway question %s%s not found\n", group_val, number_val))
    return(FALSE)
  }

  old_question <- q$question[1]

  if (old_question == new_question) {
    cat(sprintf("SKIP: [%s%s] Already matches target text\n", group_val, number_val))
    return(FALSE)
  }

  update_query <- sprintf(
    "UPDATE pathwayQuestions SET question = '%s' WHERE idPathQuestion = %d",
    gsub("'", "''", new_question),
    q$idPathQuestion[1]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s]\n", group_val, number_val))
  cat(sprintf("  FROM: %s\n", old_question))
  cat(sprintf("  TO:   %s\n\n", new_question))
  return(TRUE)
}

#------------------------------------------------------------------------------
# ENTRY PATHWAY QUESTIONS
#------------------------------------------------------------------------------
cat("--- ENTRY Pathway Questions ---\n\n")

# ENT2A: Add "to the risk assessment area"
if (update_pathway_question_full(con, "ENT", "2A",
    "Not taking into account current official management measures, can the species be transported to the risk assessment area via the considered pathway?")) {
  updates_made <- updates_made + 1
}

# ENT2B: Add "to the risk assessment area"
if (update_pathway_question_full(con, "ENT", "2B",
    "Taking into account current official management measures, can the species be transported to the risk assessment area via the considered pathway?")) {
  updates_made <- updates_made + 1
}

# ENT3: Broader conveyance terminology
# Current: "host material or commodity"
# Proposed: "commodities, plant material, or other conveyances potentially associated with the species"
if (update_pathway_question_full(con, "ENT", "3",
    "How large a volume of the considered commodities, plant material, or other conveyances potentially associated with the species is traded into the risk assessment area annually?")) {
  updates_made <- updates_made + 1
}

# ENT4: Add "host, prey organism" to transfer targets
# Current: "transfer to a suitable habitat"
# Proposed: "transfer to a suitable host, prey organism, or habitat"
if (update_pathway_question_full(con, "ENT", "4",
    "Can the species transfer to a suitable host, prey organism, or habitat after entering the risk assessment area via the pathway?")) {
  updates_made <- updates_made + 1
}

dbDisconnect(con)

cat("\n=== Pathway Question Updates Complete ===\n")
cat(sprintf("Total updates made: %d\n", updates_made))

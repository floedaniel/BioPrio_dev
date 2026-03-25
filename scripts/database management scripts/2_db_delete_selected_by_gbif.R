################################################################################
# Delete Selected Species by GBIF Taxon Key
#
# This script deletes specific pests and all their associated data
# (assessments, answers, pathways, simulations) based on GBIF taxon keys
#
# WARNING: This will permanently delete data!
# Make sure to backup your database before running this script!
################################################################################

library(DBI)
library(RSQLite)

# INPUT - GBIF taxon keys to delete --------------------------------------------
input <- c(
  "666"
)

# Configuration ----------------------------------------------------------------
DB_FILE <- "./databases/ant_test/clean_ants.db"

cat("================================================================================\n")
cat("Delete Selected Species by GBIF Taxon Key\n")
cat("================================================================================\n\n")

# Connect to database
cat("Connecting to database:", DB_FILE, "\n\n")
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

# Normalize input (trim whitespace)
input <- trimws(input)
cat("GBIF taxon keys to delete:", length(input), "\n")

# Find pest IDs for given GBIF taxon keys
pests_to_delete <- dbGetQuery(con,
                              sprintf("SELECT idPest, scientificName, gbifTaxonKey FROM pests WHERE gbifTaxonKey IN (%s)",
                                      paste(sprintf("'%s'", input), collapse = ", ")))

if (nrow(pests_to_delete) == 0) {
  cat("\nNo pests found with the given GBIF taxon keys.\n")
  dbDisconnect(con)
  stop("Nothing to delete.")
}

cat("\nPests found to delete:\n")

for (i in seq_len(nrow(pests_to_delete))) {
  cat(sprintf("  [%d] %s (GBIF: %s)\n",
              pests_to_delete$idPest[i],
              pests_to_delete$scientificName[i],
              pests_to_delete$gbifTaxonKey[i]))
}

# Report GBIF keys not found
found_keys <- pests_to_delete$gbifTaxonKey
not_found <- setdiff(input, found_keys)

if (length(not_found) > 0) {
  cat("\nGBIF taxon keys not found in database:\n")
  cat(sprintf("  %s\n", paste(not_found, collapse = ", ")))
}

pest_ids <- pests_to_delete$idPest
pest_ids_str <- paste(pest_ids, collapse = ", ")

# Find assessment IDs linked to these pests
assessments_to_delete <- dbGetQuery(con,
                                    sprintf("SELECT idAssessment FROM assessments WHERE idPest IN (%s)", pest_ids_str))

assessment_ids <- assessments_to_delete$idAssessment

cat(sprintf("\nAssessments to delete: %d\n", length(assessment_ids)))

# Disable foreign key constraints
cat("\nDisabling foreign key constraints...\n")

dbExecute(con, "PRAGMA foreign_keys = OFF")

# Delete in correct order (child tables first)
cat("\nDeleting data...\n")

if (length(assessment_ids) > 0) {
  assessment_ids_str <- paste(assessment_ids, collapse = ", ")
  
  # 1. Find entry pathway IDs for these assessments
  entry_pathways <- dbGetQuery(con,
                               sprintf("SELECT idEntryPathway FROM entryPathways WHERE idAssessment IN (%s)", assessment_ids_str))
  entry_pathway_ids <- entry_pathways$idEntryPathway
  
  # 2. Find simulation IDs for these assessments
  simulations <- dbGetQuery(con,
                            sprintf("SELECT idSimulation FROM simulations WHERE idAssessment IN (%s)", assessment_ids_str))
  simulation_ids <- simulations$idSimulation
  
  # Delete simulationSummaries
  if (length(simulation_ids) > 0) {
    simulation_ids_str <- paste(simulation_ids, collapse = ", ")
    n <- dbExecute(con, sprintf("DELETE FROM simulationSummaries WHERE idSimulation IN (%s)", simulation_ids_str))
    cat(sprintf("  simulationSummaries: %d rows deleted\n", n))
    
    # Delete simulations
    n <- dbExecute(con, sprintf("DELETE FROM simulations WHERE idSimulation IN (%s)", simulation_ids_str))
    cat(sprintf("  simulations: %d rows deleted\n", n))
  } else {
    cat("  simulationSummaries: 0 rows deleted\n")
    cat("  simulations: 0 rows deleted\n")
  }
  
  # Delete pathwayAnswers
  if (length(entry_pathway_ids) > 0) {
    entry_pathway_ids_str <- paste(entry_pathway_ids, collapse = ", ")
    n <- dbExecute(con, sprintf("DELETE FROM pathwayAnswers WHERE idEntryPathway IN (%s)", entry_pathway_ids_str))
    cat(sprintf("  pathwayAnswers: %d rows deleted\n", n))
  } else {
    cat("  pathwayAnswers: 0 rows deleted\n")
  }
  
  # Delete answers
  n <- dbExecute(con, sprintf("DELETE FROM answers WHERE idAssessment IN (%s)", assessment_ids_str))
  cat(sprintf("  answers: %d rows deleted\n", n))
  
  # Delete threatXassessment
  n <- dbExecute(con, sprintf("DELETE FROM threatXassessment WHERE idAssessment IN (%s)", assessment_ids_str))
  cat(sprintf("  threatXassessment: %d rows deleted\n", n))
  
  # Delete entryPathways
  n <- dbExecute(con, sprintf("DELETE FROM entryPathways WHERE idAssessment IN (%s)", assessment_ids_str))
  cat(sprintf("  entryPathways: %d rows deleted\n", n))
  
  # Delete assessments
  n <- dbExecute(con, sprintf("DELETE FROM assessments WHERE idAssessment IN (%s)", assessment_ids_str))
  cat(sprintf("  assessments: %d rows deleted\n", n))
}

# Delete pests
n <- dbExecute(con, sprintf("DELETE FROM pests WHERE idPest IN (%s)", pest_ids_str))

cat(sprintf("  pests: %d rows deleted\n", n))

# Re-enable foreign key constraints
cat("\nRe-enabling foreign key constraints...\n")
dbExecute(con, "PRAGMA foreign_keys = ON")

# Summary
cat("\n================================================================================\n")
cat("DELETION COMPLETE\n")
cat("================================================================================\n\n")

cat("Remaining row counts:\n")
for (table in c("pests", "assessments", "entryPathways", "answers", 
                "pathwayAnswers", "threatXassessment", "simulations", "simulationSummaries")) {
  tryCatch({
    count <- dbGetQuery(con, sprintf("SELECT COUNT(*) as n FROM %s", table))$n
    cat(sprintf("  %-25s: %d rows\n", table, count))
  }, error = function(e) {
    cat(sprintf("  %-25s: ERROR\n", table))
  })
}

# Close connection
dbDisconnect(con)

cat(sprintf("\nDatabase saved: %s\n", DB_FILE))

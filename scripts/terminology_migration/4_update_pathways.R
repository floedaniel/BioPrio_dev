# scripts/terminology_migration/4_update_pathways.R
# Update pathway names for BioPRIO (terrestrial invertebrates using CBD classification)
# Task 4 of BioPRIO terminology migration

library(DBI)
library(RSQLite)

DB_FILE <- "databases/clean_database/clean.db"

# Connect to database
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Terminology Migration: Pathways ===\n")
cat("Database:", DB_FILE, "\n\n")

# Show current pathways before update
cat("--- Current Pathways (BEFORE update) ---\n")
before <- dbGetQuery(con, "SELECT idPathway, name, [group] FROM pathways ORDER BY idPathway")
print(before)
cat("\n")

# Define pathway renamings (current name -> new name)
# Only rename A, C, D, E pathways; keep B, F, G, H unchanged
pathway_updates <- list(
  list(id = 1, old = "Seeds", new = "Contaminant of seeds or growing media"),
  list(id = 3, old = "Wood and wood products", new = "Wood and wood packaging"),
  list(id = 4, old = "Food and fodder", new = "Agricultural commodities"),
  list(id = 5, old = "Other living plant parts", new = "Cut plant material")
)

# Pathways to keep unchanged (for verification)
unchanged_pathways <- c(
  "Plants for planting",      # B (id 2)
  "Hitchhiking",              # F (id 6)
  "Natural spread",           # G (id 7)
  "Intentional introduction"  # H (id 8)
)

cat("--- Updating Pathways ---\n\n")

# Track updates
updates_made <- 0

for (upd in pathway_updates) {
  # Get current pathway
  query <- sprintf("SELECT idPathway, name FROM pathways WHERE idPathway = %d", upd$id)
  current <- dbGetQuery(con, query)

  if (nrow(current) == 0) {
    cat(sprintf("WARNING: Pathway ID %d not found\n", upd$id))
    next
  }

  current_name <- current$name[1]

  # Verify current name matches expected
  if (current_name != upd$old) {
    cat(sprintf("WARNING: Pathway ID %d has unexpected name\n", upd$id))
    cat(sprintf("  Expected: '%s'\n", upd$old))
    cat(sprintf("  Found:    '%s'\n", current_name))
    cat("  Skipping this update for safety.\n\n")
    next
  }

  # Perform update
  update_query <- sprintf(
    "UPDATE pathways SET name = '%s' WHERE idPathway = %d",
    gsub("'", "''", upd$new),  # Escape single quotes
    upd$id
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: Pathway ID %d\n", upd$id))
  cat(sprintf("  FROM: '%s'\n", upd$old))
  cat(sprintf("  TO:   '%s'\n\n", upd$new))
  updates_made <- updates_made + 1
}

cat("--- Verifying Unchanged Pathways ---\n\n")

# Verify pathways B, F, G, H are unchanged
for (pathway_name in unchanged_pathways) {
  query <- sprintf("SELECT idPathway, name FROM pathways WHERE name = '%s'", pathway_name)
  result <- dbGetQuery(con, query)

  if (nrow(result) > 0) {
    cat(sprintf("OK: '%s' (ID %d) - unchanged\n", pathway_name, result$idPathway[1]))
  } else {
    cat(sprintf("WARNING: '%s' not found - may have been accidentally modified!\n", pathway_name))
  }
}

cat("\n--- Final Pathways (AFTER update) ---\n")
after <- dbGetQuery(con, "SELECT idPathway, name, [group] FROM pathways ORDER BY idPathway")
print(after)

# Close connection
dbDisconnect(con)

cat("\n=== Migration Complete ===\n")
cat(sprintf("Total pathway updates made: %d\n", updates_made))
cat("\nPathway mapping summary:\n")
cat("  A: Seeds -> Contaminant of seeds or growing media\n")
cat("  B: Plants for planting (unchanged)\n")
cat("  C: Wood and wood products -> Wood and wood packaging\n")
cat("  D: Food and fodder -> Agricultural commodities\n")
cat("  E: Other living plant parts -> Cut plant material\n")
cat("  F: Hitchhiking (unchanged)\n")
cat("  G: Natural spread (unchanged)\n")
cat("  H: Intentional introduction (unchanged)\n")

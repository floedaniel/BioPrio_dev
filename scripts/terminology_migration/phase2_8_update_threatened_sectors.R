# scripts/terminology_migration/phase2_8_update_threatened_sectors.R
# Replace agriculture-focused "Threatened Sectors" with ecological habitat categories
# for terrestrial invertebrate assessments

library(DBI)
library(RSQLite)

DB_FILE <- "databases/clean_database/clean.db"

con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Phase 2: Update Threatened Sectors ===\n")
cat("Database:", DB_FILE, "\n\n")

# First, show current state
cat("--- Current Threatened Sectors ---\n")
current <- dbGetQuery(con, "SELECT * FROM threatenedSectors ORDER BY threatGroup, idThrSect")
print(current)

# Check table schema for constraints
cat("\n--- Current Table Schema ---\n")
schema <- dbGetQuery(con, "SELECT sql FROM sqlite_master WHERE type='table' AND name='threatenedSectors'")
cat(schema$sql, "\n")

# SQLite doesn't support ALTER TABLE to drop constraints
# We need to recreate the table

cat("\n--- Recreating table without CHECK constraint ---\n")

# Step 1: Create new table without constraint
dbExecute(con, "
  CREATE TABLE threatenedSectors_new (
    idThrSect INTEGER PRIMARY KEY NOT NULL,
    threatGroup TEXT NOT NULL DEFAULT 'Others',
    name TEXT NOT NULL
  )
")
cat("Created new table structure.\n")

# Step 2: Drop old table
dbExecute(con, "DROP TABLE threatenedSectors")
cat("Dropped old table.\n")

# Step 3: Rename new table
dbExecute(con, "ALTER TABLE threatenedSectors_new RENAME TO threatenedSectors")
cat("Renamed to threatenedSectors.\n")

# Step 4: Insert new ecological habitat categories
cat("\n--- Inserting new habitat categories ---\n")

new_sectors <- list(
  # Forest ecosystems (1-4)
  list(1, "Forest ecosystems", "Coniferous forest"),
  list(2, "Forest ecosystems", "Deciduous forest"),
  list(3, "Forest ecosystems", "Mixed forest"),
  list(4, "Forest ecosystems", "Forest plantations"),
  # Open terrestrial (5-8)
  list(5, "Open terrestrial habitats", "Grasslands & meadows"),
  list(6, "Open terrestrial habitats", "Heathland & shrubland"),
  list(7, "Open terrestrial habitats", "Alpine & mountain habitats"),
  list(8, "Open terrestrial habitats", "Coastal habitats"),
  # Wetlands & freshwater (9-12)
  list(9, "Wetlands & freshwater", "Mires & bogs"),
  list(10, "Wetlands & freshwater", "Fens & marshes"),
  list(11, "Wetlands & freshwater", "Lakes & ponds"),
  list(12, "Wetlands & freshwater", "Rivers & streams"),
  # Agricultural (13-16)
  list(13, "Agricultural systems", "Arable land & crops"),
  list(14, "Agricultural systems", "Orchards & fruit production"),
  list(15, "Agricultural systems", "Pastures & grazing land"),
  list(16, "Agricultural systems", "Greenhouses & nurseries"),
  # Urban & gardens (17-20)
  list(17, "Urban & built environments", "Urban green spaces"),
  list(18, "Urban & built environments", "Private gardens"),
  list(19, "Urban & built environments", "Parks & recreational areas"),
  list(20, "Urban & built environments", "Infrastructure corridors"),
  # Special interest (21-24)
  list(21, "Special ecological interest", "Pollinator networks"),
  list(22, "Special ecological interest", "Deadwood & saproxylic habitats"),
  list(23, "Special ecological interest", "Soil ecosystems"),
  list(24, "Special ecological interest", "Cultural landscapes")
)

# Insert each sector
for (sector in new_sectors) {
  dbExecute(con, sprintf(
    "INSERT INTO threatenedSectors (idThrSect, threatGroup, name) VALUES (%d, '%s', '%s')",
    sector[[1]], sector[[2]], sector[[3]]
  ))
}

cat(sprintf("Inserted %d new habitat categories.\n", length(new_sectors)))

# Show new state
cat("\n--- New Threatened Sectors ---\n")
new_state <- dbGetQuery(con, "SELECT * FROM threatenedSectors ORDER BY idThrSect")
print(new_state)

# Verify
cat("\n--- Summary by Group ---\n")
summary <- dbGetQuery(con, "SELECT threatGroup, COUNT(*) as count FROM threatenedSectors GROUP BY threatGroup ORDER BY MIN(idThrSect)")
print(summary)

dbDisconnect(con)

cat("\n=== Update Complete ===\n")
cat("Replaced 14 agriculture-focused sectors with 24 ecological habitat categories.\n")

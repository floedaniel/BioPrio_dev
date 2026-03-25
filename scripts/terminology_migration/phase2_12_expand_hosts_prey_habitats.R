# Phase 2.12: Expand "suitable hosts" to include prey and habitats
# Context-specific review - not all instances should be expanded
#
# Decision framework:
# - EXPAND: General references to what species depends on for survival/establishment
# - KEEP AS-IS: Specific plant cultivation contexts (greenhouses, field crops)
#   BUT still expand to cover invertebrate scenarios
# - ADJUST: Some phrasings need grammatical adjustment

library(DBI)
library(RSQLite)

db_path <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development/databases/clean_database/clean.db"

cat("=== Phase 2.12: Expand hosts to include prey & habitats ===\n\n")

con <- dbConnect(SQLite(), db_path)

# Define replacement patterns with context-aware logic
# Using a function that applies multiple targeted replacements

expand_to_hosts_prey_habitats <- function(text) {
  if (is.na(text) || text == "") return(text)

  # Pattern 1: "suitable hosts" in general ecological contexts -> expand
  # "suitable hosts are present" -> "suitable hosts, prey, or habitats are present"
  text <- gsub("suitable hosts are present", "suitable hosts, prey, or habitats are present", text)
  text <- gsub("suitable hosts grow", "suitable hosts, prey, or habitats occur", text)
  text <- gsub("suitable hosts occur", "suitable hosts, prey, or habitats occur", text)

  # Pattern 2: "suitable hosts that" contexts
  text <- gsub("suitable hosts that are considered threatened",
               "suitable hosts, prey, or habitats that are considered threatened", text)
  text <- gsub("suitable hosts that occur naturally",
               "suitable hosts, prey, or habitats that occur naturally", text)
  text <- gsub("suitable hosts considered threatened",
               "suitable hosts, prey, or habitats considered threatened", text)

  # Pattern 3: Distribution/area of suitable hosts
  text <- gsub("distribution of suitable hosts",
               "distribution of suitable hosts, prey, or habitats", text)
  text <- gsub("abundance and the distribution of suitable hosts",
               "abundance and distribution of suitable hosts, prey, or habitats", text)
  text <- gsub("Suitable hosts do not occur",
               "Suitable hosts, prey, or habitats do not occur", text)

  # Pattern 4: Species locating/finding
  text <- gsub("locate suitable hosts or mates",
               "locate suitable hosts, prey, habitats, or mates", text)
  text <- gsub("locate suitable hosts",
               "locate suitable hosts, prey, or habitats", text)
  text <- gsub("actively seek suitable habitats",
               "actively locate suitable hosts, prey, or habitats", text)

  # Pattern 5: Survival without hosts
  text <- gsub("survive without living suitable hosts",
               "survive without suitable hosts, prey, or habitats", text)
  text <- gsub("survive without a living suitable host",
               "survive without suitable hosts, prey, or habitats", text)
  text <- gsub("survive without suitable hosts",
               "survive without suitable hosts, prey, or habitats", text)
  text <- gsub("without a suitable host",
               "without suitable hosts, prey, or habitats", text)

  # Pattern 6: Species' suitable hosts (possessive contexts)
  text <- gsub("species' suitable hosts do not occur",
               "species' suitable hosts, prey, or habitats do not occur", text)
  text <- gsub("species's suitable hosts do not occur",
               "species' suitable hosts, prey, or habitats do not occur", text)

  # Pattern 7: Having/threatening suitable hosts
  text <- gsub("has several suitable hosts from different plant families",
               "has several suitable hosts from different taxonomic groups, or uses multiple prey species or habitat types", text)
  text <- gsub("adapted to new suitable hosts",
               "adapted to new suitable hosts, prey, or habitats", text)

  # Pattern 8: Production/area contexts - expand but keep cultivation context
  text <- gsub("production area of the threatened suitable hosts",
               "area where threatened suitable hosts, prey, or habitats occur", text)

  # Pattern 9: Supporting reproduction
  text <- gsub("suitable hosts supporting reproduction",
               "suitable hosts, prey, or habitats supporting reproduction", text)

  # Pattern 10: Transfer between hosts
  text <- gsub("shift to another host species",
               "shift to another host, prey, or habitat type", text)

  # Pattern 11: Regions/areas where suitable hosts occur
  text <- gsub("only suitable hosts in regions",
               "only suitable hosts, prey, or habitats in regions", text)

  # Pattern 12: Suitable host patches
  text <- gsub("suitable host patches",
               "patches of suitable hosts, prey, or habitats", text)

  # Pattern 13: Wild species as hosts
  text <- gsub("wild species are suitable hosts",
               "wild species provide suitable hosts, prey, or habitats", text)

  # Pattern 14: Eradication contexts
  text <- gsub("survive outside its suitable hosts",
               "survive outside suitable hosts, prey, or habitats", text)
  text <- gsub("eradication of the suitable hosts",
               "eradication of suitable hosts or modification of habitats", text)

  # Pattern 15: Greenhouse/field contexts - these are plant-focused but should still
  # acknowledge invertebrate scenarios
  text <- gsub("suitable hosts are produced in greenhouses",
               "suitable hosts are present in greenhouses, or suitable prey/habitats exist in controlled environments", text)
  text <- gsub("suitable hosts are only cultivated in greenhouses",
               "suitable hosts, prey, or habitats are only present in controlled environments", text)
  text <- gsub("suitable hosts are cultivated on open land",
               "suitable hosts, prey, or habitats occur on open land", text)
  text <- gsub("suitable hosts are not produced year-round",
               "suitable hosts, prey, or habitats are not present year-round", text)
  text <- gsub("suitable hosts grow or are cultivated so sparsely",
               "suitable hosts, prey, or habitats occur so sparsely", text)
  text <- gsub("suitable hosts grow or are cultivated so commonly",
               "suitable hosts, prey, or habitats occur so commonly", text)
  text <- gsub("suitable hosts are not cultivated",
               "suitable hosts, prey, or habitats do not occur", text)
  text <- gsub("suitable hosts are commonly cultivated",
               "suitable hosts, prey, or habitats commonly occur", text)
  text <- gsub("suitable hosts are widespread",
               "suitable hosts, prey, or habitats are widespread", text)
  text <- gsub("suitable hosts are very widespread",
               "suitable hosts, prey, or habitats are very widespread", text)
  text <- gsub("suitable hosts are present",
               "suitable hosts, prey, or habitats are present", text)

  # Pattern 16: Sparsely cultivated
  text <- gsub("suitable hosts are sparsely cultivated field crops",
               "suitable hosts, prey, or habitats are sparse (e.g., limited crop areas, rare prey species, or restricted habitat types)", text)

  # Pattern 17: Spread on suitable hosts
  text <- gsub("spread \"rather quickly\" on one of its suitable host species",
               "spread \"rather quickly\" within one type of suitable host, prey, or habitat", text)
  text <- gsub("spread \"quickly\" on one of its suitable hosts",
               "spread \"quickly\" within one type of suitable host, prey, or habitat", text)
  text <- gsub("spread on one of its suitable hosts",
               "spread within one type of suitable host, prey, or habitat", text)

  # Pattern 18: Used as houseplants
  text <- gsub("suitable hosts are used only as houseplants",
               "suitable hosts are limited to indoor plants, or suitable prey/habitats only exist indoors", text)

  # Pattern 19: Widespread field crops / native plants
  text <- gsub("suitable hosts are widespread field crops or naturally occurring plants",
               "suitable hosts, prey, or habitats are widespread (e.g., common crops, abundant prey species, or extensive natural habitats)", text)
  text <- gsub("suitable hosts are field crops that are commonly cultivated",
               "suitable hosts, prey, or habitats are widespread (e.g., common field crops, abundant prey, or extensive habitats)", text)

  # Pattern 20: Rate of spread and hosts
  text <- gsub("its suitable hosts grow very sparsely",
               "its suitable hosts, prey, or habitats are very sparse", text)
  text <- gsub("suitable hosts' occurrence does not limit",
               "availability of suitable hosts, prey, or habitats does not limit", text)

  # Pattern 21: Several potential hosts
  text <- gsub("several potential suitable hosts growing on open land",
               "multiple potential suitable hosts, prey species, or habitats on open land", text)

  # Pattern 22: From houseplants to outdoors
  text <- gsub("spread to suitable hosts growing outdoors",
               "spread to suitable hosts, prey, or habitats outdoors", text)

  # Clean up any double spaces
  text <- gsub("  +", " ", text)

  return(text)
}

# ========== Update questions.info ==========
cat("Updating questions.info column...\n")

questions <- dbGetQuery(con, "SELECT idQuestion, info FROM questions WHERE info IS NOT NULL AND info != ''")
cat(sprintf("  Processing %d questions\n", nrow(questions)))

updated_count <- 0
for (i in 1:nrow(questions)) {
  old_info <- questions$info[i]
  new_info <- expand_to_hosts_prey_habitats(old_info)

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
cat(sprintf("  Processing %d pathway questions\n", nrow(pathway_questions)))

updated_count <- 0
for (i in 1:nrow(pathway_questions)) {
  old_info <- pathway_questions$info[i]
  new_info <- expand_to_hosts_prey_habitats(old_info)

  if (old_info != new_info) {
    dbExecute(con, "UPDATE pathwayQuestions SET info = ? WHERE idPathQuestion = ?",
              params = list(new_info, pathway_questions$idPathQuestion[i]))
    updated_count <- updated_count + 1
  }
}
cat(sprintf("  Updated %d pathway question info texts\n", updated_count))

# ========== Validation ==========
cat("\n=== Validation ===\n")

all_info <- dbGetQuery(con, "
  SELECT 'questions' as tbl, info FROM questions WHERE info IS NOT NULL AND info != ''
  UNION ALL
  SELECT 'pathwayQuestions' as tbl, info FROM pathwayQuestions WHERE info IS NOT NULL AND info != ''
")

combined_text <- paste(all_info$info, collapse = " ")

# Count key terms
hosts_only <- length(gregexpr("suitable hosts[^,]", combined_text)[[1]])
hosts_prey_hab <- length(gregexpr("suitable hosts, prey", combined_text)[[1]])
prey_count <- length(gregexpr("prey", combined_text)[[1]])
habitat_count <- length(gregexpr("habitat", combined_text)[[1]])

cat(sprintf("'suitable hosts, prey' phrases: %d\n", hosts_prey_hab))
cat(sprintf("Total 'prey' occurrences: %d\n", prey_count))
cat(sprintf("Total 'habitat' occurrences: %d\n", habitat_count))

dbDisconnect(con)

cat("\n=== Done ===\n")

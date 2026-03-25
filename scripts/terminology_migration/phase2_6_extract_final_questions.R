# scripts/terminology_migration/phase2_6_extract_final_questions.R
# Extract all questions after phase 2 migration for review

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"
OUTPUT_FILE <- "scripts/terminology_migration/phase2_final_questions.txt"

con <- dbConnect(RSQLite::SQLite(), DB_FILE)

sink(OUTPUT_FILE)

cat("=== MAIN QUESTIONS (after Phase 2) ===\n\n")

main_q <- dbGetQuery(con,
  "SELECT [group], number, question, list FROM questions ORDER BY [group], number")

for (i in seq_len(nrow(main_q))) {
  cat(sprintf("[%s%s] %s\n", main_q$group[i], main_q$number[i], main_q$question[i]))

  opts <- fromJSON(main_q$list[i])
  for (j in seq_len(nrow(opts))) {
    cat(sprintf("  %s. %s (points: %s)\n", opts$opt[j], opts$text[j], opts$points[j]))
  }
  cat("\n")
}

cat("=== PATHWAY QUESTIONS (after Phase 2) ===\n\n")

path_q <- dbGetQuery(con,
  "SELECT [group], number, question, list FROM pathwayQuestions ORDER BY [group], number")

for (i in seq_len(nrow(path_q))) {
  cat(sprintf("[%s%s] %s\n", path_q$group[i], path_q$number[i], path_q$question[i]))

  opts <- fromJSON(path_q$list[i])
  for (j in seq_len(nrow(opts))) {
    cat(sprintf("  %s. %s (points: %s)\n", opts$opt[j], opts$text[j], opts$points[j]))
  }
  cat("\n")
}

cat("=== PATHWAYS ===\n")
pathways <- dbGetQuery(con, "SELECT * FROM pathways ORDER BY idPathway")
print(pathways)

sink()

dbDisconnect(con)

cat("Questions extracted to:", OUTPUT_FILE, "\n")
cat("Review this file to verify all changes.\n")

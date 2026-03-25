# scripts/terminology_migration/1_extract_current_questions.R
# Extract current question text for review before migration

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

# Extract main questions
questions <- dbGetQuery(con, "SELECT idQuestion, [group], number, question, list FROM questions")
cat("=== MAIN QUESTIONS ===\n")
for (i in seq_len(nrow(questions))) {
  cat(sprintf("\n[%s%s] %s\n", questions$group[i], questions$number[i], questions$question[i]))
  opts <- fromJSON(questions$list[i])
  for (j in seq_along(opts$opt)) {
    cat(sprintf("  %s. %s (points: %s)\n", opts$opt[j], opts$text[j], opts$points[j]))
  }
}

# Extract pathway questions
path_questions <- dbGetQuery(con, "SELECT idPathQuestion, [group], number, question, list FROM pathwayQuestions")
cat("\n=== PATHWAY QUESTIONS ===\n")
for (i in seq_len(nrow(path_questions))) {
  cat(sprintf("\n[%s%s] %s\n", path_questions$group[i], path_questions$number[i], path_questions$question[i]))
  opts <- fromJSON(path_questions$list[i])
  for (j in seq_along(opts$opt)) {
    cat(sprintf("  %s. %s (points: %s)\n", opts$opt[j], opts$text[j], opts$points[j]))
  }
}

# Extract pathways
pathways <- dbGetQuery(con, "SELECT idPathway, name, [group] FROM pathways")
cat("\n=== PATHWAYS ===\n")
print(pathways)

dbDisconnect(con)

# Phase 2.12b: Fix remaining unexpanded "suitable host" phrases

library(DBI)
library(RSQLite)

db_path <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development/databases/clean_database/clean.db"

con <- dbConnect(SQLite(), db_path)

fix_remaining <- function(text) {
  if (is.na(text) || text == "") return(text)

  # Fix remaining patterns
  text <- gsub("on its suitable hosts, or the species can",
               "on its suitable hosts, prey, or habitats, or the species can", text)
  text <- gsub("without suitable hosts\\. Species",
               "without suitable hosts, prey, or habitats. Species", text)
  text <- gsub("suitable host species is required",
               "suitable host, prey, or habitat type is required", text)
  text <- gsub("suitable host species, but a shift",
               "suitable host, prey, or habitat type, but a shift", text)
  text <- gsub("suitable hosts, but a shift",
               "suitable hosts, prey, or habitats, but a shift", text)
  text <- gsub("suitable hosts' occurrence does not limit",
               "suitable hosts, prey, or habitats does not limit", text)
  text <- gsub("suitable hosts are widely present",
               "suitable hosts, prey, or habitats are widespread", text)

  return(text)
}

# Update questions
questions <- dbGetQuery(con, "SELECT idQuestion, info FROM questions WHERE info IS NOT NULL")
updated <- 0
for (i in 1:nrow(questions)) {
  old_info <- questions$info[i]
  new_info <- fix_remaining(old_info)
  if (old_info != new_info) {
    dbExecute(con, "UPDATE questions SET info = ? WHERE idQuestion = ?",
              params = list(new_info, questions$idQuestion[i]))
    updated <- updated + 1
  }
}
cat("Updated", updated, "questions\n")

# Update pathway questions
pq <- dbGetQuery(con, "SELECT idPathQuestion, info FROM pathwayQuestions WHERE info IS NOT NULL")
updated <- 0
for (i in 1:nrow(pq)) {
  old_info <- pq$info[i]
  new_info <- fix_remaining(old_info)
  if (old_info != new_info) {
    dbExecute(con, "UPDATE pathwayQuestions SET info = ? WHERE idPathQuestion = ?",
              params = list(new_info, pq$idPathQuestion[i]))
    updated <- updated + 1
  }
}
cat("Updated", updated, "pathway questions\n")

dbDisconnect(con)
cat("Done\n")

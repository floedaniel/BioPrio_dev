# scripts/terminology_migration/phase2_7_standardize_pra_area.R
# Standardize "PRA area" to "risk assessment area" throughout
# CRITICAL: Only change text, NEVER change points values

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"

con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Phase 2: Standardize 'PRA area' -> 'risk assessment area' ===\n")
cat("Database:", DB_FILE, "\n\n")

updates_questions <- 0
updates_options <- 0

#------------------------------------------------------------------------------
# MAIN QUESTIONS - Question text
#------------------------------------------------------------------------------
cat("--- Main Questions: Question Text ---\n\n")

main_q <- dbGetQuery(con, "SELECT idQuestion, [group], number, question FROM questions")

for (i in seq_len(nrow(main_q))) {
  old_text <- main_q$question[i]

  if (!grepl("PRA area", old_text, fixed = TRUE)) {
    next
  }

  new_text <- gsub("PRA area", "risk assessment area", old_text, fixed = TRUE)

  update_query <- sprintf(
    "UPDATE questions SET question = '%s' WHERE idQuestion = %d",
    gsub("'", "''", new_text),
    main_q$idQuestion[i]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s]\n", main_q$group[i], main_q$number[i]))
  cat(sprintf("  FROM: %s\n", old_text))
  cat(sprintf("  TO:   %s\n\n", new_text))
  updates_questions <- updates_questions + 1
}

#------------------------------------------------------------------------------
# MAIN QUESTIONS - Answer options
#------------------------------------------------------------------------------
cat("--- Main Questions: Answer Options ---\n\n")

main_opts <- dbGetQuery(con, "SELECT idQuestion, [group], number, list FROM questions")

for (i in seq_len(nrow(main_opts))) {
  old_list <- main_opts$list[i]

  if (!grepl("PRA area", old_list, fixed = TRUE)) {
    next
  }

  opts <- fromJSON(old_list)

  updated <- FALSE
  for (j in seq_along(opts$text)) {
    if (grepl("PRA area", opts$text[j], fixed = TRUE)) {
      opts$text[j] <- gsub("PRA area", "risk assessment area", opts$text[j], fixed = TRUE)
      updated <- TRUE
    }
  }

  if (updated) {
    # Rebuild JSON preserving exact points values
    json_parts <- character(nrow(opts))
    for (j in seq_len(nrow(opts))) {
      json_parts[j] <- sprintf(
        '{"opt": "%s", "text": "%s", "points": %s}',
        opts$opt[j],
        gsub('"', '\\"', opts$text[j]),
        opts$points[j]
      )
    }
    new_list <- paste0("[", paste(json_parts, collapse = ","), "]")

    update_query <- sprintf(
      "UPDATE questions SET list = '%s' WHERE idQuestion = %d",
      gsub("'", "''", new_list),
      main_opts$idQuestion[i]
    )
    dbExecute(con, update_query)

    cat(sprintf("UPDATED: [%s%s] answer options\n", main_opts$group[i], main_opts$number[i]))
    updates_options <- updates_options + 1
  }
}

#------------------------------------------------------------------------------
# PATHWAY QUESTIONS - Question text
#------------------------------------------------------------------------------
cat("--- Pathway Questions: Question Text ---\n\n")

path_q <- dbGetQuery(con, "SELECT idPathQuestion, [group], number, question FROM pathwayQuestions")

for (i in seq_len(nrow(path_q))) {
  old_text <- path_q$question[i]

  if (!grepl("PRA area", old_text, fixed = TRUE)) {
    next
  }

  new_text <- gsub("PRA area", "risk assessment area", old_text, fixed = TRUE)

  update_query <- sprintf(
    "UPDATE pathwayQuestions SET question = '%s' WHERE idPathQuestion = %d",
    gsub("'", "''", new_text),
    path_q$idPathQuestion[i]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s]\n", path_q$group[i], path_q$number[i]))
  cat(sprintf("  FROM: %s\n", old_text))
  cat(sprintf("  TO:   %s\n\n", new_text))
  updates_questions <- updates_questions + 1
}

#------------------------------------------------------------------------------
# PATHWAY QUESTIONS - Answer options
#------------------------------------------------------------------------------
cat("--- Pathway Questions: Answer Options ---\n\n")

path_opts <- dbGetQuery(con, "SELECT idPathQuestion, [group], number, list FROM pathwayQuestions")

for (i in seq_len(nrow(path_opts))) {
  old_list <- path_opts$list[i]

  if (!grepl("PRA area", old_list, fixed = TRUE)) {
    next
  }

  opts <- fromJSON(old_list)

  updated <- FALSE
  for (j in seq_along(opts$text)) {
    if (grepl("PRA area", opts$text[j], fixed = TRUE)) {
      opts$text[j] <- gsub("PRA area", "risk assessment area", opts$text[j], fixed = TRUE)
      updated <- TRUE
    }
  }

  if (updated) {
    json_parts <- character(nrow(opts))
    for (j in seq_len(nrow(opts))) {
      json_parts[j] <- sprintf(
        '{"opt": "%s", "text": "%s", "points": %s}',
        opts$opt[j],
        gsub('"', '\\"', opts$text[j]),
        opts$points[j]
      )
    }
    new_list <- paste0("[", paste(json_parts, collapse = ","), "]")

    update_query <- sprintf(
      "UPDATE pathwayQuestions SET list = '%s' WHERE idPathQuestion = %d",
      gsub("'", "''", new_list),
      path_opts$idPathQuestion[i]
    )
    dbExecute(con, update_query)

    cat(sprintf("UPDATED: [%s%s] answer options\n", path_opts$group[i], path_opts$number[i]))
    updates_options <- updates_options + 1
  }
}

#------------------------------------------------------------------------------
# VERIFY NO "PRA area" REMAINS
#------------------------------------------------------------------------------
cat("\n--- Verification ---\n\n")

# Check main questions
remaining <- dbGetQuery(con,
  "SELECT [group], number FROM questions WHERE question LIKE '%PRA area%' OR list LIKE '%PRA area%'")
if (nrow(remaining) > 0) {
  cat("WARNING: 'PRA area' still found in main questions:\n")
  print(remaining)
} else {
  cat("PASS: No 'PRA area' in main questions\n")
}

# Check pathway questions
remaining_path <- dbGetQuery(con,
  "SELECT [group], number FROM pathwayQuestions WHERE question LIKE '%PRA area%' OR list LIKE '%PRA area%'")
if (nrow(remaining_path) > 0) {
  cat("WARNING: 'PRA area' still found in pathway questions:\n")
  print(remaining_path)
} else {
  cat("PASS: No 'PRA area' in pathway questions\n")
}

dbDisconnect(con)

cat("\n=== Standardization Complete ===\n")
cat(sprintf("Question text updates: %d\n", updates_questions))
cat(sprintf("Answer option updates: %d\n", updates_options))
cat(sprintf("TOTAL: %d updates\n", updates_questions + updates_options))

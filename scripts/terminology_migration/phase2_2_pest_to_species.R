# scripts/terminology_migration/phase2_2_pest_to_species.R
# Replace "pest" with "species" throughout main and pathway questions
# CRITICAL: Only change text, NEVER change points values

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"

con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Phase 2: pest -> species replacement ===\n")
cat("Database:", DB_FILE, "\n\n")

# Track all updates
updates_main_questions <- 0
updates_main_options <- 0
updates_pathway_questions <- 0
updates_pathway_options <- 0

#------------------------------------------------------------------------------
# MAIN QUESTIONS - Question text
#------------------------------------------------------------------------------
cat("--- Main Questions: Question Text ---\n\n")

main_q <- dbGetQuery(con, "SELECT idQuestion, [group], number, question FROM questions")

for (i in seq_len(nrow(main_q))) {
  old_text <- main_q$question[i]

  # Replace variations of "pest"
  new_text <- old_text
  new_text <- gsub("the pest", "the species", new_text, fixed = TRUE)
  new_text <- gsub("The pest", "The species", new_text, fixed = TRUE)
  new_text <- gsub("pest's", "species'", new_text, fixed = TRUE)
  new_text <- gsub("Pest's", "Species'", new_text, fixed = TRUE)

  if (new_text != old_text) {
    update_query <- sprintf(
      "UPDATE questions SET question = '%s' WHERE idQuestion = %d",
      gsub("'", "''", new_text),
      main_q$idQuestion[i]
    )
    dbExecute(con, update_query)

    cat(sprintf("UPDATED: [%s%s]\n", main_q$group[i], main_q$number[i]))
    cat(sprintf("  FROM: %s\n", old_text))
    cat(sprintf("  TO:   %s\n\n", new_text))
    updates_main_questions <- updates_main_questions + 1
  }
}

#------------------------------------------------------------------------------
# MAIN QUESTIONS - Answer options (JSON list column)
#------------------------------------------------------------------------------
cat("--- Main Questions: Answer Options ---\n\n")

main_opts <- dbGetQuery(con, "SELECT idQuestion, [group], number, list FROM questions")

for (i in seq_len(nrow(main_opts))) {
  old_list <- main_opts$list[i]

  # Check if "pest" exists in list
  if (!grepl("pest", old_list, ignore.case = TRUE)) {
    next
  }

  # Parse JSON
  opts <- fromJSON(old_list)

  updated <- FALSE
  for (j in seq_along(opts$text)) {
    old_opt_text <- opts$text[j]
    new_opt_text <- old_opt_text
    new_opt_text <- gsub("the pest", "the species", new_opt_text, fixed = TRUE)
    new_opt_text <- gsub("The pest", "The species", new_opt_text, fixed = TRUE)
    new_opt_text <- gsub("pest's", "species'", new_opt_text, fixed = TRUE)
    new_opt_text <- gsub(" pest ", " species ", new_opt_text, fixed = TRUE)
    new_opt_text <- gsub(" pest?", " species?", new_opt_text, fixed = TRUE)

    if (new_opt_text != old_opt_text) {
      opts$text[j] <- new_opt_text
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
    updates_main_options <- updates_main_options + 1
  }
}

#------------------------------------------------------------------------------
# PATHWAY QUESTIONS - Question text
#------------------------------------------------------------------------------
cat("\n--- Pathway Questions: Question Text ---\n\n")

path_q <- dbGetQuery(con, "SELECT idPathQuestion, [group], number, question FROM pathwayQuestions")

for (i in seq_len(nrow(path_q))) {
  old_text <- path_q$question[i]

  new_text <- old_text
  new_text <- gsub("the pest", "the species", new_text, fixed = TRUE)
  new_text <- gsub("The pest", "The species", new_text, fixed = TRUE)
  new_text <- gsub("pest's", "species'", new_text, fixed = TRUE)
  new_text <- gsub("can the pest", "can the species", new_text, fixed = TRUE)
  new_text <- gsub("Can the pest", "Can the species", new_text, fixed = TRUE)

  if (new_text != old_text) {
    update_query <- sprintf(
      "UPDATE pathwayQuestions SET question = '%s' WHERE idPathQuestion = %d",
      gsub("'", "''", new_text),
      path_q$idPathQuestion[i]
    )
    dbExecute(con, update_query)

    cat(sprintf("UPDATED: [%s%s]\n", path_q$group[i], path_q$number[i]))
    cat(sprintf("  FROM: %s\n", old_text))
    cat(sprintf("  TO:   %s\n\n", new_text))
    updates_pathway_questions <- updates_pathway_questions + 1
  }
}

#------------------------------------------------------------------------------
# PATHWAY QUESTIONS - Answer options
#------------------------------------------------------------------------------
cat("--- Pathway Questions: Answer Options ---\n\n")

path_opts <- dbGetQuery(con, "SELECT idPathQuestion, [group], number, list FROM pathwayQuestions")

for (i in seq_len(nrow(path_opts))) {
  old_list <- path_opts$list[i]

  if (!grepl("pest", old_list, ignore.case = TRUE)) {
    next
  }

  opts <- fromJSON(old_list)

  updated <- FALSE
  for (j in seq_along(opts$text)) {
    old_opt_text <- opts$text[j]
    new_opt_text <- old_opt_text
    new_opt_text <- gsub("the pest", "the species", new_opt_text, fixed = TRUE)
    new_opt_text <- gsub("The pest", "The species", new_opt_text, fixed = TRUE)
    new_opt_text <- gsub("pest's", "species'", new_opt_text, fixed = TRUE)

    if (new_opt_text != old_opt_text) {
      opts$text[j] <- new_opt_text
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
    updates_pathway_options <- updates_pathway_options + 1
  }
}

dbDisconnect(con)

cat("\n=== pest -> species Replacement Complete ===\n")
cat(sprintf("Main question text updates: %d\n", updates_main_questions))
cat(sprintf("Main answer option updates: %d\n", updates_main_options))
cat(sprintf("Pathway question text updates: %d\n", updates_pathway_questions))
cat(sprintf("Pathway answer option updates: %d\n", updates_pathway_options))
cat(sprintf("TOTAL: %d updates\n",
            updates_main_questions + updates_main_options +
            updates_pathway_questions + updates_pathway_options))

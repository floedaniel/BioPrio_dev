# scripts/terminology_migration/2_update_main_questions.R
# Update main questions terminology for BioPRIO (terrestrial invertebrates)
# CRITICAL: Only change text, NEVER change points values

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"

# Connect to database
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Terminology Migration: Main Questions ===\n")
cat("Database:", DB_FILE, "\n\n")

# Function to update question text
update_question <- function(con, group_val, number_val, old_text, new_text) {
  # Get current question
  query <- sprintf(
    "SELECT idQuestion, question FROM questions WHERE [group] = '%s' AND number = '%s'",
    group_val, number_val
  )
  q <- dbGetQuery(con, query)

  if (nrow(q) == 0) {
    cat(sprintf("WARNING: Question %s%s not found\n", group_val, number_val))
    return(FALSE)
  }

  current_question <- q$question[1]

  # Check if old_text exists in current question
  if (!grepl(old_text, current_question, fixed = TRUE)) {
    cat(sprintf("SKIP: [%s%s] Pattern '%s' not found in question\n",
                group_val, number_val, old_text))
    cat(sprintf("       Current text: %s\n", current_question))
    return(FALSE)
  }

  # Replace text
  new_question <- gsub(old_text, new_text, current_question, fixed = TRUE)

  # Update database
  update_query <- sprintf(
    "UPDATE questions SET question = '%s' WHERE idQuestion = %d",
    gsub("'", "''", new_question),  # Escape single quotes
    q$idQuestion[1]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s]\n", group_val, number_val))
  cat(sprintf("  FROM: %s\n", current_question))
  cat(sprintf("  TO:   %s\n\n", new_question))
  return(TRUE)
}

# Function to update answer option text in JSON list column
update_answer_option <- function(con, group_val, number_val, old_text, new_text) {
  # Get current question with list
  query <- sprintf(
    "SELECT idQuestion, list FROM questions WHERE [group] = '%s' AND number = '%s'",
    group_val, number_val
  )
  q <- dbGetQuery(con, query)

  if (nrow(q) == 0) {
    cat(sprintf("WARNING: Question %s%s not found\n", group_val, number_val))
    return(FALSE)
  }

  current_list <- q$list[1]

  # Check if old_text exists in list JSON
  if (!grepl(old_text, current_list, fixed = TRUE)) {
    cat(sprintf("SKIP: [%s%s] Pattern '%s' not found in answer options\n",
                group_val, number_val, old_text))
    cat(sprintf("       Current list: %s\n", current_list))
    return(FALSE)
  }

  # Parse JSON, update text values only (NOT points), and serialize back
  opts <- fromJSON(current_list)

  # Find and update matching text entries
  updated <- FALSE
  for (i in seq_along(opts$text)) {
    if (grepl(old_text, opts$text[i], fixed = TRUE)) {
      opts$text[i] <- gsub(old_text, new_text, opts$text[i], fixed = TRUE)
      updated <- TRUE
    }
  }

  if (!updated) {
    cat(sprintf("SKIP: [%s%s] No text entries matched '%s'\n",
                group_val, number_val, old_text))
    return(FALSE)
  }

  # Serialize back to JSON - preserve original structure
  # Build JSON manually to ensure points values are preserved exactly
  json_parts <- character(nrow(opts))
  for (i in seq_len(nrow(opts))) {
    json_parts[i] <- sprintf(
      '{"opt": "%s", "text": "%s", "points": %s}',
      opts$opt[i],
      gsub('"', '\\"', opts$text[i]),  # Escape double quotes in text
      opts$points[i]
    )
  }
  new_list <- paste0("[", paste(json_parts, collapse = ","), "]")

  # Update database
  update_query <- sprintf(
    "UPDATE questions SET list = '%s' WHERE idQuestion = %d",
    gsub("'", "''", new_list),  # Escape single quotes
    q$idQuestion[1]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s] answer options\n", group_val, number_val))
  cat(sprintf("  FROM: %s\n", current_list))
  cat(sprintf("  TO:   %s\n\n", new_list))
  return(TRUE)
}

# Track updates
updates_made <- 0

cat("--- Updating Question Text ---\n\n")

# 1. EST2: "host plants grow or are cultivated" -> "suitable hosts, prey, or habitats occur"
if (update_question(con, "EST", "2",
                    "host plants grow or are cultivated",
                    "suitable hosts, prey, or habitats occur")) {
  updates_made <- updates_made + 1
}

cat("--- Updating Answer Option Text ---\n\n")

# 2. IMP2.3: "plant production sector" -> "plant production sector or ecosystem"
if (update_answer_option(con, "IMP", "2.3",
                         "plant production sector",
                         "plant production sector or ecosystem")) {
  updates_made <- updates_made + 1
}

# 3. IMP4.3: "culturally important plants" -> "culturally important plants or other organisms"
if (update_answer_option(con, "IMP", "4.3",
                         "culturally important plants",
                         "culturally important plants or other organisms")) {
  updates_made <- updates_made + 1
}

# Close connection
dbDisconnect(con)

cat("=== Migration Complete ===\n")
cat(sprintf("Total updates made: %d\n", updates_made))
cat("\nNote: 'PRA area' terminology retained as standard pest risk assessment term.\n")
cat("      MAN2 correctly references 'European Union' (unchanged).\n")

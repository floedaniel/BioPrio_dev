# scripts/terminology_migration/3_update_pathway_questions.R
# Update pathway questions terminology for BioPRIO (terrestrial invertebrates)
# CRITICAL: Only change text, NEVER change points values

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"

# Connect to database
con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Terminology Migration: Pathway Questions ===\n")
cat("Database:", DB_FILE, "\n\n")

# Function to update pathway question text
update_pathway_question <- function(con, group_val, number_val, old_text, new_text) {
  # Get current question
  query <- sprintf(
    "SELECT idPathQuestion, question FROM pathwayQuestions WHERE [group] = '%s' AND number = '%s'",
    group_val, number_val
  )
  q <- dbGetQuery(con, query)

  if (nrow(q) == 0) {
    cat(sprintf("WARNING: Pathway question %s%s not found\n", group_val, number_val))
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
    "UPDATE pathwayQuestions SET question = '%s' WHERE idPathQuestion = %d",
    gsub("'", "''", new_question),  # Escape single quotes
    q$idPathQuestion[1]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s]\n", group_val, number_val))
  cat(sprintf("  FROM: %s\n", current_question))
  cat(sprintf("  TO:   %s\n\n", new_question))
  return(TRUE)
}

# Function to update pathway answer option text in JSON list column
update_pathway_answer_option <- function(con, group_val, number_val, old_text, new_text) {
  # Get current question with list
  query <- sprintf(
    "SELECT idPathQuestion, list FROM pathwayQuestions WHERE [group] = '%s' AND number = '%s'",
    group_val, number_val
  )
  q <- dbGetQuery(con, query)

  if (nrow(q) == 0) {
    cat(sprintf("WARNING: Pathway question %s%s not found\n", group_val, number_val))
    return(FALSE)
  }

  current_list <- q$list[1]

  # Check if old_text exists in list JSON
  if (!grepl(old_text, current_list, fixed = TRUE)) {
    cat(sprintf("SKIP: [%s%s] Pattern '%s' not found in answer options\n",
                group_val, number_val, old_text))
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
    "UPDATE pathwayQuestions SET list = '%s' WHERE idPathQuestion = %d",
    gsub("'", "''", new_list),  # Escape single quotes
    q$idPathQuestion[1]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s] answer options\n", group_val, number_val))
  cat(sprintf("  FROM: %s\n", current_list))
  cat(sprintf("  TO:   %s\n\n", new_list))
  return(TRUE)
}

# Track updates
updates_made <- 0

cat("--- Checking Pathway Questions for 'host plant commodity' ---\n\n")

# Terminology change: "host plant commodity" -> "host material or commodity"
# This applies to ENT2A, ENT2B, ENT3 according to the migration plan

# Check ENT2A question text
if (update_pathway_question(con, "ENT", "2A",
                            "host plant commodity",
                            "host material or commodity")) {
  updates_made <- updates_made + 1
}

# Check ENT2A answer options
if (update_pathway_answer_option(con, "ENT", "2A",
                                  "host plant commodity",
                                  "host material or commodity")) {
  updates_made <- updates_made + 1
}

# Check ENT2B question text
if (update_pathway_question(con, "ENT", "2B",
                            "host plant commodity",
                            "host material or commodity")) {
  updates_made <- updates_made + 1
}

# Check ENT2B answer options
if (update_pathway_answer_option(con, "ENT", "2B",
                                  "host plant commodity",
                                  "host material or commodity")) {
  updates_made <- updates_made + 1
}

# Check ENT3 question text
if (update_pathway_question(con, "ENT", "3",
                            "host plant commodity",
                            "host material or commodity")) {
  updates_made <- updates_made + 1
}

# Check ENT3 answer options
if (update_pathway_answer_option(con, "ENT", "3",
                                  "host plant commodity",
                                  "host material or commodity")) {
  updates_made <- updates_made + 1
}

# Verify points values remain unchanged
cat("--- Verifying Points Values (should be unchanged) ---\n\n")

verify_query <- "SELECT [group], number, list FROM pathwayQuestions WHERE number IN ('2A', '2B', '3', '4')"
verify_result <- dbGetQuery(con, verify_query)

for (i in seq_len(nrow(verify_result))) {
  cat(sprintf("[%s%s] Points: ", verify_result$group[i], verify_result$number[i]))
  opts <- fromJSON(verify_result$list[i])
  cat(paste(opts$points, collapse = ", "), "\n")
}

# Close connection
dbDisconnect(con)

cat("\n=== Migration Complete ===\n")
cat(sprintf("Total updates made: %d\n", updates_made))
cat("\nNote: ENT2A and ENT2B do not contain 'host plant commodity' in their text.\n")
cat("      Only ENT3 question text was updated.\n")

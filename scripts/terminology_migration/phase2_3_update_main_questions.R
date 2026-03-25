# scripts/terminology_migration/phase2_3_update_main_questions.R
# Update specific main question wording for BioPRIO terrestrial invertebrates
# Based on reformulated_questions.Rmd proposals
# CRITICAL: Only change text, NEVER change points values

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"

con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Phase 2: Main Question Terminology Updates ===\n")
cat("Database:", DB_FILE, "\n\n")

updates_made <- 0

# Helper function to update question text with full replacement
update_question_full <- function(con, group_val, number_val, new_question) {
  query <- sprintf(
    "SELECT idQuestion, question FROM questions WHERE [group] = '%s' AND number = '%s'",
    group_val, number_val
  )
  q <- dbGetQuery(con, query)

  if (nrow(q) == 0) {
    cat(sprintf("WARNING: Question %s%s not found\n", group_val, number_val))
    return(FALSE)
  }

  old_question <- q$question[1]

  if (old_question == new_question) {
    cat(sprintf("SKIP: [%s%s] Already matches target text\n", group_val, number_val))
    return(FALSE)
  }

  update_query <- sprintf(
    "UPDATE questions SET question = '%s' WHERE idQuestion = %d",
    gsub("'", "''", new_question),
    q$idQuestion[1]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s]\n", group_val, number_val))
  cat(sprintf("  FROM: %s\n", old_question))
  cat(sprintf("  TO:   %s\n\n", new_question))
  return(TRUE)
}

# Helper function to update answer option text
update_answer_option_full <- function(con, group_val, number_val, opt_letter, new_text) {
  query <- sprintf(
    "SELECT idQuestion, list FROM questions WHERE [group] = '%s' AND number = '%s'",
    group_val, number_val
  )
  q <- dbGetQuery(con, query)

  if (nrow(q) == 0) {
    cat(sprintf("WARNING: Question %s%s not found\n", group_val, number_val))
    return(FALSE)
  }

  opts <- fromJSON(q$list[1])

  # Find the option by letter
  idx <- which(opts$opt == opt_letter)
  if (length(idx) == 0) {
    cat(sprintf("WARNING: Option '%s' not found in %s%s\n", opt_letter, group_val, number_val))
    return(FALSE)
  }

  old_text <- opts$text[idx]
  if (old_text == new_text) {
    cat(sprintf("SKIP: [%s%s] option %s already matches\n", group_val, number_val, opt_letter))
    return(FALSE)
  }

  opts$text[idx] <- new_text

  # Rebuild JSON
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
    q$idQuestion[1]
  )
  dbExecute(con, update_query)

  cat(sprintf("UPDATED: [%s%s] option %s\n", group_val, number_val, opt_letter))
  cat(sprintf("  FROM: %s\n", old_text))
  cat(sprintf("  TO:   %s\n\n", new_text))
  return(TRUE)
}

#------------------------------------------------------------------------------
# ESTABLISHMENT QUESTIONS
#------------------------------------------------------------------------------
cat("--- ESTABLISHMENT Questions ---\n\n")

# EST1: Add seasonal qualifier and change "production conditions" to "land use conditions"
if (update_question_full(con, "EST", "1",
    "Could the species reproduce and overwinter (or persist through unfavourable seasons) in the risk assessment area, taking into account the prevailing climate and land use conditions?")) {
  updates_made <- updates_made + 1
}

# EST2: Rephrase for clarity
if (update_question_full(con, "EST", "2",
    "How large an area of suitable hosts, prey organisms, or habitats does the risk assessment area contain?")) {
  updates_made <- updates_made + 1
}

# EST4: "characteristics" -> "biological or ecological traits", "assist" -> "facilitate"
if (update_question_full(con, "EST", "4",
    "Does the species possess biological or ecological traits that could facilitate its establishment or spread in new areas?")) {
  updates_made <- updates_made + 1
}

# EST4 answer options - update to match new terminology
if (update_answer_option_full(con, "EST", "4", "a", "No it does not")) {
  updates_made <- updates_made + 1
}
if (update_answer_option_full(con, "EST", "4", "b", "It has traits that could facilitate to some extent")) {
  updates_made <- updates_made + 1
}
if (update_answer_option_full(con, "EST", "4", "c", "It has traits that could facilitate to a great extent")) {
  updates_made <- updates_made + 1
}
if (update_answer_option_full(con, "EST", "4", "d", "It has traits that could facilitate to a very great extent")) {
  updates_made <- updates_made + 1
}

#------------------------------------------------------------------------------
# IMPACT QUESTIONS
#------------------------------------------------------------------------------
cat("--- IMPACT Questions ---\n\n")

# IMP3: Add "and native biodiversity", rephrase
if (update_question_full(con, "IMP", "3",
    "How significant would the species' direct impacts on natural ecosystems and native biodiversity be in the risk assessment area?")) {
  updates_made <- updates_made + 1
}

# IMP4.1, IMP4.2, IMP4.3: Add "public health"
if (update_question_full(con, "IMP", "4.1",
    "Would the species have the following environmental, public health, or social impacts in the risk assessment area?")) {
  updates_made <- updates_made + 1
}

if (update_question_full(con, "IMP", "4.2",
    "Would the species have the following environmental, public health, or social impacts in the risk assessment area?")) {
  updates_made <- updates_made + 1
}

if (update_question_full(con, "IMP", "4.3",
    "Would the species have the following environmental, public health, or social impacts in the risk assessment area?")) {
  updates_made <- updates_made + 1
}

#------------------------------------------------------------------------------
# MANAGEMENT QUESTIONS
#------------------------------------------------------------------------------
cat("--- MANAGEMENT Questions ---\n\n")

# MAN3: Add inspection context
if (update_question_full(con, "MAN", "3",
    "How difficult is it to detect the species during inspections of commodities or conveyances?")) {
  updates_made <- updates_made + 1
}

# MAN4: Add "if established"
if (update_question_full(con, "MAN", "4",
    "How difficult would it be to eradicate the species from the risk assessment area if established?")) {
  updates_made <- updates_made + 1
}

# MAN5: Add "and monitor"
if (update_question_full(con, "MAN", "5",
    "How difficult would it be to survey and monitor the species' occurrence in the risk assessment area?")) {
  updates_made <- updates_made + 1
}

dbDisconnect(con)

cat("\n=== Main Question Updates Complete ===\n")
cat(sprintf("Total updates made: %d\n", updates_made))

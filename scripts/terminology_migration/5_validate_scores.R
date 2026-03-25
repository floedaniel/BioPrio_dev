# scripts/terminology_migration/5_validate_scores.R
# Task 5: Validate that all points values in JSON list columns are unchanged
# after terminology migration

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"

# Define expected point values for each question
expected_points <- list(
  # Main questions
  ENT1 = c(1, 2, 3),
  EST1 = c(0, 1.5, 4.5, 9),
  EST2 = c(0, 1, 2, 3, 4),
  EST3 = c(0, 1, 2, 3),
  EST4 = c(0, 1, 2, 3),
  IMP1 = c(0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6),
  `IMP2.1` = c(1),
  `IMP2.2` = c(1),
  `IMP2.3` = c(1),
  IMP3 = c(0, 2, 4, 6),
  `IMP4.1` = c(1),
  `IMP4.2` = c(1),
  `IMP4.3` = c(1),
  MAN1 = c(0, 2, 4),
  MAN2 = c(0, 2, 3),
  MAN3 = c(0, 1, 2),
  MAN4 = c(0, 2, 3, 4),
  MAN5 = c(0, 1, 2, 3),
  # Pathway questions
  ENT2A = c(0, 0.5, 1, 2, 3),
  ENT2B = c(0, 0.5, 1, 2, 3),
  ENT3 = c(0, 1, 2, 3),
  ENT4 = c(0, 0.5, 1, 2, 3)
)

cat("=== BioPRIO Score Validation ===\n")
cat("Verifying all points values are unchanged after terminology migration\n\n")

con <- dbConnect(RSQLite::SQLite(), DB_FILE)

all_passed <- TRUE
failures <- character(0)

# Validate main questions
cat("Checking main questions table...\n")
questions <- dbGetQuery(con, "SELECT idQuestion, [group], number, list FROM questions")

for (i in seq_len(nrow(questions))) {
  question_id <- paste0(questions$group[i], questions$number[i])
  opts <- fromJSON(questions$list[i])
  actual_points <- as.numeric(opts$points)

  if (question_id %in% names(expected_points)) {
    expected <- expected_points[[question_id]]
    if (identical(actual_points, expected)) {
      cat(sprintf("  [OK] %s: %s\n", question_id, paste(actual_points, collapse = ", ")))
    } else {
      all_passed <- FALSE
      msg <- sprintf("  [FAIL] %s: Expected [%s], Got [%s]",
                     question_id,
                     paste(expected, collapse = ", "),
                     paste(actual_points, collapse = ", "))
      cat(msg, "\n")
      failures <- c(failures, msg)
    }
  } else {
    all_passed <- FALSE
    msg <- sprintf("  [WARN] %s: No expected values defined, found [%s]",
                   question_id,
                   paste(actual_points, collapse = ", "))
    cat(msg, "\n")
    failures <- c(failures, msg)
  }
}

# Validate pathway questions
cat("\nChecking pathway questions table...\n")
path_questions <- dbGetQuery(con, "SELECT idPathQuestion, [group], number, list FROM pathwayQuestions")

for (i in seq_len(nrow(path_questions))) {
  question_id <- paste0(path_questions$group[i], path_questions$number[i])
  opts <- fromJSON(path_questions$list[i])
  actual_points <- as.numeric(opts$points)

  if (question_id %in% names(expected_points)) {
    expected <- expected_points[[question_id]]
    if (identical(actual_points, expected)) {
      cat(sprintf("  [OK] %s: %s\n", question_id, paste(actual_points, collapse = ", ")))
    } else {
      all_passed <- FALSE
      msg <- sprintf("  [FAIL] %s: Expected [%s], Got [%s]",
                     question_id,
                     paste(expected, collapse = ", "),
                     paste(actual_points, collapse = ", "))
      cat(msg, "\n")
      failures <- c(failures, msg)
    }
  } else {
    all_passed <- FALSE
    msg <- sprintf("  [WARN] %s: No expected values defined, found [%s]",
                   question_id,
                   paste(actual_points, collapse = ", "))
    cat(msg, "\n")
    failures <- c(failures, msg)
  }
}

dbDisconnect(con)

# Final result
cat("\n")
cat("=" , rep("=", 40), "\n", sep = "")
if (all_passed) {
  cat("PASS: All points values match expected values.\n")
  cat("Score integrity verified - terminology migration did not affect scoring.\n")
} else {
  cat("FAIL: Some points values do not match expected values.\n")
  cat("\nFailures:\n")
  for (f in failures) {
    cat(f, "\n")
  }
}
cat("=" , rep("=", 40), "\n", sep = "")

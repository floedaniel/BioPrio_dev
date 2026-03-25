# scripts/terminology_migration/phase2_5_validate_changes.R
# Validate phase 2 terminology changes
# Verify: 1) Points unchanged, 2) "pest" fully replaced, 3) Key terms present

library(DBI)
library(RSQLite)
library(jsonlite)

DB_FILE <- "databases/clean_database/clean.db"

con <- dbConnect(RSQLite::SQLite(), DB_FILE)

cat("=== BioPRIO Phase 2: Validation ===\n")
cat("Database:", DB_FILE, "\n\n")

errors <- 0
warnings <- 0

#------------------------------------------------------------------------------
# 1. CHECK THAT "pest" IS FULLY REPLACED (except where intentional)
#------------------------------------------------------------------------------
cat("--- Check 1: 'pest' should be replaced with 'species' ---\n\n")

# Main questions
main_q <- dbGetQuery(con, "SELECT [group], number, question, list FROM questions")
for (i in seq_len(nrow(main_q))) {
  if (grepl("\\bpest\\b", main_q$question[i], ignore.case = TRUE)) {
    cat(sprintf("ERROR: [%s%s] still contains 'pest' in question\n",
                main_q$group[i], main_q$number[i]))
    cat(sprintf("       %s\n", main_q$question[i]))
    errors <- errors + 1
  }
  if (grepl("\\bpest\\b", main_q$list[i], ignore.case = TRUE)) {
    # Check if it's "other pests" which is acceptable in IMP2.2
    if (!(main_q$group[i] == "IMP" && main_q$number[i] == "2.2" &&
          grepl("other pests", main_q$list[i]))) {
      cat(sprintf("ERROR: [%s%s] still contains 'pest' in options\n",
                  main_q$group[i], main_q$number[i]))
      errors <- errors + 1
    }
  }
}

# Pathway questions
path_q <- dbGetQuery(con, "SELECT [group], number, question, list FROM pathwayQuestions")
for (i in seq_len(nrow(path_q))) {
  if (grepl("\\bpest\\b", path_q$question[i], ignore.case = TRUE)) {
    cat(sprintf("ERROR: [%s%s] (pathway) still contains 'pest' in question\n",
                path_q$group[i], path_q$number[i]))
    errors <- errors + 1
  }
  if (grepl("\\bpest\\b", path_q$list[i], ignore.case = TRUE)) {
    cat(sprintf("ERROR: [%s%s] (pathway) still contains 'pest' in options\n",
                path_q$group[i], path_q$number[i]))
    errors <- errors + 1
  }
}

if (errors == 0) {
  cat("PASS: No remaining 'pest' terminology found (except IMP2.2 'other pests')\n\n")
}

#------------------------------------------------------------------------------
# 2. VERIFY POINTS VALUES ARE UNCHANGED
#------------------------------------------------------------------------------
cat("--- Check 2: Points values must be unchanged ---\n\n")

# Expected points for main questions (from original FinnPRIO)
expected_points <- list(
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
  MAN5 = c(0, 1, 2, 3)
)

for (i in seq_len(nrow(main_q))) {
  key <- paste0(main_q$group[i], main_q$number[i])
  if (!key %in% names(expected_points)) {
    cat(sprintf("WARNING: Unknown question %s, cannot validate points\n", key))
    warnings <- warnings + 1
    next
  }

  opts <- fromJSON(main_q$list[i])
  actual_points <- opts$points
  expected <- expected_points[[key]]

  if (!identical(as.numeric(actual_points), as.numeric(expected))) {
    cat(sprintf("ERROR: [%s] Points mismatch!\n", key))
    cat(sprintf("       Expected: %s\n", paste(expected, collapse = ", ")))
    cat(sprintf("       Actual:   %s\n", paste(actual_points, collapse = ", ")))
    errors <- errors + 1
  }
}

# Expected points for pathway questions
expected_pathway_points <- list(
  ENT2A = c(0, 0.5, 1, 2, 3),
  ENT2B = c(0, 0.5, 1, 2, 3),
  ENT3 = c(0, 1, 2, 3),
  ENT4 = c(0, 0.5, 1, 2, 3)
)

for (i in seq_len(nrow(path_q))) {
  key <- paste0(path_q$group[i], path_q$number[i])
  if (!key %in% names(expected_pathway_points)) {
    next
  }

  opts <- fromJSON(path_q$list[i])
  actual_points <- opts$points
  expected <- expected_pathway_points[[key]]

  if (!identical(as.numeric(actual_points), as.numeric(expected))) {
    cat(sprintf("ERROR: [%s] (pathway) Points mismatch!\n", key))
    cat(sprintf("       Expected: %s\n", paste(expected, collapse = ", ")))
    cat(sprintf("       Actual:   %s\n", paste(actual_points, collapse = ", ")))
    errors <- errors + 1
  }
}

if (errors == 0) {
  cat("PASS: All points values unchanged\n\n")
}

#------------------------------------------------------------------------------
# 3. VERIFY KEY TERMINOLOGY IS PRESENT
#------------------------------------------------------------------------------
cat("--- Check 3: Key terminology verification ---\n\n")

checks <- list(
  list(group = "EST", number = "1", pattern = "land use conditions",
       desc = "EST1 contains 'land use conditions'"),
  list(group = "EST", number = "1", pattern = "persist through unfavourable seasons",
       desc = "EST1 contains seasonal qualifier"),
  list(group = "EST", number = "2", pattern = "prey organisms",
       desc = "EST2 contains 'prey organisms'"),
  list(group = "EST", number = "4", pattern = "biological or ecological traits",
       desc = "EST4 contains 'biological or ecological traits'"),
  list(group = "IMP", number = "3", pattern = "native biodiversity",
       desc = "IMP3 contains 'native biodiversity'"),
  list(group = "IMP", number = "4.1", pattern = "public health",
       desc = "IMP4.1 contains 'public health'"),
  list(group = "MAN", number = "3", pattern = "commodities or conveyances",
       desc = "MAN3 contains 'commodities or conveyances'"),
  list(group = "MAN", number = "4", pattern = "if established",
       desc = "MAN4 contains 'if established'"),
  list(group = "MAN", number = "5", pattern = "survey and monitor",
       desc = "MAN5 contains 'survey and monitor'")
)

for (check in checks) {
  query <- sprintf(
    "SELECT question FROM questions WHERE [group] = '%s' AND number = '%s'",
    check$group, check$number
  )
  result <- dbGetQuery(con, query)

  if (nrow(result) == 0) {
    cat(sprintf("ERROR: Question %s%s not found\n", check$group, check$number))
    errors <- errors + 1
    next
  }

  if (grepl(check$pattern, result$question[1], fixed = TRUE)) {
    cat(sprintf("PASS: %s\n", check$desc))
  } else {
    cat(sprintf("ERROR: %s - NOT FOUND\n", check$desc))
    cat(sprintf("       Current: %s\n", result$question[1]))
    errors <- errors + 1
  }
}

# Check pathway questions
pathway_checks <- list(
  list(group = "ENT", number = "2A", pattern = "to the risk assessment area",
       desc = "ENT2A contains 'to the risk assessment area'"),
  list(group = "ENT", number = "3", pattern = "conveyances",
       desc = "ENT3 contains 'conveyances'"),
  list(group = "ENT", number = "4", pattern = "prey organism",
       desc = "ENT4 contains 'prey organism'")
)

cat("\n")
for (check in pathway_checks) {
  query <- sprintf(
    "SELECT question FROM pathwayQuestions WHERE [group] = '%s' AND number = '%s'",
    check$group, check$number
  )
  result <- dbGetQuery(con, query)

  if (nrow(result) == 0) {
    cat(sprintf("ERROR: Pathway question %s%s not found\n", check$group, check$number))
    errors <- errors + 1
    next
  }

  if (grepl(check$pattern, result$question[1], fixed = TRUE)) {
    cat(sprintf("PASS: %s\n", check$desc))
  } else {
    cat(sprintf("ERROR: %s - NOT FOUND\n", check$desc))
    cat(sprintf("       Current: %s\n", result$question[1]))
    errors <- errors + 1
  }
}

dbDisconnect(con)

#------------------------------------------------------------------------------
# SUMMARY
#------------------------------------------------------------------------------
cat("\n=== Validation Summary ===\n")
cat(sprintf("Errors:   %d\n", errors))
cat(sprintf("Warnings: %d\n", warnings))

if (errors == 0) {
  cat("\nVALIDATION PASSED - Phase 2 migration successful!\n")
} else {
  cat("\nVALIDATION FAILED - Please review errors above.\n")
}

# scripts/terminology_migration/phase2_B_review_host_plant.R
# Generate review document for "host plant" contexts

INPUT_FILE <- "www/instructions.html"
OUTPUT_FILE <- "scripts/terminology_migration/phase2_B_host_plant_review.md"

cat("=== Generating Phase B Review Document ===\n\n")

# Read file
content <- readLines(INPUT_FILE, encoding = "latin1", warn = FALSE)

# Find lines containing "host plant"
matches <- grep("host plant", content, ignore.case = TRUE)

cat(sprintf("Found %d lines containing 'host plant'\n\n", length(matches)))

# Open output file
sink(OUTPUT_FILE)

cat("# Phase B Review: 'host plant' Terminology\n\n")
cat("This document lists all occurrences of 'host plant' in instructions.html.\n")
cat("Review each context and decide on appropriate replacement for terrestrial invertebrates.\n\n")
cat("## Suggested Replacements\n\n")
cat("| Original | Possible Replacement |\n")
cat("|----------|---------------------|\n")
cat("| host plant | host organism, prey, or habitat |\n")
cat("| host plants | hosts, prey organisms, or habitats |\n")
cat("| host plant commodity | host material or commodity |\n")
cat("| living host plant | living host |\n")
cat("\n---\n\n")

cat(sprintf("## All Occurrences (%d total)\n\n", length(matches)))

for (i in seq_along(matches)) {
  line_num <- matches[i]
  line_content <- content[line_num]

  # Strip HTML tags
  clean_content <- gsub("<[^>]*>", "", line_content)
  clean_content <- gsub("&nbsp;", " ", clean_content)
  clean_content <- gsub("&amp;", "&", clean_content)
  clean_content <- gsub("\\s+", " ", clean_content)
  clean_content <- trimws(clean_content)

  # Skip empty lines
  if (nchar(clean_content) < 5) next

  cat(sprintf("### %d. Line %d\n\n", i, line_num))
  cat("**Original text:**\n")
  cat(sprintf("> %s\n\n", clean_content))
  cat("**Proposed change:** *(fill in)*\n\n")
  cat("---\n\n")
}

sink()

cat("Review document generated:", OUTPUT_FILE, "\n")

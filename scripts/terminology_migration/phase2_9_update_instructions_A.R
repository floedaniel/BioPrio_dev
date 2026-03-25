# scripts/terminology_migration/phase2_9_update_instructions_A.R
# Phase A: Simple terminology replacements in instructions.html
# - "pest" → "species"
# - "PRA area" → "risk assessment area"
# - "pest´s" → "species'" (with special apostrophe)
# - "pest's" → "species'" (with regular apostrophe)

INPUT_FILE <- "www/instructions.html"
OUTPUT_FILE <- "www/instructions.html"
BACKUP_FILE <- "www/instructions_backup_phase2.html"

cat("=== BioPRIO Phase 2A: Instructions Simple Replacements ===\n\n")

# Read file
cat("Reading:", INPUT_FILE, "\n")
content <- readLines(INPUT_FILE, encoding = "latin1", warn = FALSE)
original_content <- content

# Create backup
cat("Creating backup:", BACKUP_FILE, "\n")
writeLines(original_content, BACKUP_FILE, useBytes = TRUE)

# Count occurrences before
count_pest_before <- sum(gregexpr("pest", paste(content, collapse = "\n"), ignore.case = FALSE)[[1]] > 0)
count_pra_before <- sum(gregexpr("PRA area", paste(content, collapse = "\n"), fixed = TRUE)[[1]] > 0)

cat("\n--- Before Replacement ---\n")
cat("'pest' occurrences (approx):", length(grep("pest", content, ignore.case = FALSE)), "lines\n")
cat("'PRA area' occurrences (approx):", length(grep("PRA area", content, fixed = TRUE)), "lines\n")

# Perform replacements
cat("\n--- Performing Replacements ---\n")

# 1. "PRA area" → "risk assessment area" (do this first, before pest replacements)
content <- gsub("PRA area", "risk assessment area", content, fixed = TRUE)
cat("Replaced: 'PRA area' → 'risk assessment area'\n")

# 2. "the pest" → "the species" (most common pattern)
content <- gsub("the pest", "the species", content, fixed = TRUE)
cat("Replaced: 'the pest' → 'the species'\n")

# 3. "The pest" → "The species" (sentence start)
content <- gsub("The pest", "The species", content, fixed = TRUE)
cat("Replaced: 'The pest' → 'The species'\n")

# 4. "a pest" → "a species"
content <- gsub("a pest", "a species", content, fixed = TRUE)
cat("Replaced: 'a pest' → 'a species'\n")

# 5. "pest´s" → "species'" (special apostrophe used in document)
content <- gsub("pest´s", "species'", content, fixed = TRUE)
cat("Replaced: 'pest´s' → 'species''\n")

# 6. "pest's" → "species'" (regular apostrophe)
content <- gsub("pest's", "species'", content, fixed = TRUE)
cat("Replaced: 'pest's' → 'species''\n")

# 7. "assessed pest" → "assessed species"
content <- gsub("assessed pest", "assessed species", content, fixed = TRUE)
cat("Replaced: 'assessed pest' → 'assessed species'\n")

# 8. "one pest" → "one species"
content <- gsub("one pest", "one species", content, fixed = TRUE)
cat("Replaced: 'one pest' → 'one species'\n")

# 9. Handle "pest insects" specifically - keep as is or change to "species"
# This appears in the intentional introduction context
# "biological control agents and pest insects" - we'll handle this in Phase B

# 10. " pest " (standalone with spaces) → " species "
content <- gsub(" pest ", " species ", content, fixed = TRUE)
cat("Replaced: ' pest ' → ' species '\n")

# 11. " pest<" (before HTML tag)
content <- gsub(" pest<", " species<", content, fixed = TRUE)
cat("Replaced: ' pest<' → ' species<'\n")

# 12. ">pest " (after HTML tag)
content <- gsub(">pest ", ">species ", content, fixed = TRUE)
cat("Replaced: '>pest ' → '>species '\n")

# Count occurrences after
cat("\n--- After Replacement ---\n")
remaining_pest <- grep("pest", content, ignore.case = FALSE, value = TRUE)
remaining_pest_count <- length(remaining_pest)
cat("Lines still containing 'pest':", remaining_pest_count, "\n")

if (remaining_pest_count > 0 && remaining_pest_count <= 20) {
  cat("\nRemaining 'pest' contexts (for Phase B review):\n")
  for (i in seq_along(remaining_pest)) {
    # Extract just the relevant text around "pest"
    line <- remaining_pest[i]
    # Remove HTML tags for readability
    clean_line <- gsub("<[^>]+>", "", line)
    clean_line <- gsub("\\s+", " ", clean_line)
    clean_line <- trimws(clean_line)
    if (nchar(clean_line) > 100) {
      clean_line <- paste0(substr(clean_line, 1, 100), "...")
    }
    if (nchar(clean_line) > 0) {
      cat(sprintf("  - %s\n", clean_line))
    }
  }
}

# Write output
cat("\n--- Writing Output ---\n")
writeLines(content, OUTPUT_FILE, useBytes = TRUE)
cat("Written to:", OUTPUT_FILE, "\n")

# Summary
cat("\n=== Phase A Complete ===\n")
cat("Backup saved to:", BACKUP_FILE, "\n")
cat("Remaining 'pest' occurrences to review in Phase B:", remaining_pest_count, "\n")

# scripts/terminology_migration/phase2_10_update_instructions_B.R
# Phase B: "host plant" terminology replacements in instructions.html
# Option A: Minimal/simple replacements

INPUT_FILE <- "www/instructions.html"
OUTPUT_FILE <- "www/instructions.html"

cat("=== BioPRIO Phase 2B: Host Plant Replacements ===\n\n")

# Read file
cat("Reading:", INPUT_FILE, "\n")
content <- readLines(INPUT_FILE, encoding = "latin1", warn = FALSE)

# Count before
count_before <- length(grep("host plant", content, ignore.case = FALSE))
cat("Lines with 'host plant' before:", count_before, "\n\n")

cat("--- Performing Replacements ---\n")

# Order matters - do longer/more specific patterns first

# 1. "host plant commodity" → "host material or commodity"
content <- gsub("host plant commodity", "host material or commodity", content, fixed = TRUE)
cat("Replaced: 'host plant commodity' → 'host material or commodity'\n")

# 2. "living host plant" → "living host"
content <- gsub("living host plant", "living host", content, fixed = TRUE)
cat("Replaced: 'living host plant' → 'living host'\n")

# 3. "without host plants" → "without suitable hosts"
content <- gsub("without host plants", "without suitable hosts", content, fixed = TRUE)
cat("Replaced: 'without host plants' → 'without suitable hosts'\n")

# 4. "without a host plant" → "without a suitable host"
content <- gsub("without a host plant", "without a suitable host", content, fixed = TRUE)
cat("Replaced: 'without a host plant' → 'without a suitable host'\n")

# 5. "host plant species" → "host species"
content <- gsub("host plant species", "host species", content, fixed = TRUE)
cat("Replaced: 'host plant species' → 'host species'\n")

# 6. "host plant patches" → "host patches"
content <- gsub("host plant patches", "host patches", content, fixed = TRUE)
cat("Replaced: 'host plant patches' → 'host patches'\n")

# 7. "host plants´" (with special apostrophe) → "hosts'"
content <- gsub("host plants´", "hosts'", content, fixed = TRUE)
cat("Replaced: 'host plants´' → 'hosts''\n")

# 8. "host plants'" → "hosts'"
content <- gsub("host plants'", "hosts'", content, fixed = TRUE)
cat("Replaced: 'host plants'' → 'hosts''\n")

# 9. "host plants" (general) → "suitable hosts"
content <- gsub("host plants", "suitable hosts", content, fixed = TRUE)
cat("Replaced: 'host plants' → 'suitable hosts'\n")

# 10. "Host plants" (sentence start) → "Suitable hosts"
content <- gsub("Host plants", "Suitable hosts", content, fixed = TRUE)
cat("Replaced: 'Host plants' → 'Suitable hosts'\n")

# 11. Remaining "host plant" (singular) → "suitable host"
content <- gsub("host plant", "suitable host", content, fixed = TRUE)
cat("Replaced: 'host plant' → 'suitable host'\n")

# Count after
count_after <- length(grep("host plant", content, ignore.case = FALSE))
cat("\n--- After Replacement ---\n")
cat("Lines with 'host plant' after:", count_after, "\n")

# Write output
cat("\n--- Writing Output ---\n")
writeLines(content, OUTPUT_FILE, useBytes = TRUE)
cat("Written to:", OUTPUT_FILE, "\n")

# Verify the new terms
cat("\n--- Verification ---\n")
cat("'suitable host' occurrences:", length(grep("suitable host", content, fixed = TRUE)), "\n")
cat("'living host' occurrences:", length(grep("living host", content, fixed = TRUE)), "\n")
cat("'host material' occurrences:", length(grep("host material", content, fixed = TRUE)), "\n")

cat("\n=== Phase B Complete ===\n")

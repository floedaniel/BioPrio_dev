# Phase 2.12d: Fix remaining unexpanded phrases in instructions.html

instructions_path <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development/www/instructions.html"

cat("=== Phase 2.12d: Fix remaining in instructions.html ===\n\n")

text <- readLines(instructions_path, warn = FALSE)
text <- paste(text, collapse = "\n")

# Fix remaining patterns
text <- gsub("suitable hosts would be easy",
             "suitable hosts, prey, or habitats would be easy", text)
text <- gsub("suitable hosts or climatic conditions",
             "suitable hosts, prey, habitats, or climatic conditions", text)
text <- gsub("suitable hosts from different",
             "suitable hosts, prey, or habitats from different", text)
text <- gsub("suitable hosts do not occur",
             "suitable hosts, prey, or habitats do not occur", text)
text <- gsub("suitable hosts are produced in greenhouses",
             "suitable hosts, prey, or habitats are present in greenhouses", text)
text <- gsub("suitable hosts are commonly cultivated",
             "suitable hosts, prey, or habitats are commonly present", text)
text <- gsub("suitable hosts are not cultivated",
             "suitable hosts, prey, or habitats are not present", text)
text <- gsub("suitable hosts in regions where",
             "suitable hosts, prey, or habitats in regions where", text)
text <- gsub("suitable hosts considered threatened",
             "suitable hosts, prey, or habitats considered threatened", text)
text <- gsub("eradication of the suitable hosts",
             "eradication of suitable hosts or modification of habitats", text)
text <- gsub("survive outside its suitable hosts",
             "survive outside suitable hosts, prey, or habitats", text)

# Fix special character issue
text <- gsub("suitable hostsÂ´ occurrence",
             "suitable hosts, prey, or habitats' occurrence", text)

# Fix standalone "suitable host." at end of sentence
text <- gsub("without a suitable host\\.",
             "without suitable hosts, prey, or habitats.", text)
text <- gsub("living suitable host\\.",
             "suitable hosts, prey, or habitats.", text)

# Fix double expansions again
text <- gsub(", prey, or habitats, prey, or habitats", ", prey, or habitats", text)

# Count remaining
remaining <- gregexpr("suitable hosts?(?![s,] prey|, prey)", text, perl=TRUE)[[1]]
if(remaining[1] != -1) {
  cat("Remaining unexpanded 'suitable host(s)':", length(remaining), "\n")
}

writeLines(text, instructions_path)
cat("Done!\n")

# Phase 2.12c: Update instructions.html to include prey and habitats

instructions_path <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development/www/instructions.html"

cat("=== Phase 2.12c: Update instructions.html ===\n\n")

# Read file
text <- readLines(instructions_path, warn = FALSE)
text <- paste(text, collapse = "\n")

# Count before
before_host <- length(gregexpr("suitable host", text)[[1]])
before_prey <- length(gregexpr("prey", text)[[1]])
before_habitat <- length(gregexpr("habitat", text)[[1]])

cat(sprintf("Before: suitable host=%d, prey=%d, habitat=%d\n", before_host, before_prey, before_habitat))

# Apply expansions (same patterns as database)

# Pattern 1: General presence/occurrence
text <- gsub("suitable hosts are present", "suitable hosts, prey, or habitats are present", text)
text <- gsub("suitable hosts grow", "suitable hosts, prey, or habitats occur", text)
text <- gsub("suitable hosts occur", "suitable hosts, prey, or habitats occur", text)
text <- gsub("suitable hosts are widespread", "suitable hosts, prey, or habitats are widespread", text)
text <- gsub("suitable hosts are very widespread", "suitable hosts, prey, or habitats are very widespread", text)

# Pattern 2: "suitable hosts that" contexts
text <- gsub("suitable hosts that are considered threatened",
             "suitable hosts, prey, or habitats that are considered threatened", text)
text <- gsub("suitable hosts that occur naturally",
             "suitable hosts, prey, or habitats that occur naturally", text)
text <- gsub("suitable hosts considered threatened",
             "suitable hosts, prey, or habitats considered threatened", text)

# Pattern 3: Threatened/supporting
text <- gsub("All suitable hosts that are considered threatened",
             "All suitable hosts, prey, or habitats that are considered threatened", text)
text <- gsub("suitable hosts supporting reproduction",
             "suitable hosts, prey, or habitats supporting reproduction", text)

# Pattern 4: Distribution/area
text <- gsub("distribution of suitable hosts",
             "distribution of suitable hosts, prey, or habitats", text)
text <- gsub("spatial distribution of suitable hosts",
             "spatial distribution of suitable hosts, prey, or habitats", text)
text <- gsub("production area of the threatened suitable hosts",
             "area where threatened suitable hosts, prey, or habitats occur", text)

# Pattern 5: Survival without
text <- gsub("survive without suitable hosts",
             "survive without suitable hosts, prey, or habitats", text)
text <- gsub("without suitable hosts",
             "without suitable hosts, prey, or habitats", text)

# Pattern 6: Species' suitable hosts contexts
text <- gsub("species's suitable hosts are not produced year-round",
             "species' suitable hosts, prey, or habitats are not present year-round", text)
text <- gsub("species's suitable hosts are produced in greenhouses year-round",
             "species' suitable hosts, prey, or habitats are present year-round", text)
text <- gsub("species's suitable hosts are produced in greenhouses",
             "species' suitable hosts, prey, or habitats are present in controlled environments", text)
text <- gsub("species's suitable hosts are sparsely cultivated",
             "species' suitable hosts, prey, or habitats are sparse", text)
text <- gsub("species's suitable hosts are field crops",
             "species' suitable hosts, prey, or habitats are widespread (e.g., field crops, abundant prey, or common habitats)", text)
text <- gsub("species's suitable hosts are widespread field crops",
             "species' suitable hosts, prey, or habitats are widespread", text)

# Pattern 7: Houseplants context
text <- gsub("suitable hosts are used only as houseplants",
             "suitable hosts are limited to indoor plants, or prey/habitats only exist indoors", text)

# Pattern 8: Growing/spread contexts
text <- gsub("its suitable hosts grow very sparsely",
             "its suitable hosts, prey, or habitats are very sparse", text)
text <- gsub("its suitable hosts are not cultivated",
             "its suitable hosts, prey, or habitats do not occur", text)
text <- gsub("its suitable hosts are commonly cultivated",
             "its suitable hosts, prey, or habitats commonly occur", text)
text <- gsub("its suitable hosts are widespread",
             "its suitable hosts, prey, or habitats are widespread", text)

# Pattern 9: Spread to/from
text <- gsub("spread to suitable hosts growing outdoors",
             "spread to suitable hosts, prey, or habitats outdoors", text)
text <- gsub("on one of its suitable hosts, but a shift",
             "within one type of suitable host, prey, or habitat, but a shift", text)
text <- gsub("shift to another host species",
             "shift to another host, prey, or habitat type", text)

# Pattern 10: Only suitable hosts in regions
text <- gsub("only suitable hosts in regions",
             "only suitable hosts, prey, or habitats in regions", text)
text <- gsub("more than one host species is required",
             "more than one host, prey, or habitat type is required", text)

# Pattern 11: Locate suitable hosts
text <- gsub("locate suitable hosts",
             "locate suitable hosts, prey, or habitats", text)

# Clean up apostrophe issues
text <- gsub("speciesÃ‚Â´s suitable hosts", "species' suitable hosts, prey, or habitats", text)

# Fix double expansions
text <- gsub(", prey, or habitats, prey, or habitats", ", prey, or habitats", text)
text <- gsub("prey, or habitats, prey, or habitats", "prey, or habitats", text)

# Count after
after_host <- length(gregexpr("suitable host", text)[[1]])
after_prey <- length(gregexpr("prey", text)[[1]])
after_habitat <- length(gregexpr("habitat", text)[[1]])

cat(sprintf("After:  suitable host=%d, prey=%d, habitat=%d\n", after_host, after_prey, after_habitat))

# Write file
writeLines(text, instructions_path)

cat("\nDone! instructions.html updated.\n")

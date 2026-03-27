################################################################################
# BioPRIO Species Population Script (GBIF-based)
################################################################################
#
# Populates BioPRIO database with species using GBIF for taxonomy data.
# Adapted from FinnPRIO EPPO scripts for species without EPPO codes (e.g., ants).
#
# Usage:
#   1. Set configuration below (DB_FILE, SPECIES_NAMES, DEFAULT_ASSESSOR_ID)
#   2. Run: source("scripts/populate database/populate_ant_species.R")
#
################################################################################

library(DBI)
library(RSQLite)
library(rgbif)
library(tidyverse)

# =============================================================================
# CONFIGURATION
# =============================================================================

SOURCE_DB  <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development/databases/clean_database/clean.db"
DB_FILE    <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/FinnPrio/BioiPRIO_development/databases/ants/ants.db"

if (!file.exists(SOURCE_DB)) stop("Source database not found: ", SOURCE_DB)
dir.create(dirname(DB_FILE), showWarnings = FALSE, recursive = TRUE)
file.copy(SOURCE_DB, DB_FILE, overwrite = TRUE)

# Species directory - names are derived from folder structure at runtime
SPECIES_DIR <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/Prosjektdata - Dokumenter/VKM Data/27.02.2025_maur_forprosjekt_biologisk_mangfold/data/species"

# Derive species names from folders matching pattern: {GBIF_KEY}_{Genus}_{species}*
# Folders with only a numeric name (no species part) are skipped
folders <- list.dirs(SPECIES_DIR, full.names = FALSE, recursive = FALSE)
SPECIES_NAMES <- folders |>
  grep(pattern = "^\\d+_[A-Z][a-z]+_[a-z]+", value = TRUE) |>
  sub(pattern = "^\\d+_", replacement = "") |>
  strsplit(split = "_") |>
  sapply(function(parts) paste(parts[1], parts[2])) |>
  unique() |>
  sort()

# Default assessor ID - check your assessors table for valid IDs
DEFAULT_ASSESSOR_ID <- 3L

# Taxonomic group and quarantine status defaults
DEFAULT_TAXA_ID <- 1L         # Insects [1INSEC]
DEFAULT_QUARANTINE_ID <- 6L   # Other non-quarantine

# Options
CREATE_ASSESSMENTS <- TRUE
FETCH_DISTRIBUTION <- TRUE

# Re-run behavior: "skip" or "update"
PEST_EXISTS_MODE <- "skip"
ASSESSMENT_EXISTS_MODE <- "skip"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

na_to_default <- function(x, default = "") {
  if (is.null(x) || length(x) == 0 || (length(x) == 1 && is.na(x))) default else x
}

get_gbif_taxonomy <- function(species_name) {
  tryCatch({
    backbone <- rgbif::name_backbone(name = species_name, rank = "species")
    if (is.null(backbone$usageKey) || backbone$matchType == "NONE") return(NULL)

    # Get vernacular names
    vernacular <- tryCatch({
      vn <- rgbif::name_usage(key = backbone$usageKey, data = "vernacularNames")$data
      if (!is.null(vn) && nrow(vn) > 0) {
        en_names <- vn %>% filter(language == "eng") %>% pull(vernacularName)
        if (length(en_names) > 0) paste(unique(en_names), collapse = ", ") else NA_character_
      } else NA_character_
    }, error = function(e) NA_character_)

    # Get synonyms
    synonyms <- tryCatch({
      syn <- rgbif::name_usage(key = backbone$usageKey, data = "synonyms")$data
      if (!is.null(syn) && nrow(syn) > 0) paste(unique(syn$scientificName), collapse = ", ") else NA_character_
    }, error = function(e) NA_character_)

    list(
      scientificName = backbone$canonicalName %||% backbone$species %||% species_name,
      gbifKey = as.character(backbone$usageKey),
      vernacularName = vernacular,
      synonyms = synonyms
    )
  }, error = function(e) NULL)
}

check_europe_presence <- function(gbif_key) {
  if (is.na(gbif_key)) return(0L)
  tryCatch({
    europe <- c("AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR","DE","GR","HU",
                "IE","IT","LV","LT","LU","MT","NL","PL","PT","RO","SK","SI","ES",
                "SE","GB","NO","CH","IS")
    occ <- rgbif::occ_count(taxonKey = as.integer(gbif_key), country = europe, hasCoordinate = TRUE)
    if (occ > 0) 1L else 0L
  }, error = function(e) 0L)
}

get_distribution_summary <- function(gbif_key) {
  if (is.na(gbif_key)) return(NA_character_)
  tryCatch({
    dist_data <- rgbif::name_usage(key = as.integer(gbif_key), data = "distributions")$data
    if (is.null(dist_data) || nrow(dist_data) == 0) return(NA_character_)

    countries <- rgbif::enumeration_country()
    iso2_to_name <- setNames(countries$title, countries$iso2)

    entries <- character()
    for (i in seq_len(nrow(dist_data))) {
      loc <- dist_data$locality[i] %||% dist_data$locationId[i] %||%
             (if (!is.na(dist_data$country[i])) iso2_to_name[dist_data$country[i]] else NA)
      if (is.na(loc) || nchar(trimws(loc)) == 0) next
      means <- dist_data$establishmentMeans[i]
      if (!is.na(means) && nchar(means) > 0) {
        entries <- c(entries, paste0(loc, " (", tools::toTitleCase(means), ")"))
      } else {
        entries <- c(entries, loc)
      }
    }
    if (length(entries) > 0) {
      paste0("Distribution (GBIF, ", Sys.Date(), "): ", paste(unique(sort(entries)), collapse = "; "))
    } else NA_character_
  }, error = function(e) NA_character_)
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

# Connect to database
if (!file.exists(DB_FILE)) stop("Database not found: ", DB_FILE)
con <- dbConnect(RSQLite::SQLite(), DB_FILE)
on.exit(dbDisconnect(con))

cat("\n[BioPRIO] Processing", length(SPECIES_NAMES), "species\n")
cat("[BioPRIO] Database:", DB_FILE, "\n\n")

# Get starting IDs
max_pest <- dbGetQuery(con, "SELECT MAX(idPest) as m FROM pests")$m
next_pest_id <- if (is.na(max_pest)) 1 else max_pest + 1

max_assess <- dbGetQuery(con, "SELECT MAX(idAssessment) as m FROM assessments")$m
next_assessment_id <- if (is.na(max_assess)) 1 else max_assess + 1

today <- format(Sys.Date(), "%Y-%m-%d")
added_pests <- 0
added_assessments <- 0

# Process each species
for (i in seq_along(SPECIES_NAMES)) {
  species_name <- SPECIES_NAMES[i]
  cat("[", i, "/", length(SPECIES_NAMES), "] ", species_name, "\n", sep = "")

  # Check if exists
  existing <- dbGetQuery(con, "SELECT idPest FROM pests WHERE scientificName = ?",
                         params = list(species_name))

  if (nrow(existing) > 0 && PEST_EXISTS_MODE == "skip") {
    cat("  Skipped - already exists\n")
    pest_id <- existing$idPest
  } else {
    # Fetch GBIF data
    gbif <- get_gbif_taxonomy(species_name)
    if (is.null(gbif)) {
      cat("  WARNING: Not found in GBIF\n")
      gbif <- list(scientificName = species_name, gbifKey = NA_character_,
                   vernacularName = NA_character_, synonyms = NA_character_)
    }

    in_europe <- check_europe_presence(gbif$gbifKey)

    if (nrow(existing) > 0) {
      # Update existing
      pest_id <- existing$idPest
      dbExecute(con, "UPDATE pests SET synonyms=?, vernacularName=?, gbifTaxonKey=?, inEurope=? WHERE idPest=?",
                params = list(na_to_default(gbif$synonyms), na_to_default(gbif$vernacularName),
                              na_to_default(gbif$gbifKey), in_europe, pest_id))
      cat("  Updated pest ID:", pest_id, "\n")
    } else {
      # Insert new
      pest_id <- next_pest_id
      dbExecute(con,
                "INSERT INTO pests (idPest, scientificName, eppoCode, synonyms, vernacularName,
                                    gbifTaxonKey, idTaxa, idQuarantineStatus, inEurope)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                params = list(pest_id, gbif$scientificName, "",
                              na_to_default(gbif$synonyms), na_to_default(gbif$vernacularName),
                              na_to_default(gbif$gbifKey), DEFAULT_TAXA_ID, DEFAULT_QUARANTINE_ID, in_europe))
      cat("  Added pest ID:", pest_id, "\n")
      next_pest_id <- next_pest_id + 1
      added_pests <- added_pests + 1
    }
  }

  # Create assessment
  if (CREATE_ASSESSMENTS) {
    existing_assess <- dbGetQuery(con, "SELECT idAssessment FROM assessments WHERE idPest = ? LIMIT 1",
                                  params = list(pest_id))

    if (nrow(existing_assess) > 0 && ASSESSMENT_EXISTS_MODE == "skip") {
      cat("  Assessment exists - skipped\n")
    } else {
      # Get distribution for notes
      notes <- ""
      if (FETCH_DISTRIBUTION) {
        gbif_key <- dbGetQuery(con, "SELECT gbifTaxonKey FROM pests WHERE idPest = ?",
                               params = list(pest_id))$gbifTaxonKey
        if (!is.na(gbif_key) && nchar(gbif_key) > 0) {
          dist <- get_distribution_summary(gbif_key)
          if (!is.na(dist)) notes <- dist
        }
      }

      if (nrow(existing_assess) > 0) {
        # Update notes only
        dbExecute(con, "UPDATE assessments SET notes = ? WHERE idAssessment = ?",
                  params = list(notes, existing_assess$idAssessment))
        cat("  Updated assessment ID:", existing_assess$idAssessment, "\n")
      } else {
        # Create new assessment
        dbExecute(con,
                  "INSERT INTO assessments (idAssessment, idPest, idAssessor, startDate, hosts, notes, version, finished, valid)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                  params = list(next_assessment_id, pest_id, DEFAULT_ASSESSOR_ID, today, "", notes, "2.1", 0L, 0L))

        # Add default entry pathway
        dbExecute(con, "INSERT INTO entryPathways (idAssessment, idPathway) VALUES (?, ?)",
                  params = list(next_assessment_id, 8L))

        cat("  Created assessment ID:", next_assessment_id, "\n")
        next_assessment_id <- next_assessment_id + 1
        added_assessments <- added_assessments + 1
      }
    }
  }
}

cat("\n[BioPRIO] Done. Added", added_pests, "pests,", added_assessments, "assessments.\n")

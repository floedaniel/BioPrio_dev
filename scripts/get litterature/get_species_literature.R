# ============================================================================
# get_species_literature.R
# Unified script to search for and download scientific literature PDFs
# for multiple species, organized in species-specific folders.
# ============================================================================

# -------------------- DEPENDENCIES ------------------------------------------

required_packages <- c(
  "rgbif",
  "europepmc", "rentrez", "rcrossref", "httr", "jsonlite",
  "dplyr", "purrr", "stringr", "tidyr", "tibble", "openalexR"
)

# Install missing packages
for (pkg in required_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    message("Installing package: ", pkg)
    install.packages(pkg, dependencies = TRUE)
  }
}

library(europepmc)
library(rentrez)
library(rcrossref)
library(httr)
library(jsonlite)
library(dplyr)
library(purrr)
library(stringr)
library(tidyr)
library(tibble)
library(openalexR)
library(rgbif)

# -------------------- CONFIGURATION -----------------------------------------

# Base output directory (each species gets a subfolder)
# Format: {GBIF_KEY}_{Scientific_Name} to match hybrid justification populator
base_output_dir <- "C:/Users/dafl/OneDrive - Folkehelseinstituttet/Prosjektdata - Dokumenter/VKM Data/27.02.2025_maur_forprosjekt_biologisk_mangfold/data/species"

# Your email for Unpaywall API (required - register at unpaywall.org)
# This is free and gives access to legal open access PDFs
unpaywall_email <- "daniel.flo@vkm.no"

# Derive species list from folder structure (folders matching {GBIF_KEY}_{Genus}_{species}*)
folders <- list.dirs(base_output_dir, full.names = FALSE, recursive = FALSE)
species_list <- folders |>
  grep(pattern = "^\\d+_[A-Z][a-z]+_[a-z]+", value = TRUE) |>
  sub(pattern = "^\\d+_", replacement = "") |>
  strsplit(split = "_") |>
  sapply(function(parts) paste(parts[1], parts[2])) |>
  unique() |>
  sort()

# Optionally identify to CrossRef (improves rate limits)
Sys.setenv(crossref_email = unpaywall_email)

# Search settings
max_results_per_source <- 500   # Limit per database (lower = faster)
search_from_date <- "1800-01-01"  # Only papers published after this date

# Rate limiting (seconds between API calls)
delay_between_searches <- 1
delay_between_downloads <- 0.5

# -------------------- HELPER FUNCTIONS --------------------------------------

#' Create safe filename from DOI
safe_filename <- function(doi) {
  gsub("[^A-Za-z0-9._-]+", "_", doi)
}

#' Create species folder name in format: {GBIF_KEY}_{Scientific_Name}
#' @param species Scientific name
#' @param gbif_key GBIF taxon key
#' @return Folder name like "11700741_Lasius_aphidicola"
species_folder_name <- function(species, gbif_key) {
  safe_name <- gsub("[^A-Za-z0-9]+", "_", species)
  paste0(gbif_key, "_", safe_name)
}

#' Find existing species folder by GBIF key prefix
#' Searches for folders starting with "{gbif_key}_" to handle cases where
#' existing folders have different naming (e.g., "1315095_Formica_aserva_Forel,_1901")
#' @param base_dir Base directory to search in
#' @param gbif_key GBIF taxon key
#' @return Full path to existing folder, or NULL if not found
find_existing_species_folder <- function(base_dir, gbif_key) {
  if (!dir.exists(base_dir)) return(NULL)

  # List all directories
  all_dirs <- list.dirs(base_dir, full.names = FALSE, recursive = FALSE)

  # Find folders starting with "{gbif_key}_"
  prefix <- paste0(gbif_key, "_")
  matching <- all_dirs[startsWith(all_dirs, prefix)]

  if (length(matching) > 0) {
    # Return the first match (there should typically be only one)
    return(file.path(base_dir, matching[1]))
  }

  NULL
}

#' Rate-limited pause
rate_limit <- function(seconds) {
  Sys.sleep(seconds)
}

#' Log message with timestamp
log_msg <- function(...) {
  message("[", format(Sys.time(), "%H:%M:%S"), "] ", ...)
}

#' Get GBIF taxon key for a species
#' @param species_name Scientific name (e.g., "Lasius aphidicola")
#' @return GBIF usageKey as character, or NULL if not found
get_gbif_key <- function(species_name) {
  tryCatch({
    # Query GBIF backbone taxonomy
    result <- name_backbone(name = species_name, rank = "species", strict = FALSE)

    if (is.null(result) || length(result) == 0) {
      log_msg("  ⚠️ No GBIF match found for: ", species_name)
      return(NULL)
    }

    # Check if we got a valid match
    if (is.null(result$usageKey)) {
      log_msg("  ⚠️ No usageKey in GBIF response for: ", species_name)
      return(NULL)
    }

    # Check match type - warn if fuzzy
    if (!is.null(result$matchType) && result$matchType != "EXACT") {
      log_msg("  ℹ️ GBIF match type: ", result$matchType, " for ", species_name)
      if (!is.null(result$canonicalName)) {
        log_msg("  ℹ️ Matched to: ", result$canonicalName)
      }
    }

    as.character(result$usageKey)

  }, error = function(e) {
    log_msg("  ❌ GBIF lookup error for ", species_name, ": ", e$message)
    NULL
  })
}

# -------------------- SEARCH FUNCTIONS --------------------------------------

#' Search EuropePMC
search_europepmc <- function(term, limit) {
  tryCatch({
    res <- epmc_search(query = term, limit = limit, synonym = FALSE, sort = "cited")
    if (is.null(res) || nrow(res) == 0) return(NULL)

    res %>%
      filter(!is.na(doi)) %>%
      filter(str_detect(title, regex(term, ignore_case = TRUE))) %>%
      select(title, doi, any_of(c("pubYear", "citedByCount"))) %>%
      rename_with(~ c("title", "doi", "year", "citations")[seq_along(.)]) %>%
      mutate(source = "EuropePMC")
  }, error = function(e) {
    log_msg("EuropePMC error: ", e$message)
    NULL
  })
}

#' Search PubMed via Entrez
search_pubmed <- function(term, limit) {
  tryCatch({
    search_res <- entrez_search(db = "pubmed", term = term, retmax = limit)
    if (length(search_res$ids) == 0) return(NULL)

    # Fetch in batches to avoid timeout
    batch_size <- 100
    ids <- search_res$ids
    all_articles <- list()

    for (i in seq(1, length(ids), by = batch_size)) {
      batch_ids <- ids[i:min(i + batch_size - 1, length(ids))]
      articles <- entrez_summary(db = "pubmed", id = batch_ids)
      all_articles <- c(all_articles, list(articles))
      rate_limit(0.5)
    }

    # Flatten batches safely: esummary_list -> list of esummary; single esummary -> list of one
    flat_articles <- lapply(all_articles, function(batch) {
      if (inherits(batch, "esummary_list")) as.list(batch) else list(batch)
    }) |> unlist(recursive = FALSE)

    # Extract DOIs from elocationid field
    extract_doi <- function(x) {
      eloc <- x$elocationid
      if (is.null(eloc) || eloc == "") return(NA)
      # Extract DOI pattern
      doi_match <- str_extract(eloc, "10\\.[0-9]+/[^\\s]+")
      if (!is.na(doi_match)) return(doi_match)
      # Some are in format "doi: 10.xxxx"
      if (str_detect(eloc, "^doi:")) return(str_remove(eloc, "^doi:\\s*"))
      NA
    }

    results <- lapply(flat_articles, function(x) {
      data.frame(
        title = if (!is.null(x$title)) x$title else NA,
        doi = extract_doi(x),
        year = if (!is.null(x$pubdate)) str_extract(x$pubdate, "^\\d{4}") else NA,
        stringsAsFactors = FALSE
      )
    })

    bind_rows(results) %>%
      filter(!is.na(doi)) %>%
      filter(str_detect(title, regex(term, ignore_case = TRUE))) %>%
      mutate(source = "PubMed", citations = NA_integer_)

  }, error = function(e) {
    log_msg("PubMed error: ", e$message)
    NULL
  })
}

#' Search CrossRef
search_crossref <- function(term, limit) {
  tryCatch({
    # Use quoted phrase for exact match
    cr_res <- cr_works(query = paste0('"', term, '"'), limit = limit)
    if (is.null(cr_res$data) || nrow(cr_res$data) == 0) return(NULL)

    cr_res$data %>%
      as_tibble() %>%
      filter(!is.na(doi)) %>%
      mutate(
        title = map_chr(title, ~ if (!is.null(.x)) paste(.x, collapse = " ") else NA_character_),
        year = map_chr(issued, ~ {
          if (is.null(.x) || length(.x) == 0) return(NA_character_)
          parts <- .x[[1]]
          if (length(parts) > 0) as.character(parts[1]) else NA_character_
        })
      ) %>%
      filter(str_detect(title, regex(term, ignore_case = TRUE))) %>%
      select(title, doi, year) %>%
      mutate(source = "CrossRef", citations = NA_integer_)

  }, error = function(e) {
    log_msg("CrossRef error: ", e$message)
    NULL
  })
}

#' Search OpenAlex
search_openalex <- function(term, limit, from_date) {
  tryCatch({
    # Use search parameter (general text search) with mailto for polite pool
    oa_res <- oa_fetch(
      entity = "works",
      cited_by_count = ">1",
      # title.search = term,
      abstract.search= term,
      from_publication_date = "1800-01-01",
      to_publication_date = "2026-01-01",
      mailto = unpaywall_email,
      options = list(sort = "cited_by_count:desc"),
      verbose = TRUE
    )

    if (is.null(oa_res) || nrow(oa_res) == 0) return(NULL)

    oa_res %>%
      filter(!is.na(doi)) %>%
      select(title, doi, publication_year, cited_by_count, any_of("oa_url")) %>%
      rename(year = publication_year, citations = cited_by_count) %>%
      mutate(
        source = "OpenAlex",
        year = as.character(year)
      )

  }, error = function(e) {
    log_msg("OpenAlex error: ", e$message)
    NULL
  })
}

#' Combined search across all databases
search_all_sources <- function(term, limit = 500, from_date = "2000-01-01") {
  log_msg("Searching EuropePMC...")
  epmc <- search_europepmc(term, limit)
  rate_limit(delay_between_searches)

  log_msg("Searching PubMed...")
  pubmed <- search_pubmed(term, limit)
  rate_limit(delay_between_searches)

  log_msg("Searching CrossRef...")
  crossref <- search_crossref(term, limit)
  rate_limit(delay_between_searches)

  log_msg("Searching OpenAlex...")
  openalex <- search_openalex(term, limit, from_date)

  # Combine and deduplicate (coerce doi to character to handle all-NA logical columns)
  all_results <- bind_rows(
    lapply(list(epmc, pubmed, crossref, openalex), function(df) {
      if (!is.null(df) && "doi" %in% names(df)) df <- mutate(df, doi = as.character(doi))
      df
    })
  )

  if (nrow(all_results) == 0) return(NULL)

  # Normalize DOIs (lowercase, remove URL prefix)
  all_results <- all_results %>%
    mutate(
      doi_clean = tolower(doi),
      doi_clean = str_remove(doi_clean, "^https?://doi\\.org/"),
      doi_clean = str_remove(doi_clean, "^doi:\\s*")
    )

  # Deduplicate, keeping first occurrence (preserves source info)
  all_results %>%
    group_by(doi_clean) %>%
    slice_head(n = 1) %>%
    ungroup() %>%
    select(-doi_clean) %>%
    arrange(desc(citations))
}

# -------------------- PDF RETRIEVAL FUNCTIONS -------------------------------

#' Query Unpaywall for open access PDF URL
get_unpaywall_url <- function(doi, email) {
  tryCatch({
    url <- paste0("https://api.unpaywall.org/v2/", URLencode(doi, reserved = TRUE),
                  "?email=", URLencode(email))
    resp <- GET(url, timeout(10))

    if (status_code(resp) != 200) return(NULL)

    data <- content(resp, as = "parsed")

    # Try best open access location first
    if (!is.null(data$best_oa_location$url_for_pdf)) {
      return(data$best_oa_location$url_for_pdf)
    }

    # Fall back to any OA location with PDF
    for (loc in data$oa_locations) {
      if (!is.null(loc$url_for_pdf)) {
        return(loc$url_for_pdf)
      }
    }

    NULL
  }, error = function(e) NULL)
}

#' Get PDF URL from CrossRef metadata
get_crossref_pdf_url <- function(doi) {
  tryCatch({
    cr_data <- cr_works(dois = doi)$data
    if (is.null(cr_data) || nrow(cr_data) == 0) return(NULL)

    links <- cr_data$link[[1]]
    if (is.null(links) || length(links) == 0) return(NULL)

    # Convert to data frame if needed
    if (!is.data.frame(links)) {
      links <- as.data.frame(links)
    }

    # Look for PDF links
    pdf_link <- links %>%
      filter(
        str_detect(tolower(`content-type`), "pdf") |
        str_detect(tolower(URL), "\\.pdf")
      ) %>%
      slice_head(n = 1)

    if (nrow(pdf_link) > 0) return(pdf_link$URL)
    NULL

  }, error = function(e) NULL)
}

#' Get PubMed Central PDF URL
get_pmc_pdf_url <- function(doi) {
  tryCatch({
    # Search PMC for the DOI
    search_res <- entrez_search(db = "pmc", term = paste0(doi, "[doi]"), retmax = 1)
    if (length(search_res$ids) == 0) return(NULL)

    pmc_id <- search_res$ids[1]
    # PMC PDF URL pattern
    paste0("https://www.ncbi.nlm.nih.gov/pmc/articles/PMC", pmc_id, "/pdf/")

  }, error = function(e) NULL)
}

#' Try to find PDF URL from multiple sources
find_pdf_url <- function(doi, email) {
  # Try Unpaywall first (best source for legal OA PDFs)
  url <- get_unpaywall_url(doi, email)
  if (!is.null(url)) return(list(url = url, source = "Unpaywall"))

  rate_limit(0.3)

  # Try CrossRef
  url <- get_crossref_pdf_url(doi)
  if (!is.null(url)) return(list(url = url, source = "CrossRef"))

  rate_limit(0.3)

  # Try PMC
  url <- get_pmc_pdf_url(doi)
  if (!is.null(url)) return(list(url = url, source = "PMC"))

  NULL
}

#' Download PDF with validation
download_pdf <- function(url, filepath, timeout_sec = 60) {
  tryCatch({
    ua <- user_agent("VKM-BioPrio/1.0 (literature retrieval)")

    resp <- GET(
      url,
      ua,
      write_disk(filepath, overwrite = TRUE),
      timeout(timeout_sec),
      config(followlocation = TRUE)
    )

    # Validate download
    if (status_code(resp) != 200) {
      if (file.exists(filepath)) file.remove(filepath)
      return(list(success = FALSE, reason = paste("HTTP", status_code(resp))))
    }

    # Check file size (PDFs should be > 1KB)
    if (!file.exists(filepath) || file.info(filepath)$size < 1024) {
      if (file.exists(filepath)) file.remove(filepath)
      return(list(success = FALSE, reason = "File too small"))
    }

    # Check content type
    content_type <- headers(resp)$`content-type`
    if (!is.null(content_type) && !str_detect(tolower(content_type), "pdf|octet")) {
      # Read first bytes to check PDF magic number
      con <- file(filepath, "rb")
      header <- readBin(con, "raw", 5)
      close(con)

      if (!identical(rawToChar(header), "%PDF-")) {
        file.remove(filepath)
        return(list(success = FALSE, reason = "Not a PDF file"))
      }
    }

    list(success = TRUE, reason = "OK", size = file.info(filepath)$size)

  }, error = function(e) {
    if (file.exists(filepath)) file.remove(filepath)
    list(success = FALSE, reason = e$message)
  })
}

# -------------------- MAIN PROCESSING ---------------------------------------

#' Process a single species
process_species <- function(species, base_dir, email, max_results, from_date, gbif_key = NULL) {
  log_msg("========================================")
  log_msg("Processing: ", species)
  log_msg("========================================")

  # Validate GBIF key
  if (is.null(gbif_key) || gbif_key == "") {
    log_msg("⚠️ No GBIF key provided for ", species, " - skipping")
    return(NULL)
  }
  log_msg("GBIF taxon key: ", gbif_key)

  # Check for existing folder with this GBIF key (may have different naming)
  existing_folder <- find_existing_species_folder(base_dir, gbif_key)

  if (!is.null(existing_folder)) {
    species_dir <- existing_folder
    log_msg("Using existing folder: ", basename(species_dir))
  } else {
    # Create new folder with standard naming
    species_dir <- file.path(base_dir, species_folder_name(species, gbif_key))
    dir.create(species_dir, recursive = TRUE)
    log_msg("Created new folder: ", basename(species_dir))
  }

  # Create literature subfolder for PDFs (keeps species folder organized)
  literature_dir <- file.path(species_dir, "literature")
  if (!dir.exists(literature_dir)) dir.create(literature_dir, recursive = TRUE)

  # Search for literature
  log_msg("Searching databases...")
  results <- search_all_sources(species, limit = max_results, from_date = from_date)

  if (is.null(results) || nrow(results) == 0) {
    log_msg("No results found for: ", species)
    return(NULL)
  }

  log_msg("Found ", nrow(results), " unique papers")

  # Save metadata
  results$species <- species
  metadata_file <- file.path(species_dir, "metadata.csv")
  write.csv(results, metadata_file, row.names = FALSE)
  log_msg("Saved metadata to: ", metadata_file)

  # Create RIS file for citation managers
  ris_content <- results %>%
    rowwise() %>%
    mutate(
      ris_entry = paste0(
        "TY  - JOUR\n",
        "TI  - ", title, "\n",
        "DO  - ", doi, "\n",
        if (!is.na(year)) paste0("PY  - ", year, "\n") else "",
        "ER  - \n\n"
      )
    ) %>%
    pull(ris_entry) %>%
    paste(collapse = "")

  ris_file <- file.path(species_dir, "references.ris")
  writeLines(ris_content, ris_file)
  log_msg("Saved RIS file to: ", ris_file)

  # Download PDFs
  log_msg("Attempting PDF downloads...")

  download_log <- tibble(
    doi = character(),
    title = character(),
    pdf_url = character(),
    pdf_source = character(),
    filepath = character(),
    status = character(),
    reason = character(),
    file_size = numeric()
  )

  for (i in seq_len(nrow(results))) {
    doi <- results$doi[i]
    title <- results$title[i]

    log_msg("[", i, "/", nrow(results), "] ", str_trunc(title, 50))

    # Check if already downloaded
    filepath <- file.path(literature_dir, paste0(safe_filename(doi), ".pdf"))
    if (file.exists(filepath) && file.info(filepath)$size > 1024) {
      log_msg("  -> Already downloaded, skipping")
      download_log <- bind_rows(download_log, tibble(
        doi = doi, title = title, pdf_url = NA, pdf_source = NA,
        filepath = filepath, status = "skipped", reason = "Already exists",
        file_size = file.info(filepath)$size
      ))
      next
    }

    # Find PDF URL
    pdf_info <- find_pdf_url(doi, email)

    if (is.null(pdf_info)) {
      log_msg("  -> No PDF URL found")
      download_log <- bind_rows(download_log, tibble(
        doi = doi, title = title, pdf_url = NA, pdf_source = NA,
        filepath = NA, status = "failed", reason = "No PDF URL found",
        file_size = NA
      ))
      next
    }

    # Download PDF
    result <- download_pdf(pdf_info$url, filepath)

    if (result$success) {
      log_msg("  -> Downloaded from ", pdf_info$source, " (", result$size, " bytes)")
      download_log <- bind_rows(download_log, tibble(
        doi = doi, title = title, pdf_url = pdf_info$url, pdf_source = pdf_info$source,
        filepath = filepath, status = "success", reason = "OK",
        file_size = result$size
      ))
    } else {
      log_msg("  -> Download failed: ", result$reason)
      download_log <- bind_rows(download_log, tibble(
        doi = doi, title = title, pdf_url = pdf_info$url, pdf_source = pdf_info$source,
        filepath = NA, status = "failed", reason = result$reason,
        file_size = NA
      ))
    }

    rate_limit(delay_between_downloads)
  }

  # Save download log
  log_file <- file.path(species_dir, "download_log.csv")
  write.csv(download_log, log_file, row.names = FALSE)

  # Summary
  success_count <- sum(download_log$status == "success")
  skipped_count <- sum(download_log$status == "skipped")
  failed_count <- sum(download_log$status == "failed")

  log_msg("")
  log_msg("Summary for ", species, ":")
  log_msg("  Total papers: ", nrow(results))
  log_msg("  PDFs downloaded: ", success_count)
  log_msg("  Already had: ", skipped_count)
  log_msg("  Failed: ", failed_count)
  log_msg("  Download log: ", log_file)

  download_log
}

# -------------------- RUN ---------------------------------------------------

log_msg("Starting literature retrieval for ", length(species_list), " species")
log_msg("Output directory: ", base_output_dir)
log_msg("")

all_logs <- list()

for (species in species_list) {
  log_msg("Looking up GBIF key for: ", species)
  gbif_key <- get_gbif_key(species)

  if (is.null(gbif_key)) {
    log_msg("⚠️ Skipping ", species, " - no GBIF key found")
    next
  }

  species_log <- tryCatch(
    process_species(
      species = species,
      base_dir = base_output_dir,
      email = unpaywall_email,
      max_results = max_results_per_source,
      from_date = search_from_date,
      gbif_key = gbif_key
    ),
    error = function(e) {
      log_msg("❌ Error processing ", species, ": ", e$message, " — skipping")
      NULL
    }
  )

  if (!is.null(species_log)) {
    all_logs[[species]] <- species_log
  }

  # Pause between species to avoid rate limits
  rate_limit(2)
}

# Final summary
log_msg("")
log_msg("========================================")
log_msg("FINAL SUMMARY")
log_msg("========================================")

if (length(all_logs) > 0) {
  combined_log <- bind_rows(all_logs, .id = "species")

  summary_stats <- combined_log %>%
    group_by(species, status) %>%
    summarise(count = n(), .groups = "drop") %>%
    pivot_wider(names_from = status, values_from = count, values_fill = 0)

  print(summary_stats)

  # Save combined log
  combined_log_file <- file.path(base_output_dir, "all_species_download_log.csv")
  write.csv(combined_log, combined_log_file, row.names = FALSE)
  log_msg("Combined log saved to: ", combined_log_file)
}

log_msg("Done!")

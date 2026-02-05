# ------------------------------------------------------------
# 01_corpus.R
# Retrieve and prepare candidate abstracts for SCP extraction
# ------------------------------------------------------------

## ---- Setup -------------------------------------------------------------
library(httr)
library(jsonlite)
library(data.table)

invisible(lapply(list.files("utils", full.names = TRUE), source))

## ---- Query parameters --------------------------------------------------
target_n <- 5000 # Number of initial documents to retrieve
search_q <- "(Amazon OR Amazonia) AND (vector OR zoonotic) AND (species) AND (disease OR infection OR transmission OR host OR treatment OR control)" # Search query

## ---- OpenAlex retrieval ------------------------------------------------
cursor   <- "*"
total    <- 0
all_res  <- list()

repeat {

  res <- GET(
    "https://api.openalex.org/works",
    query = list(search = search_q, per_page = 200, cursor = cursor)
  )

  data <- fromJSON(content(res, "text", encoding = "UTF-8"), simplifyVector = FALSE)

  all_res[[length(all_res) + 1]] <- data$results
  total <- total + length(data$results)

  message("Collected: ", total, " entries")

  if (total >= target_n || is.null(data$meta$next_cursor)) break
  cursor <- data$meta$next_cursor
}

## ---- Result assembly ---------------------------------------------------
results <- rbindlist(
  lapply(unlist(all_res, recursive = FALSE), extract_openalex_fields),
  fill = TRUE
)

## ---- Abstract reconstruction ------------------------------------------
openalex_abs <- character(nrow(results))
for (i in seq_len(nrow(results))) {
  openalex_abs[i] <- reconstruct_openalex_abstract(
    results$abstract_inverted_index[[i]]
  )
}

message(
  "Abstracts available from OpenAlex: ",
  sum(!is.na(openalex_abs)), " / ", length(openalex_abs)
)

## ---- Dataset preparation ----------------------------------------------
df <- data.table(
  id       = seq_len(nrow(results)),
  title    = results$title,
  journal  = results$journal,
  year     = results$publication_year,
  doi      = results$doi,
  abstract = openalex_abs
)

df <- df[!is.na(abstract) & nzchar(abstract)]
df <- df[!duplicated(abstract)]
df <- df[
  apply_boolean_grepl(paste(title, abstract), search_q)
]

## ---- Output ------------------------------------------------------------
fwrite(df, "output/01_abstracts.psv", sep = "|")

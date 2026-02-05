# ------------------------------------------------------------
# Helpers for OpenAlex retrieval and filtering
# ------------------------------------------------------------

## ---- Abstract reconstruction ------------------------------------------
reconstruct_openalex_abstract <- function(inv_index) {

  if (is.null(inv_index) || !length(inv_index)) {
    return(NA_character_)
  }

  pos   <- unlist(inv_index, use.names = FALSE)
  words <- rep(names(inv_index), lengths(inv_index))

  paste(words[order(pos)], collapse = " ")
}

## ---- OpenAlex record extraction ---------------------------------------
extract_openalex_fields <- function(x) {

  data.frame(
    id    = if (!is.null(x$id)) x$id else NA_character_,
    title = if (!is.null(x$title)) x$title else NA_character_,
    doi   = if (!is.null(x$doi)) x$doi else NA_character_,
    journal = if (!is.null(x$primary_location$source$display_name))
      x$primary_location$source$display_name else NA_character_,
    publication_year = if (!is.null(x$publication_year))
      x$publication_year else NA_integer_,
    abstract_inverted_index = I(list(x$abstract_inverted_index)),
    stringsAsFactors = FALSE
  )
}

## ---- Boolean filtering ------------------------------------------------
apply_boolean_grepl <- function(text, query, ignore.case = TRUE) {

  q <- tolower(query)
  blocks <- strsplit(q, "\\s+and\\s+")[[1]]
  keep <- rep(TRUE, length(text))

  for (blk in blocks) {
    blk <- gsub("^\\(|\\)$", "", blk)
    rx  <- gsub("\\s+or\\s+", "|", blk)
    keep <- keep & grepl(rx, text, ignore.case = ignore.case)
  }

  keep
}
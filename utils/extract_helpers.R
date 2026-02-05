# ------------------------------------------------------------
# Helpers for SCP extraction and assembly
# ------------------------------------------------------------

## ---- Species utilities -------------------------------------------------
normalize_species_vector <- function(species_tbl) {

  if (is.null(species_tbl) || nrow(species_tbl) == 0) {
    return(character())
  }

  names <- species_tbl$name
  names <- trimws(names[!is.na(names)])
  names <- names[nzchar(names)]

  sort(unique(names))
}

## ---- Context utilities -------------------------------------------------
extract_context_fields <- function(extracted) {

  ctx <- extracted$contextual_information

  data.frame(
    study_location = if (!is.null(ctx$study_location))
      ctx$study_location else "Unknown",
    scale = if (!is.null(ctx$scale))
      ctx$scale else "Unknown",
    study_period = if (!is.null(ctx$study_period))
      ctx$study_period else "Unknown",
    stringsAsFactors = FALSE
  )
}

## ---- Prompt utilities --------------------------------------------------
read_prompt <- function(path) {
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

fill_template <- function(template, values) {
  for (nm in names(values)) {
    template <- gsub(
      paste0("{{", nm, "}}"),
      values[[nm]],
      template,
      fixed = TRUE
    )
  }
  template
}

## ---- SCP reshaping -----------------------------------------------------
flatten_scp_results <- function(x) {

  if (is.list(x) && !is.data.frame(x) && !is.null(x$output)) {
    x <- x$output
  }

  rows <- list()

  for (i in seq_len(nrow(x))) {

    rels <- x$links[[i]]
    if (!nrow(rels)) next

    sp <- x$species_name[i]

    for (j in seq_len(nrow(rels))) {
      rows[[length(rows) + 1]] <- data.frame(
        species_name  = sp,
        health_target = rels$health_target[j],
        mechanism     = rels$mechanism[j],
        stringsAsFactors = FALSE
      )
    }
  }

  if (!length(rows)) data.frame() else do.call(rbind, rows)
}
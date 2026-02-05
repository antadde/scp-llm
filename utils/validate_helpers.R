# ------------------------------------------------------------
# Helpers for SCP validation
# ------------------------------------------------------------

## ---- Mechanism scoring -------------------------------------------------
mechanism_score <- function(ext, cur) {

  idx <- which(
    mechanism_compatibility$extracted == ext &
    mechanism_compatibility$curated   == cur
  )

  if (!length(idx)) return(0)
  mechanism_compatibility$score[idx[1]]
}

## ---- String utilities --------------------------------------------------
norm <- function(x) {
  tolower(trimws(x))
}

## ---- Taxonomy utilities -----------------------------------------------
get_genus <- function(x) {

  if (is.na(x) || !nzchar(x)) {
    return(NA_character_)
  }

  strsplit(x, "\\s+")[[1]][1]
}
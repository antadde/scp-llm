# ------------------------------------------------------------
# Standardise health terminology across SCP records
# ------------------------------------------------------------

health_cleaner <- function(dt) {

  ## ---- Normalisation ---------------------------------------------------
  dt[, health_norm := {
    x <- tolower(health_target)
    x <- gsub("ó", "o", x)
    x <- gsub("[’']", "'", x)
    x <- gsub("\\([^)]*\\)", "", x)
    x <- gsub("-", " ", x)
    x <- gsub("[0-9]+", "", x)
    x <- gsub("\\s+", " ", x)
    x <- gsub("spp?\\.$", "", x)
    x <- gsub("'s", "", x)
    x <- gsub("'", "", x)
    x <- gsub(" virus$", "", x)
    trimws(x)
  }]

  dt[, health_norm := str_squish(
    str_replace_all(health_norm, "[^a-z ]", "")
  )]

  ## ---- Token filtering -------------------------------------------------
  weak_tokens <- c(
    "disease", "diseases", "virus", "viruses",
    "infection", "infections", "fever", "syndrome",
    "acute", "chronic", "american", "new", "world",
    "cutaneous", "mucocutaneous", "tegumentary",
    "visceral", "human", "animal",
    "zoonotic", "zoonoses",
    "type", "and", "or", "andor", "like"
  )

  dt[, tokens := str_split(health_norm, "\\s+")]
  dt[, core_tokens := lapply(tokens, setdiff, y = weak_tokens)]
  dt[lengths(core_tokens) == 0, core_tokens := tokens]

  ## ---- Canonical key ---------------------------------------------------
  dt[, core_key := vapply(
    core_tokens,
    function(x) paste(sort(unique(x)), collapse = "_"),
    character(1)
  )]

  canon_map <- dt[
    , .N, by = .(core_key, health_norm)
  ][
    order(core_key, -N)
  ][
    , .SD[1], by = core_key
  ][
    , .(core_key, health_standard = health_norm)
  ]

  dt <- canon_map[dt, on = "core_key"]

  ## ---- Manual harmonisation --------------------------------------------
  dt[grepl(
    "zoon|arbov|mosquit|pathog|infectious disease|vector borne",
    health_standard, ignore.case = TRUE
  ), health_standard := "ZVBD"]

  dt[grepl("leish",  health_standard, ignore.case = TRUE),
     health_standard := "leishmaniasis"]

  dt[grepl("plasmo|malaria", health_standard, ignore.case = TRUE),
     health_standard := "malaria"]

  dt[grepl("orop", health_standard, ignore.case = TRUE),
     health_standard := "oropouche"]

  dt[grepl("spotted fever|rickett", health_standard, ignore.case = TRUE),
     health_standard := "spotted fever"]

  dt[grepl("eastern equine", health_standard, ignore.case = TRUE),
     health_standard := "eastern equine encephalitis"]

  dt[grepl("venezuelan equine", health_standard, ignore.case = TRUE),
     health_standard := "venezuelan equine encephalitis"]

  dt <- dt[!grepl("not specified", health_standard, ignore.case = TRUE)]

  ## ---- Cleanup ---------------------------------------------------------
  dt[, c("tokens", "core_tokens", "core_key") := NULL]

  keep_cols <- c(
    "id",
    "species_name",
    "health_target",
    "mechanism",
    "study_location",
    "scale",
    "study_period",
    "doi",
    "species_resolved",
    "health_standard",
    "phylum",
    "class"
  )

  dt[, setdiff(names(dt), keep_cols) := NULL]
  setcolorder(dt, keep_cols)

  dt[]
}
# ------------------------------------------------------------
# 03_validate_fulltext.R
# Validation of extracted SCP from full-text .txt files
# ------------------------------------------------------------

## ---- Setup -------------------------------------------------------------
library(data.table)
library(stringr)
library(rgbif)

invisible(lapply(list.files("utils", full.names = TRUE), source))

# Choose the LLM provider:
# "openai" = GPT-4o-mini
# "gemini" = Gemini 2.5 Flash

# provider <- "gemini"
provider <- "openai"

## ======================================================================
## PART A — Validation against curated evidence
## ======================================================================

## ---- Data --------------------------------------------------------------
extracted <- fread(paste0("output/02_extracted_fulltext_", provider, ".psv"), sep = "|")
curated   <- fread("input/curated_evidence.psv", sep = "|")


## ---- Standardization ---------------------------------------------------
extracted <- species_cleaner(extracted)
extracted <- health_cleaner(extracted)

# Remove poorly defined study context
extracted <- extracted[
  !((study_location == "unknown" & scale == "unknown") | scale == "global")
]

## ---- Scoring functions -------------------------------------------------
species_score <- function(ext, cur) {
  if (is.na(ext) || is.na(cur)) return(0)
  if (ext == cur) return(1)
  if (get_genus(ext) == get_genus(cur)) return(0.6)
  0
}

health_score <- function(ext, cur, curated_vals) {
  if (is.na(ext) || is.na(cur)) return(0)
  if (ext == cur) return(1)
  if (ext %in% curated_vals) return(0.6)
  0
}

mechanism_score <- function(ext, cur, same_roles, sp_score) {
  if (is.na(ext) || is.na(cur) || sp_score < 0.5) return(0)
  if (ext == cur) return(1)
  if (length(same_roles) > 1) return(0.3)
  0
}

## ---- Validation loop ---------------------------------------------------
validated_list <- vector("list", nrow(extracted))

for (i in seq_len(nrow(extracted))) {
  
  ext_sp <- extracted$species_resolved[i]
  ext_ht <- extracted$health_standard[i]
  ext_mc <- extracted$mechanism[i]
  
  sp_scores <- vapply(
    curated$species_name,
    species_score,
    numeric(1),
    ext = ext_sp
  )
  
  ht_scores <- vapply(
    curated$health_target,
    health_score,
    numeric(1),
    ext = ext_ht,
    curated_vals = curated$health_target
  )
  
  mech_scores <- mapply(
    mechanism_score,
    cur = curated$mechanism,
    sp_score = sp_scores,
    MoreArgs = list(
      ext = ext_mc,
      same_roles = curated$mechanism[
        curated$species_name == ext_sp &
          curated$health_target == ext_ht
      ]
    )
  )
  
  total_scores <- (sp_scores + ht_scores + mech_scores) / 3
  best_idx <- which.max(total_scores)
  
  validated_list[[i]] <- cbind(
    extracted[i],
    curated[best_idx, .(
      curated_species   = species_name,
      curated_health    = health_target,
      curated_mechanism = mechanism
    )],
    data.table(
      species_score   = sp_scores[best_idx],
      health_score    = ht_scores[best_idx],
      mechanism_score = mech_scores[best_idx],
      total_score     = total_scores[best_idx]
    )
  )
}

validated <- rbindlist(validated_list, fill = TRUE)

## ---- Classification ----------------------------------------------------
validated[, validation_class := fifelse(
  total_score >= 0.85, "strong",
  fifelse(total_score >= 0.6, "moderate", "weak or novel")
)]

validated[, axis_profile := paste0(
  ifelse(species_score   >= 0.5, "S", "s"),
  ifelse(health_score    >= 0.5, "H", "h"),
  ifelse(mechanism_score >= 0.5, "M", "m")
)]

## ---- Output table ------------------------------------------------------
validated_clean <- unique(validated[, .(
  extracted_id  = id,
  species       = species_resolved,
  phylum,
  class,
  health_target = health_standard,
  mechanism,
  study_location,
  scale,
  study_period,
  curated_species,
  curated_health,
  curated_mechanism,
  species_score,
  health_score,
  mechanism_score,
  total_score,
  validation_class,
  axis_profile
)])

fwrite(validated_clean, paste0("output/03_validated_fulltext_", provider, ".psv"), sep = "|")
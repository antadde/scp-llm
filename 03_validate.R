# ------------------------------------------------------------
# 03_validate.R
# Validation of extracted SCP
#   A) against curated evidence
#   B) against manually extracted test set
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
extracted <- fread(paste0("output/02_extracted_", provider, ".psv"), sep = "|")
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
  doi,
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

fwrite(validated_clean, paste0("output/03_validated_", provider, ".psv"), sep = "|")

## ======================================================================
## PART B — Validation against manually extracted test set
## ======================================================================

## ---- Data --------------------------------------------------------------
extracted_ts <- fread(paste0("output/02_extracted_", provider, ".psv"), sep = "|")[grep("t", id)]
curated_ts   <- fread("input/manual_testset.psv", sep = "|")

extracted_ts <- health_cleaner(species_cleaner(extracted_ts))
curated_ts   <- health_cleaner(species_cleaner(curated_ts))

## ---- Manual → LLM ------------------------------------------------------
cmp <- merge(
  curated_ts, extracted_ts,
  by = "id", suffixes = c("_manual", "_llm"),
  allow.cartesian = TRUE
)

cmp[, `:=`(
  species_match   = species_resolved_manual == species_resolved_llm,
  health_match    = health_standard_manual  == health_standard_llm,
  mechanism_match = mechanism_manual        == mechanism_llm
)]

cmp[, match_score := species_match + health_match + mechanism_match]

setorder(
  cmp,
  species_resolved_manual, health_standard_manual,
  mechanism_manual, id, -match_score
)

best_llm <- cmp[, .SD[1], by = .(
  species_resolved_manual, health_standard_manual, mechanism_manual, id
)]

best_llm[, validation := fifelse(
  match_score == 3, "retrieved",
  fifelse(match_score == 2, "partial_miss",
          fifelse(!is.na(species_resolved_llm), "unclear_miss", "hard_miss"))
)]

manual_to_llm <- best_llm[, .(
  id,
  species_resolved_manual,
  health_standard_manual,
  mechanism_manual,
  species_resolved_llm,
  health_standard_llm,
  mechanism_llm,
  match_score,
  validation
)]

## ---- LLM → Manual ------------------------------------------------------
cmp_rev <- merge(
  extracted_ts, curated_ts,
  by = "id", suffixes = c("_llm", "_manual"),
  allow.cartesian = TRUE
)

cmp_rev[, `:=`(
  species_match   = species_resolved_llm == species_resolved_manual,
  health_match    = health_standard_llm  == health_standard_manual,
  mechanism_match = mechanism_llm        == mechanism_manual
)]

cmp_rev[, match_score := species_match + health_match + mechanism_match]

setorder(
  cmp_rev,
  species_resolved_llm, health_standard_llm,
  mechanism_llm, id, -match_score
)

best_manual <- cmp_rev[, .SD[1], by = .(
  species_resolved_llm, health_standard_llm, mechanism_llm, id
)]

best_manual[, validation := fifelse(
  match_score == 3, "confirmed",
  fifelse(match_score == 2, "partial", "llm_only")
)]

llm_to_manual <- best_manual[, .(
  id,
  species_resolved_llm,
  health_standard_llm,
  mechanism_llm,
  species_resolved_manual,
  health_standard_manual,
  mechanism_manual,
  match_score,
  validation
)]

## ---- Inspection --------------------------------------------------------
manual_to_llm[, .N, by = validation]
llm_to_manual[, .N, by = validation]
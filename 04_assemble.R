# ------------------------------------------------------------
# 04_assemble.R
# Final assembly of validated SCP dataset
# ------------------------------------------------------------

## ---- Setup -------------------------------------------------------------
library(data.table)

invisible(lapply(list.files("utils", full.names = TRUE), source))

## ---- Data --------------------------------------------------------------
validated <- fread("output/03_validated.psv", sep = "|")

## ---- Schema enforcement ------------------------------------------------
core_fields <- c(
  "extracted_id",
  "species",
  "phylum",
  "class",
  "health_target",
  "mechanism",
  "study_location",
  "scale",
  "study_period",
  "validation_class",
  "axis_profile",
  "species_score",
  "health_score",
  "mechanism_score",
  "total_score",
  "doi"
)

missing <- setdiff(core_fields, names(validated))
if (length(missing)) {
  stop("Missing required fields: ", paste(missing, collapse = ", "))
}

validated <- validated[, ..core_fields]

validated[, `:=`(
  extracted_id      = as.integer(extracted_id),
  validation_class  = as.factor(validation_class),
  axis_profile      = as.factor(axis_profile),
  species_score     = as.numeric(species_score),
  health_score      = as.numeric(health_score),
  mechanism_score   = as.numeric(mechanism_score),
  total_score       = round(as.numeric(total_score), 2)
)]

validated <- unique(validated)
validated[, scp_id := .I]
setcolorder(validated, c("scp_id", core_fields))

## ---- Framework mapping -------------------------------------------------
scp_map <- fread("input/ncp_es.psv", sep = "|")

validated <- scp_map[
  validated,
  on = .(mechanism)
]

## ---- Final ordering ----------------------------------------------------
core_cols <- c(
  "scp_id", "extracted_id", "species", "phylum", "class",
  "health_target", "mechanism", "study_location",
  "scale", "study_period", "doi"
)

validation_cols <- c(
  "validation_class", "axis_profile",
  "species_score", "health_score",
  "mechanism_score", "total_score"
)

framework_cols <- setdiff(names(scp_map), "mechanism")

final_order <- intersect(
  c(core_cols, validation_cols, framework_cols),
  names(validated)
)

setcolorder(validated, final_order)

## ---- Output ------------------------------------------------------------
fwrite(validated, "output/04_assembled.psv", sep = "|")
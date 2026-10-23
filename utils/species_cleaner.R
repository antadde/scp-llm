# ------------------------------------------------------------
# Resolve and standardise species names
# ------------------------------------------------------------

species_cleaner <- function(dt) {

  ## ---- Conservative normalisation -------------------------------------
  dt[, species_clean := {
    x <- tolower(species_name)
    x <- trimws(x)
    x <- gsub(",", "", x)
    x <- gsub("\\([^)]*\\)", "", x)
    x <- gsub("\\s+", " ", x)
    x <- gsub("\\s+[a-z]$", "", x)
    x <- gsub("(\\s+\\S*\\d+\\S*$)|(^\\S*\\d+\\S*$)", "", x)
    x <- gsub("\\bsp\\.$", "spp.", x)
    trimws(x)
  }]

  dt <- dt[nchar(species_clean) >= 5]
  dt <- dt[!grepl("virus", species_clean, ignore.case = TRUE)]

  ## ---- Abbreviation detection -----------------------------------------
  dt[, is_abbrev := grepl("^[a-z]+\\.", species_clean)]

  dt[, epithet := fifelse(
    grepl(" ", species_clean),
    word(sub("^[^ ]+\\s+", "", species_clean), 1),
    NA_character_
  )]

  dt[, genus_full := fifelse(
    !is_abbrev & grepl(" ", species_clean),
    sub(" .*", "", species_clean),
    NA_character_
  )]

  dt[, genus_abbrev := fifelse(
    is_abbrev,
    sub("\\..*$", "", species_clean),
    NA_character_
  )]

  ## ---- Epithet-based resolution ---------------------------------------
  dt[, `:=`(
    genus_resolved    = NA_character_,
    resolution_method = NA_character_
  )]

  epithet_map <- dt[
    !is.na(genus_full) & !is.na(epithet),
    .N,
    by = .(epithet, genus_full)
  ]

  resolved_strict <- epithet_map[
  dt[is_abbrev == TRUE],
  on = .(epithet),
  nomatch = 0
][
  startsWith(genus_full, genus_abbrev),
  .(genus_resolved = if (.N == 1) genus_full else NA_character_),
  by = .(id, species_clean)
][!is.na(genus_resolved)]

  dt[resolved_strict,
     `:=`(
       genus_resolved    = i.genus_resolved,
       resolution_method = "epithet"
     ),
     on = .(id, species_clean)
  ]

  ## ---- Positional inference -------------------------------------------
  setorder(dt, id)

  repeat {
    prev <- dt$genus_resolved

    dt[, `:=`(
      g_p1 = shift(genus_resolved,  1),
      g_p2 = shift(genus_resolved,  2),
      g_n1 = shift(genus_resolved, -1),
      g_n2 = shift(genus_resolved, -2)
    ), by = id]

    dt[
      is_abbrev & is.na(genus_resolved),
      genus_resolved := fifelse(
        !is.na(g_p1) & g_p1 == g_n1 & startsWith(g_p1, genus_abbrev), g_p1,
        fifelse(
          !is.na(g_p1) & g_p1 == g_p2 & startsWith(g_p1, genus_abbrev), g_p1,
          fifelse(
            !is.na(g_n1) & g_n1 == g_n2 & startsWith(g_n1, genus_abbrev), g_n1,
            fifelse(
              !is.na(g_p1) & startsWith(g_p1, genus_abbrev), g_p1,
              fifelse(
                !is.na(g_n1) & startsWith(g_n1, genus_abbrev), g_n1,
                NA_character_
              )
            )
          )
        )
      )
    ]

    if (identical(prev, dt$genus_resolved)) break
  }

  dt[
    is_abbrev & !is.na(genus_resolved) & is.na(resolution_method),
    resolution_method := "positional"
  ]

  dt[, c("g_p1", "g_p2", "g_n1", "g_n2") := NULL]

  ## ---- Block-wise propagation -----------------------------------------
  block_genus <- dt[
    is_abbrev & !is.na(genus_resolved),
    .(block_genus = unique(genus_resolved)),
    by = .(id, genus_abbrev)
  ][
    , .(block_genus = if (.N == 1) block_genus else NA_character_),
    by = .(id, genus_abbrev)
  ]

  dt[
    is_abbrev & is.na(genus_resolved),
    genus_resolved := block_genus[
      .SD,
      on = .(id, genus_abbrev),
      block_genus
    ]
  ]

  dt[
    is_abbrev & !is.na(genus_resolved) & is.na(resolution_method),
    resolution_method := "block"
  ]

  ## ---- Expand abbreviated names ---------------------------------------
  dt[
    is_abbrev & !is.na(genus_resolved),
    species_clean := paste(genus_resolved, epithet)
  ]

  ## ---- GBIF backbone resolution ---------------------------------------
  species_lookup <- unique(dt[, .(species_clean)])

  gbif_lookup <- tryCatch({

    gbif_dt <- as.data.table(
      rgbif::name_backbone_checklist(
        species_lookup$species_clean,
        verbose = FALSE
      )
    )

    setnames(gbif_dt, "verbatim_name", "species_clean")
    gbif_dt[, species_clean := tolower(species_clean)]

    gbif_lookup <- gbif_dt[
      rank == "SPECIES" &
      matchType %in% c("EXACT", "FUZZY") &
      !is.na(canonicalName),
      .(
        species_clean,
        speciesKey,
        gbif_canonical = tolower(canonicalName),
        phylum,
        class
      )
    ]

    gbif_accepted <- gbif_dt[
      rank == "SPECIES" &
      status == "ACCEPTED" &
      usageKey == speciesKey &
      !is.na(canonicalName),
      .(
        speciesKey,
        accepted_canonical = tolower(canonicalName),
        accepted_phylum    = phylum,
        accepted_class     = class
      )
    ]

    setkey(gbif_accepted, speciesKey)

    gbif_lookup[
      gbif_accepted,
      species_resolved := i.accepted_canonical,
      on = .(speciesKey)
    ]

    gbif_lookup[
      is.na(species_resolved),
      species_resolved := gbif_canonical
    ]

    gbif_lookup

  }, error = function(e) {

    message("GBIF backbone unavailable — skipping name resolution")

    species_lookup[, .(
      species_clean,
      species_resolved = species_clean,
      phylum = NA_character_,
      class  = NA_character_
    )]
  })

  ## ---- Taxonomic completion -------------------------------------------
  dt[
    gbif_lookup,
    `:=`(
      species_resolved = i.species_resolved,
      phylum = tolower(i.phylum),
      class  = tolower(i.class)
    ),
    on = "species_clean"
  ]

  dt[
    is.na(species_resolved),
    `:=`(
      species_resolved = species_clean,
      phylum = NA_character_,
      class  = NA_character_
    )
  ]

  gbif_lookup[, genus := sub(" .*", "", species_resolved)]

  genus_taxonomy <- unique(
    gbif_lookup[
      !is.na(phylum) | !is.na(class),
      .(genus, phylum = tolower(phylum), class = tolower(class))
    ]
  )

  dt[, genus := sub(" .*", "", species_resolved)]

  dt[
    genus_taxonomy,
    `:=`(
      phylum = fifelse(is.na(phylum), i.phylum, phylum),
      class  = fifelse(is.na(class),  i.class,  class)
    ),
    on = "genus"
  ]
  
  ## ---- Additional taxonomic completion -----------------------------------
  
  if (exists("gbif_dt", inherits = FALSE)) {
    
    additional_taxonomy <- gbif_dt[
      (matchType == "VARIANT" & rank == "SPECIES") |
        (species_clean == "chenopodium ambrosioides" &
           matchType == "HIGHERRANK"),
      .(
        species_clean,
        phylum = tolower(phylum),
        class = tolower(class)
      )
    ]
    
    dt[
      additional_taxonomy,
      `:=`(
        phylum = fcoalesce(phylum, i.phylum),
        class  = fcoalesce(class, i.class)
      ),
      on = "species_clean"
    ]
  }
  
  ## ---- Final table -----------------------------------------------------
  cols_to_keep <- c(
    "id",
    "species_name",
    "health_target",
    "mechanism",
    "study_location",
    "scale",
    "study_period",
    "doi",
    "species_resolved",
    "phylum",
    "class"
  )

  cols_present <- intersect(cols_to_keep, names(dt))

  dt[, cols_present, with = FALSE]
}

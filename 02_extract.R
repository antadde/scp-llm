# ------------------------------------------------------------
# 02_extract.R
# SCP extraction using LLM modules
# ------------------------------------------------------------

## ---- Setup -------------------------------------------------------------
set.seed(123) # make it reproducible

library(data.table)
library(ellmer)

invisible(lapply(list.files("utils", full.names = TRUE), source))

# If needed, set your OpenAI key: Sys.setenv(OPENAI_API_KEY = "your_key_here")

## ---- Data --------------------------------------------------------------
abs <- fread("output/01_abstracts.psv", sep = "|")

## ---- Module definitions ------------------------------------------------

# -- Species identification ----------------------------------------------
schema_species_list <- type_object(
  species = type_array(
    type_object(name = type_string("Valid Latin scientific species name"))
  )
)

prompt_species <- read_prompt("prompts/species_identification.txt")

make_llm_species <- function() {
  chat_openai(
    model = "gpt-4o-mini",
    system_prompt = prompt_species,
    params = params(temperature = 0, top_p = 1, max_output_tokens = 2048)
  )
}

# -- Species–Health links ----------------------------------------
schema_links_output <- type_object(
  output = type_array(
    type_object(
      species_name = type_string("Latin scientific species name."),
      links = type_array(
        type_object(
          health_target = type_string(
            "Named human infectious, vector-borne, or zoonotic disease."
          ),
          mechanism = type_enum(c(
            "Infectious agent",
            "Vector",
            "Reservoir host",
            "Intermediate host",
            "Medicinal use",
            "Biological control",
            "Other"
          ))
        )
      )
    )
  )
)

prompt_health_fixed   <- read_prompt("prompts/species_health_fixed.txt")
prompt_health_dynamic <- read_prompt("prompts/species_health_dynamic.txt")

make_llm_health <- function() {
  chat_openai(
    model = "gpt-4o-mini",
    system_prompt = prompt_health_fixed,
    params = params(temperature = 0, top_p = 1, max_output_tokens = 2048)
  )
}

# -- Contextual information ----------------------------------------------
schema_context <- type_object(
  study_location = type_string("Study location."),
  scale = type_enum(c(
    "Laboratory", "Local", "National", "Regional", "Global", "Unknown"
  )),
  study_period = type_string("Study period.")
)

prompt_context <- read_prompt("prompts/context.txt")

make_llm_context <- function() {
  chat_openai(
    model = "gpt-4o-mini",
    system_prompt = prompt_context,
    params = params(temperature = 0, top_p = 1, max_output_tokens = 2048)
  )
}

## ---- SCP extraction ----------------------------------------------------
run_scp_extraction <- function(text) {

  llm_species <- make_llm_species()
  llm_health  <- make_llm_health()
  llm_ctx     <- make_llm_context()

  species_res <- llm_species$chat_structured(
    text, type = schema_species_list
  )

  species_vec <- normalize_species_vector(species_res$species)
  if (length(species_vec) == 0L) {
    return(list(
      species_identification = species_res,
      species_health_links   = NULL,
      contextual_information = NULL
    ))
  }

  health_prompt <- fill_template(
    prompt_health_dynamic,
    values = list(
      TEXT         = text,
      SPECIES_LIST = paste(species_vec, collapse = ", ")
    )
  )

  health_res <- llm_health$chat_structured(
    health_prompt, type = schema_links_output
  )

  ctx_raw <- llm_ctx$chat_structured(text, type = schema_context)

  ctx <- list(
  study_location = if (!is.null(ctx_raw$study_location))
    ctx_raw$study_location else "Unknown",
  scale = if (!is.null(ctx_raw$scale))
    ctx_raw$scale else "Unknown",
  study_period = if (!is.null(ctx_raw$study_period))
    ctx_raw$study_period else "Unknown"
	)

  list(
    species_identification = species_res,
    species_health_links   = health_res,
    contextual_information = ctx
  )
}

## ---- Execution ---------------------------------------------------------
extract_one <- function(x) {
  out <- run_scp_extraction(x)
  Sys.sleep(1)
  out
}

n <- nrow(abs)
extracted_list <- vector("list", n)
context_list   <- vector("list", n)
scp_list       <- vector("list", n)

for (i in seq_len(n)) {

  print(i)

  res <- tryCatch(
    extract_one(abs$abstract[i]),
    error = function(e) {
      message("Error at index ", i, ": ", conditionMessage(e))
      NULL
    }
  )

  if (is.null(res)) next

  extracted_list[[i]] <- res
  context_list[[i]]   <- extract_context_fields(res)

  scp_list[[i]] <- if (is.null(res$species_health_links)) {
    data.frame()
  } else {
    flatten_scp_results(res$species_health_links$output)
  }
}

## ---- Assembly ----------------------------------------------------------
abs$extracted <- extracted_list
abs <- cbind(abs, do.call(rbind, context_list))
abs$scp <- scp_list

rows <- list()

for (i in seq_len(nrow(abs))) {

  scp_i <- abs$scp[[i]]
  if (!is.data.frame(scp_i) || nrow(scp_i) == 0) next

  meta <- abs[i, .(
    id, study_location, scale, study_period, doi
  )]

  for (j in seq_len(nrow(scp_i))) {
    rows[[length(rows) + 1]] <- cbind(meta, scp_i[j, , drop = FALSE])
  }
}

extracted <- if (length(rows)) rbindlist(rows) else data.table()

extracted[] <- lapply(extracted, function(x) tolower(as.character(x)))
setcolorder(extracted, c(
  "id", "species_name", "health_target", "mechanism",
  "study_location", "scale", "study_period", "doi"
))

## ---- Output ------------------------------------------------------------
fwrite(extracted, "output/02_extracted.psv", sep = "|")

# ------------------------------------------------------------
# 02_extract_fulltext.R
# SCP extraction from full-text .txt files using LLM modules
# ------------------------------------------------------------

## ---- Setup -------------------------------------------------------------
set.seed(123)

library(data.table)
library(ellmer)

invisible(lapply(list.files("utils", full.names = TRUE), source))

# Choose the LLM provider:
# "openai" = GPT-4o-mini
# "gemini" = Gemini 2.5 Flash

# provider <- "gemini"
provider <- "openai"

# Set API keys if needed:
# Sys.setenv(OPENAI_API_KEY = "")
# Sys.setenv(GEMINI_API_KEY = "")

## ---- Read full-text files ----------------------------------------------
fulltext_dir <- "input/OA_full_txts"

txt_files <- list.files(
  fulltext_dir,
  pattern = "\\.txt$",
  full.names = TRUE,
  ignore.case = TRUE
)

read_txt <- function(path) {
  
  raw_txt <- readBin(
    path,
    what = "raw",
    n = file.info(path)$size
  )
  
  # Remove null bytes
  raw_txt <- raw_txt[raw_txt != as.raw(0)]
  
  if (!length(raw_txt)) {
    return("")
  }
  
  txt <- rawToChar(raw_txt)
  
  # Convert to valid UTF-8
  txt <- iconv(
    txt,
    from = "",
    to = "UTF-8",
    sub = ""
  )
  
  # Basic cleaning
  txt <- gsub("\r\n?", "\n", txt)
  txt <- gsub("\u00A0", " ", txt, fixed = TRUE)
  txt <- gsub("[ \t]+", " ", txt)
  txt <- gsub("\n{3,}", "\n\n", txt)
  
  trimws(txt)
}

fulltexts <- data.table(
  id = tools::file_path_sans_ext(basename(txt_files)),
  full_text = vapply(txt_files, read_txt, character(1))
)


## ---- Module definitions ------------------------------------------------

# -- Species identification ----------------------------------------------
schema_species_list <- type_object(
  species = type_array(
    type_object(name = type_string("Valid Latin scientific species name"))
  )
)

prompt_species <- read_prompt("prompts/species_identification.txt")

make_llm_species_openai <- function() {
  chat_openai(
    model = "gpt-4o-mini",
    system_prompt = prompt_species,
    params = params(temperature = 0, top_p = 1, max_output_tokens = 2048)
  )
}

make_llm_species_gemini <- function() {
  chat_google_gemini(
    model = "gemini-2.5-flash",
    system_prompt = prompt_species,
    params = params(
      temperature = 0, top_p = 1, max_output_tokens = 8192
    )
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

make_llm_health_openai <- function() {
  chat_openai(
    model = "gpt-4o-mini",
    system_prompt = prompt_health_fixed,
    params = params(temperature = 0, top_p = 1, max_output_tokens = 2048)
  )
}

make_llm_health_gemini <- function() {
  chat_google_gemini(
    model = "gemini-2.5-flash",
    system_prompt = prompt_health_fixed,
    params = params(temperature = 0, top_p = 1, max_output_tokens = 8192)
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

make_llm_context_openai <- function() {
  chat_openai(
    model = "gpt-4o-mini",
    system_prompt = prompt_context,
    params = params(temperature = 0, top_p = 1, max_output_tokens = 2048)
  )
}

make_llm_context_gemini <- function() {
  chat_google_gemini(
    model = "gemini-2.5-flash",
    system_prompt = prompt_context,
    params = params(temperature = 0, top_p = 1, max_output_tokens = 8192)
  )
}

## ---- SCP extraction ----------------------------------------------------
run_scp_extraction <- function(text, provider = c("openai", "gemini")) {
  
  provider <- match.arg(provider)
  
  llm_species <- switch(
    provider,
    openai = make_llm_species_openai(),
    gemini = make_llm_species_gemini()
  )
  
  llm_health <- switch(
    provider,
    openai = make_llm_health_openai(),
    gemini = make_llm_health_gemini()
  )
  
  llm_ctx <- switch(
    provider,
    openai = make_llm_context_openai(),
    gemini = make_llm_context_gemini()
  )
  
  species_res <- llm_species$chat_structured(
    text, type = schema_species_list
  )
  
  species_vec <- normalize_species_vector(species_res$species)
  
  if (length(species_vec) == 0L) {
    return(list(
      provider               = provider,
      species_identification = species_res,
      species_health_links   = NULL,
      contextual_information = NULL
    ))
  }
  
  health_prompt <- fill_template(
    prompt_health_dynamic,
    values = list(
      TEXT = text,
      SPECIES_LIST = paste(species_vec, collapse = ", ")
    )
  )
  
  health_res <- llm_health$chat_structured(
    health_prompt, type = schema_links_output
  )
  
  ctx_raw <- llm_ctx$chat_structured(
    text, type = schema_context
  )
  
  ctx <- list(
    study_location = if (!is.null(ctx_raw$study_location))
      ctx_raw$study_location else "Unknown",
    scale = if (!is.null(ctx_raw$scale))
      ctx_raw$scale else "Unknown",
    study_period = if (!is.null(ctx_raw$study_period))
      ctx_raw$study_period else "Unknown"
  )
  
  list(
    provider               = provider,
    species_identification = species_res,
    species_health_links   = health_res,
    contextual_information = ctx
  )
}

## ---- Execution ---------------------------------------------------------
extract_one <- function(x, provider = c("openai", "gemini"),
                        max_tries = 6, base_wait = 20) {
  
  provider <- match.arg(provider)
  
  for (attempt in seq_len(max_tries)) {
    
    out <- tryCatch(
      run_scp_extraction(x, provider = provider),
      error = function(e) e
    )
    
    if (!inherits(out, "error")) {
      Sys.sleep(1)
      return(out)
    }
    
    msg <- conditionMessage(out)
    message("Attempt ", attempt, "/", max_tries, " failed: ", msg)
    
    if (grepl("503|429|premature EOF|lexical error|Too Many Requests|Service Unavailable", msg)) {
      Sys.sleep(base_wait * attempt)
    } else {
      stop(out)
    }
  }
  
  stop("Extraction failed after ", max_tries, " attempts.")
}

n <- nrow(fulltexts)
extracted_list <- vector("list", n)
context_list   <- vector("list", n)
scp_list       <- vector("list", n)

for (i in seq_len(n)) {
  
  print(i)
  
  res <- tryCatch(
    extract_one(fulltexts$full_text[i], provider = provider),
    error = function(e) {
      message("Error at index ", i, ": ", conditionMessage(e))
      NULL
    }
  )
  
  if (is.null(res)) {
    context_list[[i]] <- data.frame(
      study_location = NA_character_,
      scale = NA_character_,
      study_period = NA_character_
    )
    next
  }
  
  extracted_list[[i]] <- res
  context_list[[i]]   <- extract_context_fields(res)
  
  scp_list[[i]] <- if (is.null(res$species_health_links)) {
    data.frame()
  } else {
    flatten_scp_results(res$species_health_links$output)
  }
}

## ---- Assembly ----------------------------------------------------------
fulltexts$extracted <- extracted_list
fulltexts <- cbind(fulltexts, do.call(rbind, context_list))
fulltexts$scp <- scp_list

rows <- list()

for (i in seq_len(nrow(fulltexts))) {
  
  scp_i <- fulltexts$scp[[i]]
  if (!is.data.frame(scp_i) || nrow(scp_i) == 0) next
  
  meta <- fulltexts[i, .(
    id, study_location, scale, study_period
  )]
  
  for (j in seq_len(nrow(scp_i))) {
    rows[[length(rows) + 1]] <- cbind(meta, scp_i[j, , drop = FALSE])
  }
}

extracted <- if (length(rows)) rbindlist(rows) else data.table(
  id = character(), species_name = character(),
  health_target = character(), mechanism = character(),
  study_location = character(), scale = character(),
  study_period = character()
)

extracted[] <- lapply(extracted, function(x) tolower(as.character(x)))
setcolorder(extracted, c(
  "id", "species_name", "health_target", "mechanism",
  "study_location", "scale", "study_period"
))

## ---- Output ------------------------------------------------------------
# Remove embedded line breaks and repeated spaces
extracted[] <- lapply(extracted, function(x) {
  if (is.character(x)) {
    x <- gsub("[\r\n\t]+", " ", x)
    x <- gsub("\\s+", " ", x)
    trimws(x)
  } else {
    x
  }
})

fwrite(extracted, paste0("output/02_extracted_fulltext_", provider, ".psv"), sep = "|")
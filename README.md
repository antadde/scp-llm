# scp-llm

**A reproducible R workflow to extract, validate, and structure Species Contributions to People (SCP) from text using Large Language Models (LLMs)**

This repository accompanies the manuscript currently under review:

> Adde A. et al. *Towards a Species-Based Approach to One Health by Leveraging Large Language Models*.

The workflow implements a generalizable framework to consolidate biodiversity–health knowledge at the species level within a One Health perspective.

# Overview

The workflow transforms fragmented textual evidence into structured species–health records through four automated steps:

1. Corpus preparation  
2. LLM-based semantic extraction  
3. Validation  
4. Dataset assembly  

A proof-of-concept application is provided for human vector-borne and zoonotic diseases in the Amazon region.

The architecture is modular and can be adapted to other regions, corpora, and health domains.

# Requirements

- R ≥ 4.2  
- An OpenAI API key

Set your API key in R before running the workflow:

```{r}
Sys.setenv(OPENAI_API_KEY = "your_key_here")
```

For persistent configuration (recommended), add the following line to your `.Renviron` file:

```
OPENAI_API_KEY=your_key_here
```

## Required R packages

```{r}
library(data.table)
library(stringr)
library(httr)
library(jsonlite)
library(ellmer)
library(rgbif)
```

# Quick Start

All scripts assume the directory structure provided in this repository.

Run scripts sequentially:

```{r}
source("01_corpus.R")
source("02_extract.R")
source("03_validate.R")
source("04_assemble.R")
```

Outputs are written to the `/output` directory.

# Workflow Description

## 1. Corpus Preparation (`01_corpus.R`)

- Queries the OpenAlex API using a defined search string  
- Retrieves up to 5,000 documents  
- Extracts title, abstract, source, and DOI  
- Filters to retain only abstracts matching the query  

Output: `output/01_abstracts.psv`

Each row represents one abstract.

## 2. LLM-Based Semantic Extraction (`02_extract.R`)

Extraction is performed abstract-by-abstract using three modules:

- Species identification  
- Species–health linking  
- Contextual information retrieval  

Model configuration:

- Model: gpt-4o-mini  
- Temperature: 0  
- Top-p: 1  
- Max tokens: 2048

Prompts are constraint-driven and restrict extraction to:

- Valid Latin species names  
- Explicitly stated species–health links  
- Predefined mechanisms  
- Human vector-borne and zoonotic diseases  

Output: `output/02_extracted.psv`

Each row corresponds to one extracted SCP.

## 3. Validation (`03_validate.R`)

Validation operates at the SCP level.

Extracted records are compared to curated evidence across three axes:

- Species similarity  
- Health similarity  
- Mechanism similarity  

Scores are aggregated (0–1) and classified as:

- Strong ≥ 0.85  
- Moderate ≥ 0.6  
- Weak/Novel < 0.6  

An axis profile (e.g., SHM) summarizes similarity across components.

Output: `output/03_validated.psv`

## 4. Dataset Assembly (`04_assemble.R`)

The validated SCP table is restructured into a standardized long-format dataset (one row per SCP).

Each SCP includes:

- Unique identifier 
- Source document identifier  
- Taxonomic information (species, phylum, class)  
- Health target  
- Mechanism  
- Study location  
- Spatial scale  
- Study period  
- DOI  
- Validation class  
- Axis profile  
- Similarity scores  
- IPBES NCP classification  
- CICES ecosystem service classification  
- Direction of effect (−1 negative, +1 positive)  

Final output: `output/04_assembled.psv`

## Utility Functions

Helper functions used for preprocessing and harmonization are stored in `/utils`:

- `species_cleaner.R`
- `health_cleaner.R`

These ensure consistent terminology prior to validation and dataset assembly.

# Input Resources

The `/input` directory contains:

- `abstracts_testset.psv` – controlled benchmark abstracts  
- `manual_testset.psv` – manually curated SCP  
- `curated_evidence.psv` – validation reference dataset  
- `ncp_es.psv` – mapping to IPBES and CICES frameworks  

# Adapting the Framework

To apply the workflow to another context:

- Modify the OpenAlex query in `01_corpus.R`  
- Adjust prompt templates in `/prompts`  
- Update scope definitions (health targets, mechanisms)  
- Provide curated evidence for validation  
- Update contribution mapping table if needed  

The modular structure remains unchanged.

# Citation

If you use this workflow, please cite:

Adde A. et al. (2026). *scp-llm: Species Contributions to People extraction workflow* (Version 1.0). Zenodo. DOI forthcoming.

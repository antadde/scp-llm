# scp-llm

**A reproducible R workflow for extracting, validating, and structuring Species Contributions to People (SCP) from text using Large Language Models (LLMs)**

This repository accompanies the manuscript currently under review:

> Adde A. et al. *Toward a Species-Based Approach to One Health by Leveraging Large Language Models*.

The workflow provides a modular framework for consolidating biodiversity–health knowledge at the species level within a One Health perspective.

# Overview

The workflow transforms fragmented textual evidence into structured species–health records through four main steps:

1. Corpus preparation  
2. LLM-based semantic extraction  
3. Validation  
4. Dataset assembly  

A proof-of-concept application is provided for human vector-borne and zoonotic diseases in the Amazon region.

The workflow is intended as a methodological proof of concept. Its structure allows adaptation to other regions, scientific corpora, health domains, and evidence bases.

# Requirements

- R ≥ 4.2  
- An OpenAI or Google Gemini API key
- An OpenAlex API key

Set the required API keys in R before running the workflow:

```r
Sys.setenv(OPENAI_API_KEY = "your_key_here")
Sys.setenv(GEMINI_API_KEY = "your_key_here")
Sys.setenv(OPENALEX_API_KEY = "your_key_here")
```

Only the key corresponding to the selected provider is required.
For persistent configuration, add the relevant line to your `.Renviron` file:

```
OPENAI_API_KEY=your_key_here
GEMINI_API_KEY=your_key_here
OPENALEX_API_KEY=your_key_here
```

## Required R packages

```r
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

```r
source("01_corpus.R")
source("02_extract.R")
source("03_validate.R")
source("04_assemble.R")
```

Outputs are written to the `output/` directory.

## 1. Corpus Preparation (`01_corpus.R`)

- Queries the OpenAlex API using a defined search string  
- Retrieves up to 5,000 candidate documents  
- Extracts title, abstract, source, and DOI  
- Filters to retain only abstracts matching the query  

Output: `output/01_abstracts.psv`

Each row represents one abstract.

## 2. LLM-Based Semantic Extraction (`02_extract.R`)

Extraction is performed independently for each document using three modules:

- Species identification  
- Species–health linking  
- Contextual information retrieval

Two LLM providers are currently supported:

- OpenAI: GPT-4o-mini
- Google: Gemini 2.5 Flash

The provider can be selected directly in `02_extract.R`. The same prompts and extraction constraints are applied to both models.

The main model configuration is:

- Temperature: 0  
- Top-p: 1  
- Max tokens: 2048

Prompts restrict extraction to:

- Valid Latin species names explicitly mentioned in the source text
- Explicitly stated species–health relationships
- Human vector-borne and zoonotic diseases
- Predefined contribution mechanisms

Output: `output/02_extracted.psv`

Each row corresponds to one extracted SCP record.

## 3. Validation (`03_validate.R`)

Validation operates at the SCP level.

Extracted records are compared with curated evidence along three axes:

- Species similarity  
- Health similarity  
- Mechanism similarity  

The three similarity scores are aggregated into an overall score ranging from 0 to 1 and assigned to the following classes:

- Strong ≥ 0.85
- Moderate ≥ 0.6 and < 0.85
- Weak/Novel < 0.6  

An axis profile (e.g., SHM) summarizes which components of the extracted record agree with the curated evidence.

The validation class reflects correspondence with the available reference dataset. A weak/novel classification therefore does not necessarily indicate an incorrect extraction: it may also represent a relationship absent from the curated evidence.

Output: `output/03_validated.psv`

## 4. Dataset Assembly (`04_assemble.R`)

Validated records are restructured into a standardized long-format dataset containing one row per SCP.

Each record includes:

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

## Additional Analyses
### Cross-Model Comparison
The complete extraction and validation workflow was run independently using GPT-4o-mini and Gemini 2.5 Flash.

### Abstract–Full-Text Comparison
A control analysis compares SCP extraction from abstracts and full texts for 15 open-access papers. Both document types are processed using corresponding extraction (`02_extract_fulltext.R`) and validation (`03_validate_fulltext.R`) scripts based on the same workflow.

## Utility Functions

Helper functions for preprocessing and terminology harmonization are stored in `utils/`:

- `species_cleaner.R`
- `health_cleaner.R`

These functions standardize species and health terminology before validation and dataset assembly.

## Input Resources

The `/input` directory contains:

- `abstracts_testset.psv` – controlled benchmark abstracts  
- `manual_testset.psv` – manually curated SCP records  
- `curated_evidence.psv` – reference evidence used for validation  
- `ncp_es.psv` – mapping between contribution mechanisms, IPBES NCP categories, and CICES ecosystem services 

## Adapting the Framework

To apply the workflow to another research context:

- Modify the OpenAlex query in `01_corpus.R`  
- Adjust the prompt templates in `/prompts`
- Redefine the eligible health targets and contribution mechanisms
- Supply a context-appropriate curated evidence dataset
- Update the contribution-classification table where needed
- Reassess extraction performance using a manually curated benchmark

The modular workflow can be retained, but prompts, reference evidence, and validation thresholds should be evaluated for each new application.

# Limitations

Users should consider several limitations when interpreting the resulting dataset:

- Abstracts provide incomplete representations of the evidence reported in full articles.
- Corpus composition depends on the coverage and retrieval behaviour of OpenAlex.
- LLM outputs can vary across models and may include omissions or unsupported relationships.
- Validation results depend on the scope and completeness of the curated evidence.
- Terminological harmonization can merge or separate biologically related concepts imperfectly.
- Evidence strength is not equivalent to validation similarity and should be assessed separately before downstream use.

# Citation

If you use this workflow, please cite:

Adde A. et al. (2026). *scp-llm: Species Contributions to People extraction workflow* (Version 1.2). Zenodo. DOI forthcoming.
# scp-llm

**A reproducible R workflow for extracting, validating, and structuring Species Contributions to People (SCP) from text using Large Language Models (LLMs)**

This repository accompanies the manuscript:

> Adde A. et al. *Toward a species-based approach to One Health by leveraging large language models*.

The workflow provides a modular framework for consolidating biodiversity–health knowledge at the species level within a One Health perspective.

# Overview

The workflow transforms fragmented textual evidence into structured species–health records through four main steps:

1. Corpus preparation  
2. LLM-based semantic extraction  
3. Validation  
4. Dataset assembly  

A proof-of-concept application is provided for human vector-borne and zoonotic diseases in the Amazon region.

The workflow is intended as a methodological proof of concept. Its structure allows adaptation to other regions, scientific corpora, health domains, and evidence bases.

# Requirements and installation

Tested with **R 4.5.2** and `data.table` 1.18.6.1, `stringr` 1.6.0, `httr` 1.4.9, `jsonlite` 2.0.0, `ellmer` 0.5.2 and `rgbif` 3.9.0.

```r
install.packages(c("data.table", "stringr", "httr",
                   "jsonlite", "ellmer", "rgbif"))
```

## API keys and provider selection

Set credentials in your R environment or user-level `.Renviron` (`NAME=value`; restart R after editing):

- `OPENALEX_API_KEY`: corpus retrieval.
- `OPENAI_API_KEY`: OpenAI extraction.
- `GEMINI_API_KEY`: Gemini extraction.

Extraction needs only the selected provider's key. Validation uses the GBIF API through `rgbif`, without a key configured by these scripts.

Set `provider <- "openai"` or `provider <- "gemini"` inside each relevant script, using the same choice throughout:

| Script | Assignment line |
|---|---|
| `02_extract.R` | 19 |
| `03_validate.R` | 20 |
| `04_assemble.R` | 16 |
| `02_extract_fulltext.R` | 19 |
| `03_validate_fulltext.R` | 18 |

The default is OpenAI. A console assignment does not override the script settings.

# Quick Start

Download the [GitHub repository](https://github.com/antadde/scp-llm) and open R in its root, containing `01_corpus.R`, `input/`, `output/`, `prompts/` and `utils/`. Keep this directory structure, configure credentials and select the provider, then run:

```r
source("01_corpus.R")    # OpenAlex retrieval
source("02_extract.R")   # LLM extraction
source("03_validate.R")  # GBIF normalization and validation
source("04_assemble.R")  # Dataset assembly
```

Outputs are pipe-delimited files in `output/`; matching files are overwritten. Live extraction requires provider access and quota and may incur charges.

To reuse bundled results, skip retrieval to use `output/01_abstracts.psv`, or skip retrieval and extraction to validate archived extractions. Validation still uses GBIF. For an API-free replay, run only `04_assemble.R` with the matching provider's bundled validation output and `input/ncp_es.psv`.

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

Both providers use the same prompts and constraints. All three modules, in both abstract and full-text extraction, use temperature 0, top-p 1 and max_output_tokens 2048.

In the example, prompts restrict extraction to:

- Valid Latin species names explicitly mentioned in the source text
- Explicitly stated species–health relationships
- Human vector-borne and zoonotic diseases
- Predefined contribution mechanisms

Outputs: `output/02_extracted_openai.psv` or `output/02_extracted_gemini.psv`, according to the selected provider.

Each row corresponds to one extracted SCP record. The script appends `input/abstracts_testset.psv` to the corpus before extraction.

## 3. Validation (`03_validate.R`)

Validation operates at the SCP level, after GBIF species normalization.

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

Outputs: `output/03_validated_openai.psv` or `output/03_validated_gemini.psv`. Benchmark comparisons with `input/manual_testset.psv` remain in memory.

## 4. Dataset Assembly (`04_assemble.R`)

Validated records are restructured into a standardized long-format dataset containing one row per SCP.

Each record includes identifiers, taxonomy (species, phylum, class), health target, mechanism, study location, spatial scale, study period, DOI, validation class, axis profile and similarity scores. IPBES NCP and CICES ecosystem service classifications and direction of effect (−1 negative, +1 positive) are included where a framework mapping exists; mechanism `other` may have missing classifications and effect values.

Final outputs: `output/04_assembled_openai.psv` or `output/04_assembled_gemini.psv`.

## Additional Analyses
### Cross-Model Comparison
The complete extraction and validation workflow was run independently using GPT-4o-mini and Gemini 2.5 Flash.

### Abstract–Full-Text Comparison
A control analysis compares SCP extraction from abstracts and full texts for 15 open-access papers. Both document types are processed using corresponding extraction (`02_extract_fulltext.R`) and validation (`03_validate_fulltext.R`) scripts based on the same workflow.

For optional full-text analysis, place TXT files in `input/OA_full_txts/`; 15 are supplied. Filename stems become document IDs. PDFs are not converted by the workflow. Select the same provider in both scripts, then run:

```r
source("02_extract_fulltext.R")
source("03_validate_fulltext.R")
```

| Provider | Extraction output | Validation output |
|---|---|---|
| OpenAI | `output/02_extracted_fulltext_openai.psv` | `output/03_validated_fulltext_openai.psv` |
| Gemini | `output/02_extracted_fulltext_gemini.psv` | `output/03_validated_fulltext_gemini.psv` |

Only OpenAI full-text outputs are bundled. Skip extraction to validate them; validation still uses GBIF. Full-text assembly is not implemented: `04_assemble.R` processes abstract outputs.

## Utility Functions

Helper functions for preprocessing and terminology harmonization are stored in `utils/`:

- `species_cleaner.R`
- `health_cleaner.R`

These functions standardize species and health terminology before validation and dataset assembly.

## Input Resources

The `input/` directory contains:

- `abstracts_testset.psv` – controlled benchmark abstracts  
- `manual_testset.psv` – manually curated SCP records  
- `curated_evidence.psv` – reference evidence used for validation  
- `ncp_es.psv` – mapping between contribution mechanisms, IPBES NCP categories, and CICES ecosystem services 

## Adapting the Framework

To apply the workflow to another research context:

- Modify the OpenAlex query in `01_corpus.R`  
- Adjust the prompt templates in `prompts/`
- Redefine the eligible health targets and contribution mechanisms
- Supply a context-appropriate curated evidence dataset
- Update the contribution-classification table where needed
- Reassess extraction performance using a manually curated benchmark

The modular workflow can be retained, but prompts, reference evidence, and validation thresholds should be evaluated for each new application.

# Limitations

Users should consider several limitations when interpreting the resulting dataset:

- Abstracts provide incomplete representations of the evidence reported in full articles.
- Corpus composition depends on the coverage and retrieval behaviour of OpenAlex.
- Live LLM outputs may differ from archived results even with temperature 0 and a fixed seed, and may include omissions or unsupported relationships.
- Validation results depend on the scope and completeness of the curated evidence.
- Taxonomy resolution depends on GBIF; its backbone changes over time. Terminological harmonization can merge or separate biologically related concepts imperfectly.
- Evidence strength is not equivalent to validation similarity and should be assessed separately before downstream use.

# Citation

Adde A. et al. *Toward a Species-Based Approach to One Health by Leveraging Large Language Models*. Next Sustainability. https://doi.org/10.1016/j.nxsust.2026.100590

Accepted article; DOI reserved.

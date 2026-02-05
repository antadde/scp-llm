> ⚠️ **Work in progress**
> Documentation under construction.

# scp-llm

End-to-end workflow to extract, validate, and structure **Species Contributions to People (SCP)**
from text using large language models (LLMs) for One Health research.

## Pipeline
Run scripts in order:
1. `01_corpus.R` – retrieve and prepare candidate documents
2. `02_extract.R` – extract SCP using LLMs
3. `03_validate.R` – validate extracted SCP against curated evidence
4. `04_assemble.R` – assemble the final dataset

## Requirements
- R ≥ 4.2
- Required R packages:
  - data.table
  - stringr
  - httr
  - jsonlite
  - ellmer
  - rgbif
- OpenAI API key available as `OPENAI_API_KEY`

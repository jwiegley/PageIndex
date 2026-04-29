# PageIndex

Vectorless, reasoning-based RAG system by Vectify AI. Builds hierarchical tree indexes from PDFs and Markdown using LLM reasoning instead of vector embeddings.

## Development Commands

```bash
# Install dependencies
pip3 install --upgrade -r requirements.txt

# Set API key (create .env in project root)
echo 'CHATGPT_API_KEY=your_key' > .env

# Process a PDF
python3 run_pageindex.py --pdf_path /path/to/document.pdf

# Process Markdown
python3 run_pageindex.py --md_path /path/to/document.md

# Process with options
python3 run_pageindex.py --pdf_path doc.pdf --model gpt-4o-2024-11-20 \
  --max-pages-per-node 10 --max-tokens-per-node 20000 \
  --if-add-node-summary yes --if-add-doc-description no
```

There is no formal test framework. Reference outputs live in `tests/results/` as JSON files corresponding to PDFs in `tests/pdfs/`. Validate changes by running against these documents and comparing output structure.

Output JSON is written to `./results/`. Logs (JSON format) are written to `./logs/`.

## Architecture

### Module Responsibilities

- **`run_pageindex.py`** — CLI entry point. Parses args, routes to PDF or Markdown pipeline, saves JSON output.
- **`pageindex/page_index.py`** — PDF processing engine. TOC detection, extraction, page mapping, tree construction, verification, and self-healing correction.
- **`pageindex/page_index_md.py`** — Markdown processing. Parses `#` headers into hierarchy, optional tree thinning, summary generation.
- **`pageindex/utils.py`** — Shared utilities: OpenAI API wrappers (sync/async), PDF text extraction, token counting, tree operations, JSON parsing, config loading, logging.
- **`pageindex/__init__.py`** — Re-exports via `from .page_index import *` and `from .page_index_md import md_to_tree`.

### PDF Processing Pipeline (Fallback Chain)

`page_index_main()` → `tree_parser()` → `meta_processor()` which tries three strategies in order:

1. **`process_toc_with_page_numbers`** — Extracts embedded TOC, maps logical page numbers to physical PDF pages by calculating an offset from sampled page pairs.
2. **`process_toc_no_page_numbers`** — Uses embedded TOC structure but has the LLM locate each section's starting page by scanning document text.
3. **`process_no_toc`** — No TOC found; the LLM generates a hierarchical structure from scratch by reading page groups.

After extraction, `verify_toc()` samples sections and checks via LLM whether titles actually appear at the claimed pages. If accuracy > 60%, `fix_incorrect_toc_with_retries()` corrects individual errors (up to 3 attempts). If accuracy ≤ 60%, the system falls back to the next strategy.

Large leaf nodes (exceeding `max_page_num_each_node` AND `max_token_num_each_node`) are recursively subdivided via `process_large_node_recursively()`.

### Markdown Processing Pipeline

`md_to_tree()` → parse `#` headers (skipping code blocks) → extract text between headers → optional tree thinning (merge nodes below token threshold) → build hierarchy via stack-based algorithm → optional LLM summary generation.

### Config System

Three-tier precedence (highest wins): function arguments → `config.yaml` defaults → hardcoded fallbacks.

`ConfigLoader` (in utils.py) loads `pageindex/config.yaml`, validates keys, and merges with user options into a `SimpleNamespace` object. **Note:** `SimpleNamespace` is imported as `config` in utils.py (`from types import SimpleNamespace as config`), so `config(...)` throughout the codebase is constructing a `SimpleNamespace`.

The API key is read from the `CHATGPT_API_KEY` environment variable (not `OPENAI_API_KEY`), loaded via `python-dotenv` at module import time.

### Async Pattern

The public API (`page_index()`, `page_index_main()`) is synchronous — it defines an inner async function and calls `asyncio.run()`. Internally, LLM calls are concurrent via `asyncio.gather()` for verification, summary generation, and error correction. `md_to_tree()` is natively async; the CLI wraps it with `asyncio.run()`.

### LLM Interaction Pattern

All LLM calls follow: structured prompt with JSON response format instructions → `ChatGPT_API()` or `ChatGPT_API_async()` with 10 retries and 1s delay → `extract_json()` which handles ````json` fences, `None`→`null` replacement, trailing comma cleanup, and whitespace normalization. Prompts consistently end with "Directly return the final JSON structure. Do not output anything else."

### Tree Node Structure (PDF)

```json
{
  "title": "Section Name",
  "node_id": "0001",
  "start_index": 5,
  "end_index": 12,
  "summary": "LLM-generated description...",
  "nodes": []
}
```

`start_index`/`end_index` are 1-based physical PDF page numbers. `node_id` is zero-padded to 4 digits. `nodes` contains children (omitted when empty for PDF, present as `[]` during markdown processing).

### Physical vs Logical Page Mapping

PDFs often have printed page numbers (logical) that differ from the actual PDF page index (physical) due to front matter. The system extracts both, finds matching title/page pairs, computes the most common offset via `calculate_page_offset()`, then applies it to all TOC entries via `add_page_offset_to_toc_json()`.

### Key Dependencies

- **openai** — All LLM calls go through OpenAI's API (sync and async clients)
- **PyPDF2** — Default PDF text extraction
- **pymupdf** — Alternative PDF parser (selectable via `pdf_parser` param in `get_page_tokens()`)
- **tiktoken** — Token counting for node size management
- **pyyaml** — Config file parsing
- **python-dotenv** — `.env` file loading for API key

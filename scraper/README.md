# Mining Knowledge-Base Scraper

Collects publicly available mining safety, regulation, and environmental
documents for the Zambia mining safety assistant prototype, and turns them
into a RAG-ready knowledge base.

## How it works

```
sources.json  ->  scraper.py  ->  data/raw/ + data/manifest.json
                                       |
                                  extract.py
                                       |
                          data/knowledge_base.jsonl
```

1. **scraper.py** visits each seed URL in `sources.json`, follows links on
   the same domain (up to `max_depth`), downloads every PDF it finds, and
   saves the text of relevant HTML pages. It respects `robots.txt` and waits
   `delay_seconds` between requests.
2. **extract.py** reads everything the scraper downloaded, extracts text
   from PDFs, splits it into ~1200-character overlapping chunks, and writes
   `data/knowledge_base.jsonl`. Every chunk carries its source name and URL
   so the assistant can cite where an answer came from.

## Setup

```
pip install -r requirements.txt
```

## Usage

```
python scraper.py                 # crawl all sources
python scraper.py --source ZEMA   # crawl only sources matching "ZEMA"
python extract.py                 # build data/knowledge_base.jsonl
```

Re-running is safe: the manifest is updated in place and extract.py rebuilds
the knowledge base from scratch each time.

## Adding sources

Edit `sources.json` and add an entry:

```json
{
  "name": "Mine Safety Department",
  "url": "https://example.gov.zm/safety",
  "tags": ["safety", "government"]
}
```

Direct PDF links also work as seeds.

## Next step: RAG

Load `data/knowledge_base.jsonl`, embed each chunk (e.g. with
sentence-transformers), store the vectors in Chroma/FAISS/Qdrant, and at
query time retrieve the top matches and pass them to an LLM along with the
user's question. The `source`/`url` fields let the assistant cite the
original document in its answer.

## Notes

- Only public pages are collected; content behind logins is never accessed.
- Check each site's terms of use before redistributing its documents.
- Government sites in the config can be slow or intermittently offline —
  re-run later if a source times out.

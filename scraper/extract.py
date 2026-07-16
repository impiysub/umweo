"""Turn downloaded documents into a RAG-ready knowledge base.

Reads every file listed in data/manifest.json, extracts plain text from PDFs,
splits everything into overlapping chunks, and writes them to
data/knowledge_base.jsonl — one JSON object per chunk, each carrying its
source name and URL so the assistant can cite where an answer came from.

Usage:
    python extract.py
"""

import json
from pathlib import Path

from pypdf import PdfReader

BASE_DIR = Path(__file__).parent
MANIFEST_PATH = BASE_DIR / "data" / "manifest.json"
OUTPUT_PATH = BASE_DIR / "data" / "knowledge_base.jsonl"

CHUNK_SIZE = 1200   # characters per chunk
CHUNK_OVERLAP = 200  # characters repeated between neighbouring chunks


def pdf_to_text(path: Path) -> str:
    reader = PdfReader(path)
    pages = []
    for page in reader.pages:
        try:
            pages.append(page.extract_text() or "")
        except Exception:
            pages.append("")
    return "\n".join(pages)


def chunk_text(text: str) -> list[str]:
    text = " ".join(text.split())  # collapse whitespace
    if not text:
        return []
    chunks = []
    start = 0
    while start < len(text):
        end = start + CHUNK_SIZE
        # Try to break at a sentence boundary near the end of the chunk.
        if end < len(text):
            dot = text.rfind(". ", start + CHUNK_SIZE // 2, end)
            if dot != -1:
                end = dot + 1
        chunks.append(text[start:end].strip())
        start = max(end - CHUNK_OVERLAP, start + 1)
    return [c for c in chunks if len(c) > 50]


def main() -> None:
    if not MANIFEST_PATH.exists():
        print("No manifest found — run scraper.py first.")
        return

    with open(MANIFEST_PATH, encoding="utf-8") as f:
        manifest = json.load(f)

    total_chunks = 0
    skipped = 0
    with open(OUTPUT_PATH, "w", encoding="utf-8") as out:
        for url, meta in manifest.items():
            path = BASE_DIR / meta["file"]
            if not path.exists():
                skipped += 1
                continue

            if meta["type"] == "pdf":
                try:
                    text = pdf_to_text(path)
                except Exception as e:
                    print(f"[skip] {path.name}: {e}")
                    skipped += 1
                    continue
            else:
                text = path.read_text(encoding="utf-8", errors="ignore")

            chunks = chunk_text(text)
            for i, chunk in enumerate(chunks):
                record = {
                    "id": f"{path.stem}_{i}",
                    "text": chunk,
                    "source": meta["source"],
                    "url": url,
                    "tags": meta.get("tags", []),
                    "title": meta.get("title", path.name),
                }
                out.write(json.dumps(record, ensure_ascii=False) + "\n")
            total_chunks += len(chunks)
            print(f"[ok] {path.name}: {len(chunks)} chunks")

    print(f"\nWrote {total_chunks} chunks to {OUTPUT_PATH} ({skipped} files skipped)")


if __name__ == "__main__":
    main()

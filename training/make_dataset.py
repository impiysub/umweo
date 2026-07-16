"""Build a fine-tuning dataset from the scraped knowledge base.

Reads scraper/data/knowledge_base.jsonl and converts each chunk into
chat-format training examples (system / user / assistant messages) that
Kaggle's GPU notebook can train on directly.

Usage:
    python make_dataset.py
Output:
    train.jsonl  (upload this to Kaggle as a dataset)
"""

import json
import random
from pathlib import Path

BASE_DIR = Path(__file__).parent
KNOWLEDGE_BASE = BASE_DIR.parent / "scraper" / "data" / "knowledge_base.jsonl"
OUTPUT = BASE_DIR / "train.jsonl"

SYSTEM_PROMPT = (
    "You are UMWEO AI, a friendly mining assistant for artisanal and "
    "small-scale miners in Zambia. You explain mining safety, regulations, "
    "and good practices in simple, clear language. You always mention the "
    "source of your information."
)

# Question templates. {topic} is filled from the document title/tags.
TEMPLATES = [
    "What can you tell me about {topic}?",
    "Explain {topic} in simple terms.",
    "I am a small-scale miner. What should I know about {topic}?",
    "What does the guidance say about {topic}?",
]


def topic_from(meta_title: str, tags: list[str]) -> str:
    title = meta_title.split("|")[0].split("-")[0].strip()
    if len(title) > 8:
        return title
    return ", ".join(tags) if tags else "this subject"


def main() -> None:
    if not KNOWLEDGE_BASE.exists():
        print(f"Knowledge base not found: {KNOWLEDGE_BASE}")
        print("Run the scraper and extract.py first.")
        return

    random.seed(42)
    examples = []
    with open(KNOWLEDGE_BASE, encoding="utf-8") as f:
        for line in f:
            chunk = json.loads(line)
            text = chunk["text"]
            if len(text) < 200:  # too short to teach anything
                continue
            topic = topic_from(chunk.get("title", ""), chunk.get("tags", []))
            question = random.choice(TEMPLATES).format(topic=topic)
            answer = f"{text}\n\n(Source: {chunk['source']})"
            examples.append(
                {
                    "messages": [
                        {"role": "system", "content": SYSTEM_PROMPT},
                        {"role": "user", "content": question},
                        {"role": "assistant", "content": answer},
                    ]
                }
            )

    random.shuffle(examples)
    with open(OUTPUT, "w", encoding="utf-8") as out:
        for ex in examples:
            out.write(json.dumps(ex, ensure_ascii=False) + "\n")

    print(f"Wrote {len(examples)} training examples to {OUTPUT}")
    print("Next: upload train.jsonl to Kaggle as a dataset named 'umweo-mining-data'")


if __name__ == "__main__":
    main()

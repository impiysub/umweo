"""UMWEO AI - RAG backend powered by our own fine-tuned model.

Answers mining questions from the scraped knowledge base:
1. Loads scraper/data/knowledge_base.jsonl (3,500+ chunks with sources).
2. Finds the passages most relevant to the question (BM25 keyword search).
3. UMWEO's own fine-tuned model (Qwen2.5-1.5B + our Kaggle-trained LoRA
   adapter in ../umweo-flora) writes a simple answer from those passages.

If the model is not downloaded/enabled yet, the API still works in
retrieval-only mode: it returns the most relevant document passage directly.

Run (retrieval-only):
    uvicorn main:app --host 0.0.0.0 --port 8000

Run (with our own model - after `python download_model.py`):
    $env:USE_OWN_MODEL = "1"
    uvicorn main:app --host 0.0.0.0 --port 8000

Endpoints:
    GET  /health
    POST /ask   {"question": "...", "language": "english"}
"""

import json
import os
import re
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from rank_bm25 import BM25Okapi

BASE_DIR = Path(__file__).parent
KNOWLEDGE_BASE = BASE_DIR.parent / "scraper" / "data" / "knowledge_base.jsonl"
ADAPTER_DIR = BASE_DIR.parent / "umweo-flora"  # our Kaggle-trained adapter
BASE_MODEL = "Qwen/Qwen2.5-1.5B-Instruct"
TOP_K = 4  # passages given to the model per question

SYSTEM_PROMPT = (
    "You are UMWEO AI, a friendly mining assistant for artisanal and "
    "small-scale miners in Zambia. Answer using the reference passages "
    "provided. Explain in simple, clear language - short sentences, "
    "step-by-step where helpful. Mention which source your answer comes "
    "from. For emergencies, always advise contacting local authorities or "
    "the Mine Safety Department."
)

app = FastAPI(title="UMWEO AI - Mining Assistant API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # demo only - restrict in production
    allow_methods=["*"],
    allow_headers=["*"],
)


def tokenize(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


# ---- Load knowledge base and build the search index at startup ----
chunks: list[dict] = []
with open(KNOWLEDGE_BASE, encoding="utf-8") as f:
    for line in f:
        chunks.append(json.loads(line))

bm25 = BM25Okapi([tokenize(c["text"]) for c in chunks])
print(f"Knowledge base loaded: {len(chunks)} chunks")

# ---- Our own model (Qwen base + UMWEO LoRA adapter) ----
model = None
model_tokenizer = None
if os.environ.get("USE_OWN_MODEL") == "1":
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    print("Loading UMWEO model (this takes a minute on first start)...")
    model_tokenizer = AutoTokenizer.from_pretrained(BASE_MODEL)
    model = AutoModelForCausalLM.from_pretrained(
        BASE_MODEL, torch_dtype=torch.float32
    )
    if ADAPTER_DIR.exists():
        from peft import PeftModel

        model = PeftModel.from_pretrained(model, str(ADAPTER_DIR))
        print(f"UMWEO adapter loaded from {ADAPTER_DIR}")
    else:
        print(f"WARNING: adapter not found at {ADAPTER_DIR} - using base model")
    model.eval()
    print("UMWEO model ready")
else:
    print("USE_OWN_MODEL not set - running in retrieval-only mode")


class Question(BaseModel):
    question: str
    language: str = "english"


def retrieve(question: str, k: int = TOP_K) -> list[dict]:
    scores = bm25.get_scores(tokenize(question))
    ranked = sorted(range(len(chunks)), key=lambda i: scores[i], reverse=True)
    return [chunks[i] for i in ranked[:k] if scores[i] > 0]


def sources_of(passages: list[dict]) -> list[dict]:
    seen = {}
    for p in passages:
        seen.setdefault(p["url"], {"source": p["source"], "url": p["url"]})
    return list(seen.values())


def generate_answer(question: str, passages: list[dict], language: str) -> str:
    import torch

    context = "\n\n".join(
        f"[Passage {i + 1} - from {p['source']}]\n{p['text']}"
        for i, p in enumerate(passages)
    )
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {
            "role": "user",
            "content": (
                f"Reference passages:\n\n{context}\n\n"
                f"Question: {question}\n\nAnswer in {language}."
            ),
        },
    ]
    prompt = model_tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    inputs = model_tokenizer(prompt, return_tensors="pt", truncation=True, max_length=3072)
    with torch.no_grad():
        output = model.generate(
            **inputs,
            max_new_tokens=350,
            do_sample=False,
            pad_token_id=model_tokenizer.eos_token_id,
        )
    new_tokens = output[0][inputs["input_ids"].shape[1]:]
    return model_tokenizer.decode(new_tokens, skip_special_tokens=True).strip()


@app.get("/health")
def health():
    return {
        "status": "ok",
        "chunks": len(chunks),
        "model": "umweo (own fine-tuned)" if model else "retrieval-only",
    }


@app.post("/ask")
def ask(q: Question):
    passages = retrieve(q.question)
    if not passages:
        return {
            "answer": (
                "I could not find information about that in my documents. "
                "Please ask about mining safety, licensing, environment, or "
                "gold and copper mining practices."
            ),
            "sources": [],
            "mode": "no_match",
        }

    if model is None:
        best = passages[0]
        return {
            "answer": f"{best['text']}\n\n(Source: {best['source']})",
            "sources": sources_of(passages),
            "mode": "retrieval_only",
        }

    answer = generate_answer(q.question, passages, q.language)
    return {
        "answer": answer,
        "sources": sources_of(passages),
        "mode": "umweo_model",
    }

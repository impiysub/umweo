"""UMWEO AI - RAG backend for Zambian small-scale miners.

How a question is answered:
1. BM25 retrieval finds relevant passages in our scraped knowledge base
   (scraper/data/knowledge_base.jsonl - 3,500+ chunks with sources).
2. SerpAPI searches the web for Zambia-specific information (licences,
   PACRA, ZRA, ZEMA, prices) when a SERP_API_KEY is set.
3. A model writes a simple, cited answer from both:
   our own fine-tuned model (USE_OWN_MODEL=1), or Gemini (LLM_API_KEY).
If no model is reachable, the API falls back to quoting the best passage.

Run:
    uvicorn main:app --host 0.0.0.0 --port 8000

Endpoints:
    GET  /health
    POST /ask   {"question": "...", "language": "english"}
"""

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from rank_bm25 import BM25Okapi

BASE_DIR = Path(__file__).parent
KNOWLEDGE_BASE = BASE_DIR.parent / "scraper" / "data" / "knowledge_base.jsonl"
ADAPTER_DIR = BASE_DIR.parent / "umweo-flora"  # our Kaggle-trained adapter
BASE_MODEL = "Qwen/Qwen2.5-1.5B-Instruct"
TOP_K = 4  # knowledge-base passages given to the model per question

SYSTEM_PROMPT = (
    "You are UMWEO AI, a friendly mining assistant for artisanal and "
    "small-scale miners in ZAMBIA. Answer ANY mining-related question. "
    "You are given reference passages from mining guidance documents and, "
    "when available, live web search results - use both, and prefer "
    "official Zambian sources (Ministry of Mines, PACRA, ZRA, ZEMA) for "
    "Zambia-specific topics like licences, registration, and taxes. "
    "If the user greets you or makes small talk, reply warmly and briefly. "
    "If a question has nothing to do with mining, answer briefly and "
    "kindly steer back to mining topics. Explain in simple, clear "
    "language - short sentences, step-by-step where helpful. Say where "
    "your information comes from. For emergencies, always advise "
    "contacting local authorities or the Mine Safety Department."
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

# ---- Cloud LLM (Gemini via its OpenAI-compatible endpoint) ----
LLM_API_KEY = os.environ.get("LLM_API_KEY", "").strip()
LLM_API_URL = os.environ.get(
    "LLM_API_URL",
    "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
)
LLM_MODEL = os.environ.get("LLM_MODEL", "gemini-flash-latest")
# Tried when the main model is overloaded or errors.
LLM_FALLBACK_MODEL = os.environ.get("LLM_FALLBACK_MODEL", "gemini-flash-lite-latest")

# ---- Web search (SerpAPI) ----
SERP_API_KEY = os.environ.get("SERP_API_KEY", "").strip()

if LLM_API_KEY:
    print(f"Cloud LLM enabled: {LLM_MODEL}")
if SERP_API_KEY:
    print("Web search enabled (SerpAPI)")
if model is None and not LLM_API_KEY:
    print("Running in retrieval-only mode")

last_llm_error: str | None = None
_search_cache: dict[str, tuple[list[str], list[dict]]] = {}


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
        seen.setdefault(
            p["source"],
            {"source": p["source"], "url": p["url"], "type": "document"},
        )
    return list(seen.values())


def web_search(question: str) -> tuple[list[str], list[dict]]:
    """Search the web via SerpAPI, biased to Zambia. Returns (snippets, links).

    Results are cached in memory - the free plan allows 250 searches/month.
    """
    if not SERP_API_KEY:
        return [], []
    query = question if "zambia" in question.lower() else f"{question} Zambia"
    cache_key = query.lower().strip()
    if cache_key in _search_cache:
        return _search_cache[cache_key]

    params = urllib.parse.urlencode(
        {
            "engine": "google",
            "q": query,
            "num": 5,
            "hl": "en",
            "gl": "zm",
            "api_key": SERP_API_KEY,
        }
    )
    snippets: list[str] = []
    links: list[dict] = []
    try:
        with urllib.request.urlopen(
            f"https://serpapi.com/search.json?{params}", timeout=30
        ) as resp:
            data = json.loads(resp.read())
        answer_box = data.get("answer_box") or {}
        if answer_box.get("snippet"):
            snippets.append(f"[Web answer]\n{answer_box['snippet']}")
        for r in data.get("organic_results", [])[:5]:
            if r.get("snippet"):
                title = r.get("title", "web result")
                snippets.append(f"[Web - {title}]\n{r['snippet']}")
                if r.get("link"):
                    links.append(
                        {"source": title, "url": r["link"], "type": "web"}
                    )
        _search_cache[cache_key] = (snippets, links[:4])
    except Exception as e:
        print(f"Web search error: {e}")
    return snippets, links[:4]


def build_user_text(
    question: str, passages: list[dict], web_snippets: list[str], language: str
) -> str:
    if passages:
        doc_context = "\n\n".join(
            f"[Passage {i + 1} - from {p['source']}]\n{p['text']}"
            for i, p in enumerate(passages)
        )
    else:
        doc_context = "(no matching document passages)"
    web_context = "\n\n".join(web_snippets) if web_snippets else "(no web results)"
    return (
        f"Reference passages from mining documents:\n\n{doc_context}\n\n"
        f"Live web search results:\n\n{web_context}\n\n"
        f"User message: {question}\n\nAnswer in {language}."
    )


def ask_cloud_llm(user_text: str) -> str | None:
    """Answer via Gemini. Tries the main model, then the fallback model."""
    global last_llm_error

    for model_name in [LLM_MODEL, LLM_FALLBACK_MODEL]:
        payload = json.dumps(
            {
                "model": model_name,
                "messages": [
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user", "content": user_text},
                ],
                # Generous cap: Gemini spends part of this budget on internal
                # reasoning before writing the visible answer.
                "max_tokens": 2500,
                "reasoning_effort": "low",
            }
        ).encode("utf-8")
        req = urllib.request.Request(
            LLM_API_URL,
            data=payload,
            headers={
                "Authorization": f"Bearer {LLM_API_KEY}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                data = json.loads(resp.read())
            answer = data["choices"][0]["message"]["content"].strip()
            if answer:
                last_llm_error = None
                return answer
            last_llm_error = f"{model_name}: empty answer"
        except urllib.error.HTTPError as e:
            last_llm_error = (
                f"{model_name} HTTP {e.code}: {e.read().decode(errors='ignore')[:200]}"
            )
        except Exception as e:
            last_llm_error = f"{model_name} {type(e).__name__}: {e}"
        print(f"Cloud LLM error: {last_llm_error}")
    return None


def generate_answer(user_text: str) -> str:
    """Answer with our own fine-tuned model."""
    import torch

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user_text},
    ]
    prompt = model_tokenizer.apply_chat_template(
        messages, tokenize=False, add_generation_prompt=True
    )
    inputs = model_tokenizer(
        prompt, return_tensors="pt", truncation=True, max_length=3072
    )
    with torch.no_grad():
        output = model.generate(
            **inputs,
            max_new_tokens=350,
            do_sample=False,
            pad_token_id=model_tokenizer.eos_token_id,
        )
    new_tokens = output[0][inputs["input_ids"].shape[1]:]
    return model_tokenizer.decode(new_tokens, skip_special_tokens=True).strip()


def make_snippet(question: str, text: str, max_sentences: int = 4) -> str:
    """Trim a raw chunk to whole sentences focused on the question."""
    q_tokens = set(tokenize(question))
    sentences = re.split(r"(?<=[.!?])\s+", text.strip())
    if len(sentences) > 1 and sentences[0] and not sentences[0][0].isupper() \
            and not sentences[0][0].isdigit():
        sentences = sentences[1:]
    if not sentences:
        return text
    overlaps = [len(q_tokens & set(tokenize(s))) for s in sentences]
    best = max(range(len(sentences)), key=lambda i: overlaps[i])
    window = sentences[best:best + max_sentences]
    return " ".join(window).strip()


GREETING = re.compile(
    r"^(hi|hello|hey|hallo|muli ?bwanji|muli ?shani|mulishani|mwashibukeni"
    r"|mwapoleni|mwabuka buti|shani|bwanji|good (morning|afternoon|evening)"
    r"|how are you|thanks?( you)?|zikomo|natotela|twalumba|ok(ay)?|yes|no)\b[\s!.?]*$",
    re.IGNORECASE,
)

WELCOME_REPLY = (
    "Hello! I am UMWEO AI, your mining assistant. Ask me a question about "
    "mining safety, licences, the environment, or gold and copper mining - "
    "for example: 'What PPE do I need?' or 'How do I manage tailings safely?'"
)


# ---- Daily mining tips (rotates by day; Ministry-editable in production) ----
TIPS = [
    "Check your pit walls every morning before work. Cracks, bulges, or "
    "water seeping out are warning signs - do not enter until it is safe.",
    "Always wear your hard hat, boots, and dust mask. Most mining injuries "
    "happen to miners not wearing protective equipment.",
    "Never work alone underground. Always have a partner who knows where "
    "you are and can call for help.",
    "Support tunnel roofs with proper timber. If the roof drips or cracks "
    "after rain, stay out until it is inspected.",
    "Mercury harms you and your family. Ask about mercury-free gold "
    "processing methods like gravity concentration and borax smelting.",
    "Backfill old pits and trenches. Open pits collect stagnant water, "
    "which breeds mosquitoes and can drown children and livestock.",
    "Keep a first aid kit at the mine site and learn how to treat crush "
    "injuries, cuts, and heat exhaustion before help arrives.",
]

FEEDBACK_FILE = BASE_DIR / "data" / "feedback.jsonl"


class Feedback(BaseModel):
    helpful: bool | None = None
    mining_type: str | None = None
    challenge: str | None = None
    contact_requested: bool | None = None
    survey_question: str | None = None
    survey_answer: str | None = None
    question: str | None = None
    language: str = "english"


@app.get("/")
def home():
    return FileResponse(BASE_DIR / "static" / "index.html")


@app.get("/tip")
def tip():
    import datetime

    day = datetime.date.today().toordinal()
    return {"tip": TIPS[day % len(TIPS)]}


@app.get("/tips")
def all_tips():
    return {"tips": TIPS}


@app.post("/feedback")
def submit_feedback(fb: Feedback):
    import datetime

    FEEDBACK_FILE.parent.mkdir(parents=True, exist_ok=True)
    record = fb.model_dump()
    record["timestamp"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    with open(FEEDBACK_FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
    return {"status": "recorded"}


@app.get("/feedback")
def list_feedback():
    """Ministry view: everything miners have reported."""
    if not FEEDBACK_FILE.exists():
        return {"count": 0, "entries": []}
    entries = [
        json.loads(line)
        for line in FEEDBACK_FILE.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    return {"count": len(entries), "entries": entries}


@app.get("/health")
def health():
    if model is not None:
        brain = "umweo (own fine-tuned)"
    elif LLM_API_KEY:
        brain = f"cloud ({LLM_MODEL})"
    else:
        brain = "retrieval-only"
    return {
        "status": "ok",
        "chunks": len(chunks),
        "model": brain,
        "web_search": bool(SERP_API_KEY),
        "last_llm_error": last_llm_error,
    }


@app.post("/ask")
def ask(q: Question):
    passages = retrieve(q.question)
    web_snippets, web_links = web_search(q.question)
    user_text = build_user_text(q.question, passages, web_snippets, q.language)
    all_sources = sources_of(passages) + web_links

    # 1. Our own fine-tuned model (when enabled and loaded)
    if model is not None:
        answer = generate_answer(user_text)
        return {"answer": answer, "sources": all_sources, "mode": "umweo_model"}

    # 2. Gemini writes the answer from our documents + web results
    if LLM_API_KEY:
        answer = ask_cloud_llm(user_text)
        if answer:
            return {"answer": answer, "sources": all_sources, "mode": "cloud_ai"}

    # 3. Offline emergency fallbacks (no AI reachable)
    if GREETING.match(q.question.strip()):
        return {"answer": WELCOME_REPLY, "sources": [], "mode": "greeting"}
    if not passages:
        return {
            "answer": (
                "I could not find information about that in my documents, "
                "and the AI service is unreachable right now. Please ask "
                "about mining safety, licensing, environment, or gold and "
                "copper mining practices."
            ),
            "sources": [],
            "mode": "no_match",
        }
    best = passages[0]
    snippet = make_snippet(q.question, best["text"])
    return {
        "answer": f"{snippet}\n\n(Source: {best['source']})",
        "sources": sources_of(passages),
        "mode": "retrieval_only",
    }

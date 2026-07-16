# UMWEO AI — Kaggle Training Kit

Fine-tunes a small open model (Qwen2.5-1.5B-Instruct) on the scraped mining
knowledge base using Kaggle's free GPUs. The result is a compact model that
can eventually run **on the phone itself** — the offline assistant for miners
with no signal.

> **Note:** the online chat in the app should still use RAG with a strong
> model — it gives better answers and cites sources. This fine-tuned model is
> the *offline / phase-two* track.

## Steps

1. **Build the dataset** (after the scraper + extract.py have run):

   ```
   python make_dataset.py
   ```

   This writes `train.jsonl` — chat-format Q&A examples generated from the
   knowledge base.

2. **Upload to Kaggle:**
   - Go to kaggle.com → *Datasets* → *New Dataset* → upload `train.jsonl`
     → name it exactly **umweo-mining-data**.
   - Go to *Code* → *New Notebook* → *File* → *Import Notebook* → upload
     `umweo_finetune.ipynb`.
   - In the notebook sidebar: *Add Input* → your **umweo-mining-data**
     dataset; *Accelerator* → **GPU T4 x2**.

3. **Run all cells.** Training takes ~10–30 minutes. Download the trained
   adapter from the notebook's *Output* tab.

## Improving quality

The auto-generated Q&A pairs in `train.jsonl` are a starting point. The
single highest-impact improvement is adding a few hundred *real* miner
questions with expert-reviewed answers. Append them to `train.jsonl` in the
same format:

```json
{"messages": [{"role": "system", "content": "..."}, {"role": "user", "content": "How do I support a pit wall?"}, {"role": "assistant", "content": "..."}]}
```

## Limits to know about

- Kaggle free tier: ~30 GPU hours/week, 12-hour max session.
- The current dataset is small; the model will sound knowledgeable about the
  scraped topics but it is NOT a safety authority. Keep the disclaimer and
  the RAG citations in the production app.

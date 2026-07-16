"""One-time download of the Qwen2.5-1.5B base model (~3 GB).

Our Kaggle-trained adapter (../umweo-flora) is a small modification that
sits on top of this base model. Run this once; afterwards the backend can
start with USE_OWN_MODEL=1 and no internet.
"""

from transformers import AutoModelForCausalLM, AutoTokenizer

BASE_MODEL = "Qwen/Qwen2.5-1.5B-Instruct"

print(f"Downloading tokenizer for {BASE_MODEL}...")
AutoTokenizer.from_pretrained(BASE_MODEL)
print("Downloading model weights (~3 GB - this can take a while)...")
AutoModelForCausalLM.from_pretrained(BASE_MODEL)
print("Done. The model is cached locally - start the server with USE_OWN_MODEL=1")

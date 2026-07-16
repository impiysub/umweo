"""Remove irrelevant documents from the collected data.

Drops manifest entries (and their downloaded files) that have nothing to do
with mining, safety, or the environment — e.g. the pension and tourism acts
the parliament crawl picked up. Run after scraper.py, before extract.py.

Usage:
    python prune.py           # show what would be removed
    python prune.py --apply   # actually remove it
"""

import argparse
import json
import re
from pathlib import Path

BASE_DIR = Path(__file__).parent
MANIFEST_PATH = BASE_DIR / "data" / "manifest.json"

KEEP = re.compile(
    r"\b(min(e|es|ing|er|ers|erals?)|safety|environment(al)?|hazard(ous)?"
    r"|licen[cs]\w*|guideline|gold|copper|artisanal|small.scale|asm|asgm"
    r"|occupational|emergency|first.aid|geolog\w*|explosive|blast\w*"
    r"|mercury|ventilat\w*|tailings|rehabilitat\w*|pollution|prospect\w*"
    r"|quarry\w*|shaft|ppe|zema|planetgold|delve)\b",
    re.IGNORECASE,
)

# Obvious junk wins even if a KEEP word also matches.
DROP = re.compile(
    r"\b(pension|superannuation|tourism|hospitality|speaker|chief justice"
    r"|prosecution|penal code|publishing house|revenue authority"
    r"|appropriation|legal education|public administration|disabilities"
    r"|constitution amendment|cabinet ministers|provincial ministers"
    r"|contact us|up ?coming events|use policy|list of volumes"
    r"|ministerial statements|zaneep|cop2\d)\b",
    re.IGNORECASE,
)

# Non-English language editions of documents we already have in English.
LANG_DROP = re.compile(
    r"(-fr|-es|-ru|_fr|_es)\.pdf"
    r"|rapport|avancement|informe|evaluaci|interprogram|transversale"
    r"|rapide|referencia|plegable|sso_en_la|sst-dans",
    re.IGNORECASE,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Prune irrelevant documents")
    parser.add_argument("--apply", action="store_true", help="delete instead of just listing")
    args = parser.parse_args()

    with open(MANIFEST_PATH, encoding="utf-8") as f:
        manifest = json.load(f)

    kept, dropped = {}, []
    for url, meta in manifest.items():
        haystack = " ".join([meta.get("title", ""), url, " ".join(meta.get("tags", []))])
        if DROP.search(haystack) or LANG_DROP.search(haystack) or not KEEP.search(haystack):
            dropped.append((url, meta))
        else:
            kept[url] = meta

    for url, meta in dropped:
        print(f"[drop] {meta.get('title') or url}")
    print(f"\n{len(kept)} kept, {len(dropped)} dropped")

    if not args.apply:
        print("\nDry run only — rerun with --apply to delete.")
        return

    for _, meta in dropped:
        path = BASE_DIR / meta["file"]
        if path.exists():
            path.unlink()
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(kept, f, indent=2, ensure_ascii=False)
    print("Applied: files deleted and manifest updated.")


if __name__ == "__main__":
    main()

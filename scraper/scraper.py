"""Mining knowledge-base scraper.

Reads seed URLs from sources.json, crawls each one within its own domain,
and downloads every PDF it finds into data/raw/. Also saves the text of
useful HTML pages. Respects robots.txt and waits between requests.

Usage:
    python scraper.py               # crawl everything in sources.json
    python scraper.py --source ZEMA # only sources whose name contains "ZEMA"
"""

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.robotparser
from pathlib import Path
from urllib.parse import urljoin, urlparse

import requests
from bs4 import BeautifulSoup

BASE_DIR = Path(__file__).parent
RAW_DIR = BASE_DIR / "data" / "raw"
MANIFEST_PATH = BASE_DIR / "data" / "manifest.json"

USER_AGENT = (
    "MiningSafetyBot/0.1 (prototype knowledge-base collector; "
    "contact: ngosalwandoniza@gmail.com)"
)

session = requests.Session()
session.headers["User-Agent"] = USER_AGENT

# Pattern that marks a page/PDF as relevant. Word-boundary matching so that
# e.g. "mine/mining/mineral" match but "ministers"/"administration" do not.
RELEVANT_PATTERN = re.compile(
    r"\b(min(e|es|ing|er|ers|erals?)|safety|environment(al)?|hazard(ous)?"
    r"|licen[cs]\w*|regulat\w*|guideline|gold|copper|artisanal|small.scale"
    r"|occupational|emergency|first.aid|geolog\w*|explor\w*|explosive"
    r"|blast\w*|mercury|ventilat\w*|tailings|rehabilitat\w*|pollution"
    r"|prospect\w*|quarry\w*|pit|shaft|ppe|training)\b",
    re.IGNORECASE,
)


def load_config(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_manifest() -> dict:
    if MANIFEST_PATH.exists():
        with open(MANIFEST_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_manifest(manifest: dict) -> None:
    MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)


def get_robots(domain: str, cache: dict) -> urllib.robotparser.RobotFileParser:
    if domain not in cache:
        rp = urllib.robotparser.RobotFileParser()
        # Fetch robots.txt with our own session/user-agent: the stdlib
        # fetcher gets blocked by some sites, which then looks like a
        # blanket disallow.
        try:
            resp = session.get(f"{domain}/robots.txt", timeout=30)
            if resp.status_code == 200:
                rp.parse(resp.text.splitlines())
            elif resp.status_code in (401, 403):
                rp.disallow_all = True
            else:
                rp.allow_all = True
        except requests.RequestException:
            # Unreachable robots.txt: crawl politely anyway.
            rp.allow_all = True
        cache[domain] = rp
    return cache[domain]


def safe_filename(url: str, suffix: str) -> str:
    """Build a stable, filesystem-safe filename from a URL."""
    name = urlparse(url).path.rsplit("/", 1)[-1] or "index"
    name = re.sub(r"[^A-Za-z0-9._-]", "_", name)[:80]
    digest = hashlib.sha1(url.encode()).hexdigest()[:8]
    if not name.lower().endswith(suffix):
        name += suffix
    return f"{digest}_{name}"


def looks_relevant(text: str) -> bool:
    return bool(RELEVANT_PATTERN.search(text))


def extract_page_text(soup: BeautifulSoup) -> str:
    for tag in soup(["script", "style", "nav", "footer", "header"]):
        tag.decompose()
    text = soup.get_text(separator="\n")
    lines = [line.strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


def crawl_source(source: dict, config: dict, manifest: dict, robots_cache: dict) -> None:
    seed = source["url"]
    domain = f"{urlparse(seed).scheme}://{urlparse(seed).netloc}"
    delay = config.get("delay_seconds", 2)
    max_depth = config.get("max_depth", 2)
    max_pages = config.get("max_pages_per_source", 40)

    robots = get_robots(domain, robots_cache)
    queue = [(seed, 0)]
    visited = set()
    pages_fetched = 0
    pdfs_downloaded = 0

    print(f"\n=== {source['name']} ===")

    while queue and pages_fetched < max_pages:
        url, depth = queue.pop(0)
        if url in visited:
            continue
        visited.add(url)

        if not robots.can_fetch(USER_AGENT, url):
            print(f"  [robots.txt disallows] {url}")
            continue

        time.sleep(delay)
        try:
            resp = session.get(url, timeout=30)
            resp.raise_for_status()
        except requests.RequestException as e:
            print(f"  [error] {url} -> {e}")
            continue

        pages_fetched += 1
        print(f"  [{pages_fetched}/{max_pages}] visiting {url}")
        content_type = resp.headers.get("Content-Type", "")

        if "pdf" in content_type or url.lower().endswith(".pdf"):
            fname = safe_filename(url, ".pdf")
            out = RAW_DIR / fname
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(resp.content)
            manifest[url] = {
                "file": str(out.relative_to(BASE_DIR)),
                "source": source["name"],
                "tags": source.get("tags", []),
                "type": "pdf",
                "fetched": time.strftime("%Y-%m-%d %H:%M:%S"),
            }
            pdfs_downloaded += 1
            print(f"  [pdf] {fname}")
            continue

        if "html" not in content_type:
            continue

        soup = BeautifulSoup(resp.text, "html.parser")

        # Save the page text itself if it looks like real content.
        page_text = extract_page_text(soup)
        if len(page_text) > 500 and looks_relevant(page_text[:2000]):
            fname = safe_filename(url, ".txt")
            out = RAW_DIR / fname
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(page_text, encoding="utf-8")
            manifest[url] = {
                "file": str(out.relative_to(BASE_DIR)),
                "source": source["name"],
                "tags": source.get("tags", []),
                "type": "html",
                "title": soup.title.get_text(strip=True) if soup.title else "",
                "fetched": time.strftime("%Y-%m-%d %H:%M:%S"),
            }
            print(f"  [page] {fname}")

        if depth >= max_depth:
            continue

        for a in soup.find_all("a", href=True):
            link = urljoin(url, a["href"]).split("#")[0]
            if not link.startswith(domain):
                # Stay on the source's own domain, EXCEPT direct PDF links,
                # which are worth grabbing wherever they live.
                if link.lower().endswith(".pdf") and link not in visited:
                    queue.append((link, max_depth))
                continue
            if link in visited:
                continue
            link_text = a.get_text(strip=True)
            if link.lower().endswith(".pdf") or looks_relevant(link_text + " " + link):
                queue.append((link, depth + 1))

    print(f"  done: {pages_fetched} pages fetched, {pdfs_downloaded} PDFs downloaded")


def main() -> None:
    parser = argparse.ArgumentParser(description="Mining knowledge-base scraper")
    parser.add_argument("--source", help="only crawl sources whose name contains this text")
    args = parser.parse_args()

    config = load_config(BASE_DIR / "sources.json")
    manifest = load_manifest()
    robots_cache: dict = {}

    sources = config["sources"]
    if args.source:
        sources = [s for s in sources if args.source.lower() in s["name"].lower()]
        if not sources:
            print(f"No source matching '{args.source}' in sources.json")
            sys.exit(1)

    for source in sources:
        try:
            crawl_source(source, config, manifest, robots_cache)
        except KeyboardInterrupt:
            print("\nInterrupted — saving manifest before exit.")
            break
        finally:
            save_manifest(manifest)

    print(f"\nManifest: {MANIFEST_PATH} ({len(manifest)} documents total)")


if __name__ == "__main__":
    main()

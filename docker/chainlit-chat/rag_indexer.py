"""
RAG Indexer — Sprint S11

CLI tool to index documentation into Qdrant vector store.
Run once after deploy, then re-run when docs change.

Usage:
  python rag_indexer.py \\
    --docs-dir /app/docs \\
    --qdrant-url http://qdrant.observability.local:6333 \\
    --litellm-url http://litellm.observability.local:4000 \\
    [--recreate]   # drop and recreate collection
    [--dry-run]    # show chunks without indexing
"""

import argparse
import asyncio
import hashlib
import logging
import re
from pathlib import Path
from dataclasses import dataclass

import httpx
from openai import AsyncOpenAI

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("rag-indexer")

EMBED_DIM = 1024          # Titan Embed v2
MAX_CHUNK_CHARS = 2048    # ~512 tokens
COLLECTION_NAME = "obs_hub_knowledge"
EMBED_MODEL = "text-embedding-titan-v2"


@dataclass
class Chunk:
    text: str
    source_file: str
    section_title: str
    doc_type: str
    chunk_hash: str


# ---------------------------------------------------------------------------
# Doc type classifier (by filename)
# ---------------------------------------------------------------------------
_DOC_TYPE_MAP = {
    "09_troubleshooting": "troubleshooting",
    "01_analise_tecnica": "architecture",
    "02_analise_finops": "finops",
    "04_roadmap": "architecture",
    "05_apresentacao": "architecture",
    "TFC-GRAFANA": "runbook",
    "ROADMAP-MELHORIAS": "architecture",
    "grafana-baseline": "runbook",
    "sprint_closure": "architecture",
    "sprint_status": "architecture",
    "business_case": "finops",
    "ai_platform": "architecture",
}


def _classify_doc(filename: str) -> str:
    for key, dtype in _DOC_TYPE_MAP.items():
        if key.lower() in filename.lower():
            return dtype
    return "general"


# ---------------------------------------------------------------------------
# Chunker: split by ## and ### headers, respect max size
# ---------------------------------------------------------------------------
def chunk_markdown(text: str, source_file: str) -> list[Chunk]:
    """Split markdown by headers. Each ## section becomes one or more chunks."""
    sections = re.split(r"\n(?=#{2,3} )", text)
    doc_type = _classify_doc(source_file)
    chunks = []

    for section in sections:
        if not section.strip():
            continue

        first_line = section.split("\n", 1)[0].strip()
        title = re.sub(r"^#{2,3}\s*", "", first_line)

        if len(section) <= MAX_CHUNK_CHARS:
            h = hashlib.sha256(section.encode()).hexdigest()[:16]
            chunks.append(Chunk(
                text=section.strip(),
                source_file=source_file,
                section_title=title,
                doc_type=doc_type,
                chunk_hash=h,
            ))
        else:
            paragraphs = re.split(r"\n{2,}", section)
            current = ""
            for para in paragraphs:
                if len(current) + len(para) > MAX_CHUNK_CHARS and current:
                    h = hashlib.sha256(current.encode()).hexdigest()[:16]
                    chunks.append(Chunk(
                        text=current.strip(),
                        source_file=source_file,
                        section_title=title,
                        doc_type=doc_type,
                        chunk_hash=h,
                    ))
                    current = para
                else:
                    current = current + "\n\n" + para if current else para
            if current.strip():
                h = hashlib.sha256(current.encode()).hexdigest()[:16]
                chunks.append(Chunk(
                    text=current.strip(),
                    source_file=source_file,
                    section_title=title,
                    doc_type=doc_type,
                    chunk_hash=h,
                ))

    return chunks


def _extract_python_knowledge(content: str) -> str:
    """Extract knowledge content from Python prompt files."""
    matches = re.findall(r'"""(.*?)"""', content, re.DOTALL)
    if matches:
        return "\n\n".join(matches)
    matches = re.findall(r"'''(.*?)'''", content, re.DOTALL)
    if matches:
        return "\n\n".join(matches)
    return content


# ---------------------------------------------------------------------------
# Qdrant REST API helpers
# ---------------------------------------------------------------------------
async def _qdrant_get(client: httpx.AsyncClient, path: str) -> dict:
    resp = await client.get(path)
    resp.raise_for_status()
    return resp.json()


async def _qdrant_post(client: httpx.AsyncClient, path: str, json: dict) -> dict:
    resp = await client.post(path, json=json)
    resp.raise_for_status()
    return resp.json()


async def _qdrant_put(client: httpx.AsyncClient, path: str, json: dict) -> dict:
    resp = await client.put(path, json=json)
    resp.raise_for_status()
    return resp.json()


async def _qdrant_delete(client: httpx.AsyncClient, path: str) -> dict:
    resp = await client.delete(path)
    resp.raise_for_status()
    return resp.json()


# ---------------------------------------------------------------------------
# Main indexing loop
# ---------------------------------------------------------------------------
async def index_docs(args: argparse.Namespace) -> None:
    qdrant = httpx.AsyncClient(base_url=args.qdrant_url, timeout=60)
    embed_client = AsyncOpenAI(
        base_url=f"{args.litellm_url}/v1",
        api_key="not-needed",
        timeout=60,
    )

    # Collect source files
    source_files: list[tuple[str, str]] = []

    docs_dir = Path(args.docs_dir)
    if docs_dir.exists():
        for md_file in sorted(docs_dir.glob("*.md")):
            source_files.append((str(md_file), md_file.name))

    prompts_dir = Path(args.prompts_dir) if args.prompts_dir else docs_dir.parent / "prompts"
    if prompts_dir.exists():
        for py_file in sorted(prompts_dir.glob("*.py")):
            if py_file.name == "__init__.py":
                continue
            source_files.append((str(py_file), f"prompts/{py_file.name}"))

    logger.info(f"Found {len(source_files)} source files to index")

    # Check if collection exists
    try:
        collections_resp = await _qdrant_get(qdrant, "/collections")
        existing = [
            c["name"]
            for c in collections_resp.get("result", {}).get("collections", [])
        ]
    except Exception as e:
        logger.error(f"Cannot connect to Qdrant at {args.qdrant_url}: {e}")
        return

    if COLLECTION_NAME in existing and args.recreate:
        logger.info(f"Recreating collection '{COLLECTION_NAME}'")
        await _qdrant_delete(qdrant, f"/collections/{COLLECTION_NAME}")
        existing.remove(COLLECTION_NAME)

    if COLLECTION_NAME not in existing:
        logger.info(f"Creating collection '{COLLECTION_NAME}' (dim={EMBED_DIM})")
        await _qdrant_put(qdrant, f"/collections/{COLLECTION_NAME}", {
            "vectors": {
                "size": EMBED_DIM,
                "distance": "Cosine",
            },
        })

    # Load existing hashes for incremental indexing
    existing_hashes: set[str] = set()
    if not args.recreate:
        try:
            scroll_resp = await _qdrant_post(
                qdrant,
                f"/collections/{COLLECTION_NAME}/points/scroll",
                {"limit": 10000, "with_payload": ["chunk_hash"]},
            )
            for point in scroll_resp.get("result", {}).get("points", []):
                payload = point.get("payload", {})
                if "chunk_hash" in payload:
                    existing_hashes.add(payload["chunk_hash"])
            logger.info(f"Loaded {len(existing_hashes)} existing chunk hashes")
        except Exception:
            logger.info("No existing points found — fresh index")

    total_indexed = 0
    total_skipped = 0

    for file_path, display_name in source_files:
        try:
            content = Path(file_path).read_text(encoding="utf-8")

            if file_path.endswith(".py"):
                content = _extract_python_knowledge(content)

            chunks = chunk_markdown(content, display_name)
            logger.info(f"  {display_name}: {len(chunks)} chunks")

            for chunk in chunks:
                if chunk.chunk_hash in existing_hashes:
                    total_skipped += 1
                    continue

                if args.dry_run:
                    logger.info(
                        f"    [DRY] {chunk.section_title[:60]} "
                        f"({len(chunk.text)} chars, {chunk.doc_type})"
                    )
                    total_indexed += 1
                    continue

                # Embed via LiteLLM
                resp = await embed_client.embeddings.create(
                    model=EMBED_MODEL,
                    input=chunk.text,
                )
                vector = resp.data[0].embedding

                # Generate deterministic point ID from hash
                point_id = int(
                    hashlib.sha256(chunk.chunk_hash.encode()).hexdigest()[:15], 16
                )

                # Upsert to Qdrant
                await _qdrant_put(
                    qdrant,
                    f"/collections/{COLLECTION_NAME}/points",
                    {
                        "points": [{
                            "id": point_id,
                            "vector": vector,
                            "payload": {
                                "text": chunk.text,
                                "source_file": chunk.source_file,
                                "section_title": chunk.section_title,
                                "doc_type": chunk.doc_type,
                                "chunk_hash": chunk.chunk_hash,
                            },
                        }],
                    },
                )
                total_indexed += 1
                existing_hashes.add(chunk.chunk_hash)

        except Exception as e:
            logger.error(f"Failed to index {display_name}: {e}")
            continue

    await qdrant.aclose()
    logger.info(
        f"Indexing complete: {total_indexed} indexed, "
        f"{total_skipped} skipped (unchanged), "
        f"collection='{COLLECTION_NAME}'"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="RAG Indexer for Observability Hub"
    )
    parser.add_argument(
        "--docs-dir",
        default="/app/docs",
        help="Path to docs/ directory",
    )
    parser.add_argument(
        "--prompts-dir",
        default=None,
        help="Path to prompts/ directory (default: docs/../prompts)",
    )
    parser.add_argument(
        "--qdrant-url",
        default="http://qdrant.observability.local:6333",
    )
    parser.add_argument(
        "--litellm-url",
        default="http://litellm.observability.local:4000",
    )
    parser.add_argument(
        "--recreate",
        action="store_true",
        help="Drop and recreate collection",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show chunks without indexing",
    )
    args = parser.parse_args()
    asyncio.run(index_docs(args))


if __name__ == "__main__":
    main()

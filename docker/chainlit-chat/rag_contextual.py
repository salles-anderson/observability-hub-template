"""
Contextual Retrieval — AG-4 / S16

Enriches RAG chunks with contextual prefixes using Claude Haiku.
Based on Anthropic's Contextual Retrieval technique:
https://www.anthropic.com/news/contextual-retrieval

For each chunk, Claude generates a 1-2 sentence context that situates
the chunk within the overall document. This context is prepended to the
chunk text before re-embedding, improving retrieval quality by 49-67%.

Usage:
  python rag_contextual.py \
    --qdrant-url http://qdrant.observability.local:6333 \
    --litellm-url http://litellm.observability.local:4000 \
    --docs-dir /app/docs \
    [--dry-run]    # show contexts without updating
    [--batch-size 10]
"""

import argparse
import asyncio
import hashlib
import logging
import re
from pathlib import Path

import httpx
from openai import AsyncOpenAI

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("rag-contextual")

COLLECTION_NAME = "obs_hub_knowledge"
EMBED_MODEL = "text-embedding-titan-v2"
EMBED_DIM = 1024
CONTEXT_MODEL = "claude-sonnet-4.6"  # Uses Claude via LiteLLM (Haiku would be cheaper but Sonnet is already configured)

CONTEXT_PROMPT = """<document>
{document}
</document>

Here is the chunk we want to situate within the overall document:
<chunk>
{chunk}
</chunk>

Please give a short succinct context (1-2 sentences in Portuguese BR) to situate this chunk within the overall document for the purposes of improving search retrieval.
The context should help someone searching for this information find it.
Focus on: what system/service this is about, what aspect (config, troubleshooting, architecture, cost, etc.), and any key identifiers (service names, account IDs, etc.).
Answer ONLY with the succinct context and nothing else."""


async def _get_all_points(qdrant: httpx.AsyncClient) -> list[dict]:
    """Scroll through all points in the collection."""
    points = []
    offset = None

    while True:
        body = {"limit": 100, "with_payload": True, "with_vector": False}
        if offset:
            body["offset"] = offset

        resp = await qdrant.post(
            f"/collections/{COLLECTION_NAME}/points/scroll",
            json=body,
        )
        resp.raise_for_status()
        data = resp.json()
        result = data.get("result", {})

        batch = result.get("points", [])
        points.extend(batch)

        next_offset = result.get("next_page_offset")
        if not next_offset or not batch:
            break
        offset = next_offset

    return points


async def _load_document(docs_dir: Path, source_file: str) -> str:
    """Load the full document that a chunk came from."""
    # Try direct path
    doc_path = docs_dir / source_file
    if doc_path.exists():
        return doc_path.read_text(encoding="utf-8")

    # Try prompts directory
    if source_file.startswith("prompts/"):
        prompts_path = docs_dir.parent / source_file
        if prompts_path.exists():
            content = prompts_path.read_text(encoding="utf-8")
            # Extract docstrings from Python files
            matches = re.findall(r'"""(.*?)"""', content, re.DOTALL)
            if matches:
                return "\n\n".join(matches)
            return content

    return ""


async def _generate_context(
    llm: AsyncOpenAI,
    document: str,
    chunk_text: str,
) -> str:
    """Use Claude to generate a contextual prefix for a chunk."""
    # Truncate document if too long (keep first 4000 chars for context)
    if len(document) > 4000:
        document = document[:4000] + "\n... [documento truncado]"

    try:
        resp = await asyncio.wait_for(
            llm.chat.completions.create(
                model=CONTEXT_MODEL,
                messages=[
                    {
                        "role": "user",
                        "content": CONTEXT_PROMPT.format(
                            document=document,
                            chunk=chunk_text[:1500],
                        ),
                    }
                ],
                max_tokens=150,
                temperature=0,
            ),
            timeout=15.0,
        )
        context = resp.choices[0].message.content.strip()
        return context
    except asyncio.TimeoutError:
        logger.warning("Context generation timeout — skipping")
        return ""
    except Exception as e:
        logger.warning(f"Context generation error: {e}")
        return ""


async def run_contextual(args: argparse.Namespace) -> None:
    qdrant = httpx.AsyncClient(base_url=args.qdrant_url, timeout=60)
    llm = AsyncOpenAI(
        base_url=f"{args.litellm_url}/v1",
        api_key="not-needed",
        timeout=30,
    )
    embed = AsyncOpenAI(
        base_url=f"{args.litellm_url}/v1",
        api_key="not-needed",
        timeout=15,
    )

    docs_dir = Path(args.docs_dir)

    # Load all points
    logger.info("Loading existing chunks from Qdrant...")
    points = await _get_all_points(qdrant)
    logger.info(f"Found {len(points)} chunks to enrich")

    # Cache documents to avoid re-reading
    doc_cache: dict[str, str] = {}

    updated = 0
    skipped = 0
    errors = 0

    for i, point in enumerate(points):
        payload = point.get("payload", {})
        source_file = payload.get("source_file", "")
        chunk_text = payload.get("text", "")
        section_title = payload.get("section_title", "")
        point_id = point.get("id")

        # Skip if already has context
        if payload.get("contextual_prefix"):
            skipped += 1
            continue

        # Load source document
        if source_file not in doc_cache:
            doc_cache[source_file] = await _load_document(docs_dir, source_file)

        document = doc_cache[source_file]
        if not document:
            logger.warning(f"  [{i+1}/{len(points)}] No document for {source_file} — skipping")
            skipped += 1
            continue

        # Generate context
        context = await _generate_context(llm, document, chunk_text)
        if not context:
            errors += 1
            continue

        # Build enriched text
        enriched_text = f"{context}\n\n{chunk_text}"

        logger.info(
            f"  [{i+1}/{len(points)}] {section_title[:50]}\n"
            f"    Context: {context[:100]}..."
        )

        if args.dry_run:
            updated += 1
            continue

        # Re-embed with contextual prefix
        try:
            embed_resp = await embed.embeddings.create(
                model=EMBED_MODEL,
                input=enriched_text,
            )
            new_vector = embed_resp.data[0].embedding

            # Update point with new vector and enriched payload
            new_hash = hashlib.sha256(enriched_text.encode()).hexdigest()[:16]
            await qdrant.put(
                f"/collections/{COLLECTION_NAME}/points",
                json={
                    "points": [{
                        "id": point_id,
                        "vector": new_vector,
                        "payload": {
                            "text": enriched_text,
                            "source_file": source_file,
                            "section_title": section_title,
                            "doc_type": payload.get("doc_type", "general"),
                            "chunk_hash": new_hash,
                            "contextual_prefix": context,
                            "original_text": chunk_text,
                        },
                    }],
                },
            )
            updated += 1
        except Exception as e:
            logger.error(f"  Failed to update point {point_id}: {e}")
            errors += 1

        # Rate limit — avoid hammering LiteLLM
        if (i + 1) % args.batch_size == 0:
            logger.info(f"  Progress: {i+1}/{len(points)} ({updated} updated, {skipped} skipped, {errors} errors)")
            await asyncio.sleep(1)

    await qdrant.aclose()
    logger.info(
        f"\nContextual enrichment complete:\n"
        f"  Updated: {updated}\n"
        f"  Skipped: {skipped} (already enriched or no doc)\n"
        f"  Errors:  {errors}\n"
        f"  Total:   {len(points)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Contextual Retrieval — enrich RAG chunks with context prefixes"
    )
    parser.add_argument("--docs-dir", default="/app/docs")
    parser.add_argument("--qdrant-url", default="http://qdrant.observability.local:6333")
    parser.add_argument("--litellm-url", default="http://litellm.observability.local:4000")
    parser.add_argument("--batch-size", type=int, default=10)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    asyncio.run(run_contextual(args))


if __name__ == "__main__":
    main()

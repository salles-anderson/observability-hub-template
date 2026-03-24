"""
Semantic Cache — AG-4 / S16

Caches LLM responses in Qdrant by query similarity.
Queries with similarity > threshold return cached response instantly
(~50ms vs ~30-60s for full AG-2 pipeline).

Collection: "semantic_cache" (separate from RAG knowledge base)
Embedding: Titan Embed v2 (1024 dims, same as RAG)
TTL: 30 minutes (ops data goes stale quickly)
Threshold: 0.92 (high — avoids false matches)
"""

import asyncio
import json
import logging
import os
import time
import uuid

import httpx
from openai import AsyncOpenAI

logger = logging.getLogger("semantic-cache")

QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant.observability.local:6333")
LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm.observability.local:4000")
EMBED_MODEL = os.environ.get("RAG_EMBED_MODEL", "text-embedding-titan-v2")

CACHE_ENABLED = os.environ.get("SEMANTIC_CACHE_ENABLED", "true").lower() == "true"
CACHE_COLLECTION = "semantic_cache"
CACHE_THRESHOLD = float(os.environ.get("SEMANTIC_CACHE_THRESHOLD", "0.92"))
CACHE_TTL_SECONDS = int(os.environ.get("SEMANTIC_CACHE_TTL", "1800"))  # 30 min
EMBED_DIM = 1024

_embed_client: AsyncOpenAI | None = None
_http_client: httpx.AsyncClient | None = None


def _get_embed_client() -> AsyncOpenAI:
    global _embed_client
    if _embed_client is None:
        _embed_client = AsyncOpenAI(
            base_url=f"{LITELLM_URL}/v1",
            api_key="not-needed",
            timeout=httpx.Timeout(5.0, connect=2.0),
        )
    return _embed_client


def _get_http_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None:
        _http_client = httpx.AsyncClient(
            base_url=QDRANT_URL,
            timeout=httpx.Timeout(5.0, connect=2.0),
        )
    return _http_client


async def _embed(text: str) -> list[float]:
    """Embed text via LiteLLM → Bedrock Titan Embed v2."""
    client = _get_embed_client()
    resp = await client.embeddings.create(model=EMBED_MODEL, input=text)
    return resp.data[0].embedding


async def ensure_collection():
    """Create semantic_cache collection if it doesn't exist."""
    client = _get_http_client()
    try:
        resp = await client.get(f"/collections/{CACHE_COLLECTION}")
        if resp.status_code == 200:
            return
    except Exception:
        pass

    try:
        await client.put(
            f"/collections/{CACHE_COLLECTION}",
            json={
                "vectors": {
                    "size": EMBED_DIM,
                    "distance": "Cosine",
                },
            },
        )
        logger.info(f"Created Qdrant collection '{CACHE_COLLECTION}'")
    except Exception as e:
        logger.warning(f"Failed to create cache collection: {e}")


async def lookup(question: str) -> str | None:
    """Search for a cached response similar to the question.

    Returns cached response if similarity >= threshold and not expired.
    Returns None on cache miss.
    """
    if not CACHE_ENABLED:
        return None

    t0 = time.monotonic()
    try:
        vector = await asyncio.wait_for(_embed(question), timeout=3.0)

        client = _get_http_client()
        resp = await client.post(
            f"/collections/{CACHE_COLLECTION}/points/query",
            json={
                "query": vector,
                "limit": 1,
                "with_payload": True,
                "score_threshold": CACHE_THRESHOLD,
            },
        )
        resp.raise_for_status()
        data = resp.json()

        points = data.get("result", {}).get("points", [])
        if not points:
            elapsed = int((time.monotonic() - t0) * 1000)
            logger.info(f"Cache MISS for '{question[:60]}' ({elapsed}ms)")
            return None

        point = points[0]
        payload = point.get("payload", {})
        cached_at = payload.get("cached_at", 0)
        now = time.time()

        # Check TTL
        if now - cached_at > CACHE_TTL_SECONDS:
            elapsed = int((time.monotonic() - t0) * 1000)
            logger.info(
                f"Cache EXPIRED for '{question[:60]}' "
                f"(age={int(now - cached_at)}s, ttl={CACHE_TTL_SECONDS}s, {elapsed}ms)"
            )
            # Delete expired point
            point_id = point.get("id")
            if point_id:
                await client.post(
                    f"/collections/{CACHE_COLLECTION}/points/delete",
                    json={"points": [point_id]},
                )
            return None

        score = point.get("score", 0)
        response = payload.get("response", "")
        elapsed = int((time.monotonic() - t0) * 1000)

        logger.info(
            f"Cache HIT for '{question[:60]}' "
            f"(score={score:.3f}, age={int(now - cached_at)}s, {elapsed}ms)"
        )

        return response

    except asyncio.TimeoutError:
        logger.warning("Cache lookup timeout — skipping")
        return None
    except Exception as e:
        logger.warning(f"Cache lookup error: {e} — skipping")
        return None


async def store(question: str, response: str, agents_used: str = ""):
    """Store a question-response pair in the semantic cache.

    Fire-and-forget — errors are logged but don't affect the response.
    """
    if not CACHE_ENABLED:
        return

    try:
        vector = await asyncio.wait_for(_embed(question), timeout=3.0)

        client = _get_http_client()
        point_id = str(uuid.uuid4())

        await client.put(
            f"/collections/{CACHE_COLLECTION}/points",
            json={
                "points": [
                    {
                        "id": point_id,
                        "vector": vector,
                        "payload": {
                            "question": question,
                            "response": response,
                            "agents_used": agents_used,
                            "cached_at": time.time(),
                        },
                    }
                ]
            },
        )

        logger.info(
            f"Cache STORE for '{question[:60]}' "
            f"(agents={agents_used}, id={point_id[:8]})"
        )

    except Exception as e:
        logger.warning(f"Cache store error: {e} — skipping")


async def cleanup_expired():
    """Remove expired entries from cache. Run periodically."""
    if not CACHE_ENABLED:
        return 0

    try:
        client = _get_http_client()
        cutoff = time.time() - CACHE_TTL_SECONDS

        resp = await client.post(
            f"/collections/{CACHE_COLLECTION}/points/delete",
            json={
                "filter": {
                    "must": [
                        {
                            "key": "cached_at",
                            "range": {"lt": cutoff},
                        }
                    ]
                }
            },
        )

        if resp.status_code == 200:
            result = resp.json().get("result", {})
            logger.info(f"Cache cleanup: removed expired entries (cutoff={cutoff:.0f})")
            return 1
        return 0

    except Exception as e:
        logger.warning(f"Cache cleanup error: {e}")
        return 0

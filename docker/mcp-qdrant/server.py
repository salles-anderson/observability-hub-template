"""
MCP Server — Qdrant (RAG + Semantic Cache) (AG-5)

Exposes RAG knowledge base search and semantic cache as MCP tools.
Collection: obs_hub_knowledge (RAG), semantic_cache (cache)
Embedding: Titan Embed v2 via LiteLLM
Transport: SSE on port 8004
"""

import asyncio
import os
import logging
import time
import uuid

import httpx
from openai import AsyncOpenAI
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger("mcp-qdrant")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant.observability.local:6333")
LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm.observability.local:4000")
EMBED_MODEL = os.environ.get("RAG_EMBED_MODEL", "text-embedding-titan-v2")
RAG_COLLECTION = "obs_hub_knowledge"
CACHE_COLLECTION = "semantic_cache"
CACHE_THRESHOLD = float(os.environ.get("SEMANTIC_CACHE_THRESHOLD", "0.92"))
CACHE_TTL = int(os.environ.get("SEMANTIC_CACHE_TTL", "1800"))
EMBED_DIM = 1024

# ---------------------------------------------------------------------------
# Clients
# ---------------------------------------------------------------------------
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
    client = _get_embed_client()
    resp = await client.embeddings.create(model=EMBED_MODEL, input=text)
    return resp.data[0].embedding


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------
mcp = FastMCP("Qdrant Knowledge Base")


@mcp.tool()
async def rag_search_knowledge(query: str, top_k: int = 5) -> str:
    """Search the Observability Hub knowledge base for relevant documentation.

    Use this when the user asks about architecture, runbooks, configuration,
    troubleshooting guides, or any documentation about the Teck infrastructure.

    Args:
        query: Search query in natural language
        top_k: Number of results to return (default 5)

    Returns relevant documentation chunks with source and relevance score.
    """
    try:
        vector = await asyncio.wait_for(_embed(query), timeout=3.0)
        client = _get_http_client()

        resp = await client.post(
            f"/collections/{RAG_COLLECTION}/points/query",
            json={"query": vector, "limit": top_k, "with_payload": True},
        )
        resp.raise_for_status()
        points = resp.json().get("result", {}).get("points", [])

        if not points:
            return "No relevant documentation found in knowledge base."

        lines = ["## Knowledge Base Results\n"]
        for i, pt in enumerate(points, 1):
            payload = pt.get("payload", {})
            score = pt.get("score", 0)
            text = payload.get("text", "")
            source = payload.get("source_file", "unknown")
            title = payload.get("section_title", "")
            doc_type = payload.get("doc_type", "general")

            lines.append(
                f"**[{i}] {title}** (source: `{source}`, type: {doc_type}, score: {score:.2f})\n"
                f"{text}\n"
            )

        return "\n".join(lines)

    except asyncio.TimeoutError:
        return "RAG search timeout — knowledge base unavailable"
    except Exception as e:
        return f"RAG search error: {e}"


@mcp.tool()
async def semantic_cache_lookup(question: str) -> str:
    """Look up a cached response for a similar question.

    Uses vector similarity to find previously answered questions.
    Returns cached response if similarity > 0.92 and not expired (30min TTL).

    Args:
        question: The user's question to look up
    """
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
        points = resp.json().get("result", {}).get("points", [])

        if not points:
            return "CACHE_MISS"

        payload = points[0].get("payload", {})
        cached_at = payload.get("cached_at", 0)

        if time.time() - cached_at > CACHE_TTL:
            return "CACHE_EXPIRED"

        score = points[0].get("score", 0)
        response = payload.get("response", "")
        logger.info(f"Cache HIT: score={score:.3f}, age={int(time.time() - cached_at)}s")
        return response

    except Exception as e:
        return f"CACHE_ERROR: {e}"


@mcp.tool()
async def semantic_cache_store(question: str, response: str, agents_used: str = "") -> str:
    """Store a question-response pair in the semantic cache.

    Args:
        question: The original question
        response: The full response to cache
        agents_used: Comma-separated list of agents that generated the response
    """
    try:
        vector = await asyncio.wait_for(_embed(question), timeout=3.0)
        client = _get_http_client()

        # Ensure collection exists
        try:
            await client.get(f"/collections/{CACHE_COLLECTION}")
        except Exception:
            await client.put(
                f"/collections/{CACHE_COLLECTION}",
                json={"vectors": {"size": EMBED_DIM, "distance": "Cosine"}},
            )

        point_id = str(uuid.uuid4())
        await client.put(
            f"/collections/{CACHE_COLLECTION}/points",
            json={
                "points": [{
                    "id": point_id,
                    "vector": vector,
                    "payload": {
                        "question": question,
                        "response": response,
                        "agents_used": agents_used,
                        "cached_at": time.time(),
                    },
                }]
            },
        )

        return f"CACHE_STORED: {point_id[:8]}"

    except Exception as e:
        return f"CACHE_STORE_ERROR: {e}"


if __name__ == "__main__":
    import uvicorn
    app = mcp.sse_app()
    uvicorn.run(app, host="0.0.0.0", port=8004)  # noqa: S104

"""
RAG Retriever — Sprint S11

Hybrid retrieval against Qdrant vector store.
Embedding via LiteLLM proxy → Bedrock Titan Embed v2.
Model-agnostic: context chunks are injected into any LLM's prompt.

Collection: "obs_hub_knowledge"
Embedding: text-embedding-titan-v2 (1024 dimensions via LiteLLM)
"""

import asyncio
import logging
import os
import time
from dataclasses import dataclass

import httpx
from openai import AsyncOpenAI

logger = logging.getLogger("rag-retriever")

QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant.observability.local:6333")
LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm.observability.local:4000")
EMBED_MODEL = os.environ.get("RAG_EMBED_MODEL", "text-embedding-titan-v2")
COLLECTION_NAME = os.environ.get("RAG_COLLECTION", "obs_hub_knowledge")
RAG_ENABLED = os.environ.get("RAG_ENABLED", "false").lower() == "true"
RAG_TIMEOUT = int(os.environ.get("RAG_TIMEOUT_MS", "3000")) / 1000

EMBED_DIM = 1024  # Titan Embed v2


@dataclass
class ChunkResult:
    text: str
    source_file: str
    section_title: str
    doc_type: str
    score: float


_embed_client: AsyncOpenAI | None = None
_http_client: httpx.AsyncClient | None = None


def _get_embed_client() -> AsyncOpenAI:
    global _embed_client
    if _embed_client is None:
        _embed_client = AsyncOpenAI(
            base_url=f"{LITELLM_URL}/v1",
            api_key="not-needed",
            timeout=httpx.Timeout(RAG_TIMEOUT, connect=2.0),
        )
    return _embed_client


def _get_http_client() -> httpx.AsyncClient:
    global _http_client
    if _http_client is None:
        _http_client = httpx.AsyncClient(
            base_url=QDRANT_URL,
            timeout=httpx.Timeout(RAG_TIMEOUT, connect=2.0),
        )
    return _http_client


async def _embed(text: str) -> list[float]:
    """Embed text via LiteLLM proxy -> Bedrock Titan Embed v2."""
    client = _get_embed_client()
    resp = await client.embeddings.create(model=EMBED_MODEL, input=text)
    return resp.data[0].embedding


async def retrieve(question: str, top_k: int = 5) -> list[ChunkResult]:
    """
    Dense retrieval from Qdrant via REST API.
    Returns up to top_k chunks sorted by score.
    Falls back gracefully if Qdrant is unreachable.
    """
    if not RAG_ENABLED:
        return []

    t0 = time.monotonic()
    try:
        vector = await asyncio.wait_for(_embed(question), timeout=RAG_TIMEOUT)

        client = _get_http_client()
        resp = await client.post(
            f"/collections/{COLLECTION_NAME}/points/query",
            json={
                "query": vector,
                "limit": top_k,
                "with_payload": True,
            },
        )
        resp.raise_for_status()
        data = resp.json()

        chunks = []
        for point in data.get("result", {}).get("points", []):
            payload = point.get("payload", {})
            chunks.append(ChunkResult(
                text=payload.get("text", ""),
                source_file=payload.get("source_file", "unknown"),
                section_title=payload.get("section_title", ""),
                doc_type=payload.get("doc_type", "general"),
                score=point.get("score", 0.0),
            ))

        elapsed_ms = int((time.monotonic() - t0) * 1000)
        logger.info(
            f"RAG retrieved {len(chunks)} chunks for "
            f"'{question[:60]}' in {elapsed_ms}ms"
        )
        return chunks

    except asyncio.TimeoutError:
        logger.warning(f"RAG timeout ({RAG_TIMEOUT}s) — skipping context injection")
        return []
    except Exception as e:
        logger.warning(f"RAG unavailable: {e} — continuing without context")
        return []


def build_rag_context(chunks: list[ChunkResult]) -> str:
    """Format retrieved chunks into a prompt-injectable context block."""
    if not chunks:
        return ""

    lines = [
        "\n\n## Contexto da Base de Conhecimento (RAG)",
        "Use APENAS os trechos abaixo para responder. "
        "Se a informacao nao estiver aqui, diga que nao encontrou na documentacao.\n",
    ]
    for i, chunk in enumerate(chunks, 1):
        lines.append(
            f"**[{i}] {chunk.section_title}** "
            f"(fonte: `{chunk.source_file}`, tipo: {chunk.doc_type}, "
            f"relevancia: {chunk.score:.2f})\n"
            f"{chunk.text}\n"
        )
    lines.append("---")
    return "\n".join(lines)

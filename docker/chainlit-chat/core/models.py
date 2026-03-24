"""
Data models — AgentResult, AgentRequest.

Standardized contracts between router, agents, and correlator.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field


@dataclass
class AgentRequest:
    """Input for a specialized agent."""

    question: str
    history: list[dict] | None = None
    account_id: str | None = None
    role: str = "user"
    metadata: dict = field(default_factory=dict)


@dataclass
class AgentResult:
    """Standardized output from a specialized agent."""

    agent_name: str
    status: str  # success | partial | error | timeout
    data: str  # Markdown findings
    confidence: float = 1.0  # 0.0-1.0
    sources: list[str] = field(default_factory=list)
    duration_ms: int = 0
    tool_calls: int = 0
    metadata: dict = field(default_factory=dict)

    @staticmethod
    def error(agent_name: str, message: str, duration_ms: int = 0) -> AgentResult:
        """Factory for error results."""
        return AgentResult(
            agent_name=agent_name,
            status="error",
            data=message,
            confidence=0.0,
            duration_ms=duration_ms,
        )

    @staticmethod
    def timeout(agent_name: str, duration_ms: int) -> AgentResult:
        """Factory for timeout results."""
        return AgentResult(
            agent_name=agent_name,
            status="timeout",
            data="Tempo limite excedido para esta consulta.",
            confidence=0.0,
            duration_ms=duration_ms,
        )


class Timer:
    """Simple context manager for measuring elapsed time in ms."""

    def __init__(self):
        self._start = 0.0
        self.elapsed_ms = 0

    def __enter__(self):
        self._start = time.monotonic()
        return self

    def __exit__(self, *_):
        self.elapsed_ms = int((time.monotonic() - self._start) * 1000)

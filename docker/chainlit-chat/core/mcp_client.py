"""
MCP Client Manager — AG-5

Uses the official MCP Python SDK (ClientSession + sse_client) to connect
to FastMCP servers via SSE transport.

Each MCP server runs as a sidecar container on localhost:800X.
The client discovers tools from all servers and routes tool calls.
"""

from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass, field
from contextlib import AsyncExitStack

from mcp.client.sse import sse_client
from mcp import ClientSession

logger = logging.getLogger("mcp-client")

# ---------------------------------------------------------------------------
# MCP Server Registry
# ---------------------------------------------------------------------------
MCP_SERVERS = {
    "aws": {
        "url": os.environ.get("MCP_AWS_URL", "http://localhost:8001"),
    },
    "github": {
        "url": os.environ.get("MCP_GITHUB_URL", "http://localhost:8002"),
    },
    "tfc": {
        "url": os.environ.get("MCP_TFC_URL", "http://localhost:8003"),
    },
    "qdrant": {
        "url": os.environ.get("MCP_QDRANT_URL", "http://localhost:8004"),
    },
    "grafana": {
        "url": os.environ.get("MCP_GRAFANA_URL", "http://localhost:8000"),
    },
    "confluence": {
        "url": os.environ.get("MCP_CONFLUENCE_URL", "http://localhost:8005"),
    },
    "eraser": {
        "url": os.environ.get("MCP_ERASER_URL", "http://localhost:8006"),
    },
}


@dataclass
class MCPTool:
    """A tool discovered from an MCP server."""
    name: str
    description: str
    input_schema: dict
    server_name: str


@dataclass
class MCPClientManager:
    """Manages persistent connections to all MCP servers."""

    tools: list[MCPTool] = field(default_factory=list)
    _tool_map: dict[str, MCPTool] = field(default_factory=dict)
    _tool_to_server: dict[str, str] = field(default_factory=dict)
    _sessions: dict[str, ClientSession] = field(default_factory=dict)
    _exit_stack: AsyncExitStack | None = None
    _initialized: bool = False

    async def initialize(self):
        """Connect to all MCP servers and discover tools."""
        if self._initialized:
            return

        self._exit_stack = AsyncExitStack()
        self.tools = []
        self._tool_map = {}
        self._tool_to_server = {}
        self._sessions = {}

        for name, config in MCP_SERVERS.items():
            try:
                await self._connect_server(name, config["url"])
            except Exception as e:
                logger.warning(f"MCP {name}: failed to connect — {e}")

        self._initialized = True
        logger.info(
            f"MCP Client: {len(self.tools)} tools from "
            f"{len(self._sessions)} servers ({self.server_summary})"
        )

    async def _connect_server(self, server_name: str, url: str):
        """Connect to a single MCP server and discover its tools."""
        try:
            # Create persistent SSE connection via exit stack
            sse_url = f"{url}/sse"
            read, write = await self._exit_stack.enter_async_context(
                sse_client(sse_url)
            )

            session = await self._exit_stack.enter_async_context(
                ClientSession(read, write)
            )

            await session.initialize()
            result = await session.list_tools()

            self._sessions[server_name] = session

            for t in result.tools:
                tool = MCPTool(
                    name=t.name,
                    description=t.description or "",
                    input_schema=t.inputSchema or {"type": "object", "properties": {}},
                    server_name=server_name,
                )
                self.tools.append(tool)
                self._tool_map[t.name] = tool
                self._tool_to_server[t.name] = server_name

            logger.info(f"MCP {server_name}: {len(result.tools)} tools")

        except Exception as e:
            logger.warning(f"MCP {server_name} ({url}): {e}")

    async def call_tool(self, tool_name: str, arguments: dict) -> str:
        """Call a tool on its MCP server via the persistent session."""
        tool = self._tool_map.get(tool_name)
        if not tool:
            return f"Error: unknown tool '{tool_name}'"

        server_name = self._tool_to_server.get(tool_name)
        session = self._sessions.get(server_name)
        if not session:
            return f"Error: no session for server '{server_name}'"

        try:
            result = await asyncio.wait_for(
                session.call_tool(tool_name, arguments=arguments),
                timeout=60.0,
            )

            # Extract text content from MCP response
            texts = []
            for content in result.content:
                if hasattr(content, "text"):
                    texts.append(content.text)
                else:
                    texts.append(str(content))

            return "\n".join(texts) if texts else "No output"

        except asyncio.TimeoutError:
            return f"Error: tool '{tool_name}' timed out (60s)"
        except Exception as e:
            return f"Error calling '{tool_name}': {e}"

    def get_anthropic_tools(self) -> list[dict]:
        """Convert MCP tools to Anthropic tool_use format."""
        return [
            {
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.input_schema,
            }
            for tool in self.tools
        ]

    @property
    def tool_count(self) -> int:
        return len(self.tools)

    @property
    def server_summary(self) -> str:
        counts = {}
        for tool in self.tools:
            counts[tool.server_name] = counts.get(tool.server_name, 0) + 1
        return ", ".join(f"{name}({count})" for name, count in sorted(counts.items()))

    async def close(self):
        """Close all MCP connections."""
        if self._exit_stack:
            await self._exit_stack.aclose()
            self._exit_stack = None
            self._initialized = False
            self._sessions = {}


# ---------------------------------------------------------------------------
# Singleton
# ---------------------------------------------------------------------------
_manager: MCPClientManager | None = None


async def get_mcp_manager() -> MCPClientManager:
    """Get or create the MCP client manager singleton."""
    global _manager
    if _manager is None or not _manager._initialized:
        _manager = MCPClientManager()
        await _manager.initialize()
    return _manager

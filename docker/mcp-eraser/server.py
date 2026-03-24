"""
MCP Server: Eraser — Generate architecture diagrams via DiagramGPT API.

Tools:
  - eraser_generate_diagram: Generate diagram from text description
"""

import os
import json
import logging
import httpx
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("mcp-eraser")

ERASER_API_TOKEN = os.environ.get("ERASER_API_TOKEN", "")
ERASER_API_URL = "https://app.eraser.io/api/render/prompt"

mcp = FastMCP("Eraser Diagrams")


@mcp.tool()
def eraser_generate_diagram(
    description: str,
    diagram_type: str = "architecture",
    theme: str = "dark",
) -> str:
    """Generate an architecture diagram from a text description using Eraser DiagramGPT.

    Args:
        description: Natural language description of the diagram to generate.
            Example: "AWS architecture with ECS Fargate, RDS PostgreSQL, ElastiCache Redis,
            ALB, S3, SQS. The API receives requests via ALB, processes with ECS,
            stores in RDS, caches in Redis, queues async jobs in SQS."
        diagram_type: Type of diagram. Options: architecture, sequence, entity-relationship,
            cloud-architecture, flow-chart, class-diagram
        theme: Color theme. Options: dark, light
    """
    if not ERASER_API_TOKEN:
        return "Error: ERASER_API_TOKEN not configured"

    headers = {
        "Authorization": f"Bearer {ERASER_API_TOKEN}",
        "Content-Type": "application/json",
    }

    payload = {
        "text": description,
        "diagramType": diagram_type,
        "background": True,
        "theme": theme,
        "scale": "2",
        "returnFile": True,
    }

    try:
        with httpx.Client(timeout=30.0) as client:
            resp = client.post(ERASER_API_URL, headers=headers, json=payload)
            resp.raise_for_status()
            data = resp.json()

            file_url = data.get("fileUrl", "")
            diagram_code = data.get("code", "")

            result = f"Diagram generated!\n"
            if file_url:
                result += f"Image URL: {file_url}\n"
            if diagram_code:
                result += f"\nDiagram code:\n```\n{diagram_code[:2000]}\n```"

            return result

    except httpx.HTTPStatusError as e:
        return f"Error: Eraser API returned {e.response.status_code}: {e.response.text[:200]}"
    except Exception as e:
        return f"Error generating diagram: {e}"


@mcp.tool()
def eraser_generate_from_code(
    diagram_code: str,
    theme: str = "dark",
) -> str:
    """Render a diagram from Eraser diagram-as-code syntax.

    Args:
        diagram_code: Eraser diagram-as-code syntax.
            Example:
            ```
            Client > ALB > ECS [Fargate]
            ECS > RDS [PostgreSQL]
            ECS > Redis [ElastiCache]
            ECS > SQS
            SQS > Worker [Horizon]
            ```
        theme: Color theme (dark/light)
    """
    if not ERASER_API_TOKEN:
        return "Error: ERASER_API_TOKEN not configured"

    headers = {
        "Authorization": f"Bearer {ERASER_API_TOKEN}",
        "Content-Type": "application/json",
    }

    payload = {
        "code": diagram_code,
        "background": True,
        "theme": theme,
        "scale": "2",
        "returnFile": True,
    }

    try:
        with httpx.Client(timeout=30.0) as client:
            resp = client.post(
                "https://app.eraser.io/api/render/elements",
                headers=headers,
                json=payload,
            )
            resp.raise_for_status()
            data = resp.json()

            file_url = data.get("fileUrl", "")
            return f"Diagram rendered!\nImage URL: {file_url}" if file_url else f"Response: {data}"

    except httpx.HTTPStatusError as e:
        return f"Error: Eraser API returned {e.response.status_code}: {e.response.text[:200]}"
    except Exception as e:
        return f"Error rendering diagram: {e}"


if __name__ == "__main__":
    import uvicorn
    app = mcp.sse_app()
    uvicorn.run(app, host="0.0.0.0", port=8006)

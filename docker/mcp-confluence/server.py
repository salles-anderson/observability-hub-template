"""
MCP Server: Confluence — Create, read, update pages in Atlassian Confluence.

Tools:
  - confluence_list_spaces: List all spaces
  - confluence_search_pages: Search pages by title
  - confluence_get_page: Read page content
  - confluence_create_page: Create new page
  - confluence_update_page: Update existing page
  - confluence_get_child_pages: List child pages
"""

import os
import json
import base64
import logging
import httpx
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("mcp-confluence")

CONFLUENCE_URL = os.environ.get("CONFLUENCE_URL", "https://yourorg.atlassian.net")
CONFLUENCE_EMAIL = os.environ.get("CONFLUENCE_EMAIL", "anderson.sales@yourorg.com.br")
CONFLUENCE_TOKEN = os.environ.get("CONFLUENCE_TOKEN", "")

mcp = FastMCP("Confluence")

def _auth_header() -> str:
    creds = f"{CONFLUENCE_EMAIL}:{CONFLUENCE_TOKEN}"
    return f"Basic {base64.b64encode(creds.encode()).decode()}"

def _client() -> httpx.Client:
    return httpx.Client(
        base_url=f"{CONFLUENCE_URL}/wiki/rest/api",
        headers={
            "Authorization": _auth_header(),
            "Content-Type": "application/json",
        },
        timeout=30.0,
    )


@mcp.tool()
def confluence_list_spaces(limit: int = 25) -> str:
    """List all Confluence spaces with keys and names."""
    with _client() as c:
        resp = c.get(f"/space?limit={limit}")
        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", [])
        lines = [f"Spaces ({len(results)}):"]
        for s in results:
            lines.append(f"  {s['key']:15} | {s['name']}")
        return "\n".join(lines)


@mcp.tool()
def confluence_search_pages(query: str, space_key: str = "", limit: int = 10) -> str:
    """Search Confluence pages by title or content.

    Args:
        query: Search text (title or content)
        space_key: Optional space key to filter (e.g., 'SC')
        limit: Max results (default 10)
    """
    with _client() as c:
        cql = f'type=page AND title~"{query}"'
        if space_key:
            cql += f' AND space.key="{space_key}"'
        resp = c.get(f"/content/search?cql={cql}&limit={limit}")
        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", [])
        lines = [f"Results ({len(results)}):"]
        for r in results:
            space = r.get("resultGlobalContainer", {}).get("title", "?")
            lines.append(f"  ID:{r['content']['id']:12} | {r['content']['title']} [{space}]")
        return "\n".join(lines)


@mcp.tool()
def confluence_get_page(page_id: str) -> str:
    """Read a Confluence page content by ID.

    Args:
        page_id: The page ID (e.g., '286916610')
    """
    with _client() as c:
        resp = c.get(f"/content/{page_id}?expand=body.storage,version,space")
        resp.raise_for_status()
        data = resp.json()
        title = data.get("title", "?")
        space = data.get("space", {}).get("key", "?")
        version = data.get("version", {}).get("number", 0)
        body = data.get("body", {}).get("storage", {}).get("value", "")

        # Strip HTML tags for readability
        import re
        text = re.sub(r'<[^>]+>', ' ', body)
        text = re.sub(r'\s+', ' ', text).strip()

        return f"Title: {title}\nSpace: {space}\nVersion: {version}\nContent ({len(body)} chars):\n{text[:3000]}"


@mcp.tool()
def confluence_create_page(
    title: str,
    body_html: str,
    space_key: str = "SC",
    parent_id: str = "166428854",
) -> str:
    """Create a new Confluence page with HTML content.

    Args:
        title: Page title
        body_html: HTML content for the page body
        space_key: Space key (default 'SC' = Stark Center)
        parent_id: Parent page ID (default '166428854' = Stark Center Home)
    """
    with _client() as c:
        payload = {
            "type": "page",
            "title": title,
            "space": {"key": space_key},
            "ancestors": [{"id": parent_id}],
            "body": {
                "storage": {
                    "value": body_html,
                    "representation": "storage",
                }
            },
        }
        resp = c.post("/content", json=payload)
        resp.raise_for_status()
        data = resp.json()
        page_id = data.get("id", "?")
        url = data.get("_links", {}).get("base", "") + data.get("_links", {}).get("webui", "")
        return f"Page created!\nID: {page_id}\nTitle: {title}\nURL: {url}"


@mcp.tool()
def confluence_update_page(
    page_id: str,
    title: str,
    body_html: str,
) -> str:
    """Update an existing Confluence page content.

    Args:
        page_id: The page ID to update
        title: New page title
        body_html: New HTML content
    """
    with _client() as c:
        # Get current version
        resp = c.get(f"/content/{page_id}?expand=version")
        resp.raise_for_status()
        current_version = resp.json().get("version", {}).get("number", 0)

        payload = {
            "version": {"number": current_version + 1},
            "title": title,
            "type": "page",
            "body": {
                "storage": {
                    "value": body_html,
                    "representation": "storage",
                }
            },
        }
        resp = c.put(f"/content/{page_id}", json=payload)
        resp.raise_for_status()
        data = resp.json()
        url = data.get("_links", {}).get("base", "") + data.get("_links", {}).get("webui", "")
        return f"Page updated!\nID: {page_id}\nVersion: {current_version + 1}\nURL: {url}"


@mcp.tool()
def confluence_get_child_pages(page_id: str, limit: int = 25) -> str:
    """List child pages of a given page.

    Args:
        page_id: Parent page ID
        limit: Max results (default 25)
    """
    with _client() as c:
        resp = c.get(f"/content/{page_id}/child/page?limit={limit}")
        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", [])
        lines = [f"Child pages ({len(results)}):"]
        for r in results:
            lines.append(f"  ID:{r['id']:12} | {r['title']}")
        return "\n".join(lines)


if __name__ == "__main__":
    import uvicorn
    app = mcp.sse_app()
    uvicorn.run(app, host="0.0.0.0", port=8005)

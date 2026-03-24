"""
GitHub tools for Claude tool_use — Teck AI Assistant v10.

Defines tools that Claude can call to read code, PRs, commits and workflows
from GitHub repos via REST API. READ-ONLY — no write/delete/create operations.

Each tool:
  1. Is defined as an Anthropic tool schema (TOOLS list)
  2. Has an executor function that calls the GitHub REST API
  3. Returns formatted data for Claude to analyze

Security: Uses fine-grained PAT with read-only permissions (Contents, PRs,
Actions, Metadata). Token stored in AWS SSM Parameter Store (KMS encrypted).

Used by: agent.py _query_anthropic_with_tools()
"""

import os
import logging
import base64

import httpx

logger = logging.getLogger("github-tools")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_ORG = os.environ.get("GITHUB_ORG", "YOUR_ORG")
GITHUB_API = "https://api.github.com"

_client: httpx.AsyncClient | None = None


async def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None:
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if GITHUB_TOKEN:
            headers["Authorization"] = f"Bearer {GITHUB_TOKEN}"
        _client = httpx.AsyncClient(
            timeout=15.0,
            headers=headers,
        )
    return _client


# ---------------------------------------------------------------------------
# Tool definitions (Anthropic tool_use format)
# ---------------------------------------------------------------------------
TOOLS: list[dict] = [
    {
        "name": "github_list_contents",
        "description": (
            "Liste o conteudo de um diretorio em um repositorio GitHub. "
            "Use para explorar a estrutura de pastas e arquivos de um projeto. "
            "Retorna nome, tipo (file/dir) e tamanho de cada item."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "repo": {
                    "type": "string",
                    "description": (
                        "Nome do repositorio (sem org). "
                        "Exemplos: example-api-api, teck-observability-hub, example-api-infra"
                    ),
                },
                "path": {
                    "type": "string",
                    "description": (
                        "Caminho dentro do repo (default: raiz). "
                        "Exemplos: src, src/controllers, terraform/environment"
                    ),
                },
                "ref": {
                    "type": "string",
                    "description": "Branch ou tag (default: main).",
                },
            },
            "required": ["repo"],
        },
    },
    {
        "name": "github_get_file",
        "description": (
            "Leia o conteudo completo de um arquivo em um repositorio GitHub. "
            "Use para analisar codigo, configuracoes, Dockerfiles, READMEs, etc. "
            "Retorna o conteudo do arquivo em texto."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "repo": {
                    "type": "string",
                    "description": "Nome do repositorio (sem org).",
                },
                "path": {
                    "type": "string",
                    "description": (
                        "Caminho completo do arquivo. "
                        "Exemplos: src/app.ts, Dockerfile, package.json, README.md"
                    ),
                },
                "ref": {
                    "type": "string",
                    "description": "Branch ou tag (default: main).",
                },
            },
            "required": ["repo", "path"],
        },
    },
    {
        "name": "github_search_code",
        "description": (
            "Busque codigo em repositorios da org YOUR_ORG. "
            "Use para encontrar funcoes, classes, imports, configuracoes, "
            "variaveis de ambiente, ou qualquer padrao no codigo."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": (
                        "Termo de busca. Exemplos: "
                        "DATABASE_URL, class AuthMiddleware, FROM node:, "
                        "import prisma, ANTHROPIC_API_KEY"
                    ),
                },
                "repo": {
                    "type": "string",
                    "description": (
                        "Filtrar por repositorio especifico (opcional). "
                        "Se omitido, busca em todos os repos da org."
                    ),
                },
                "extension": {
                    "type": "string",
                    "description": "Filtrar por extensao (opcional). Exemplos: ts, py, tf, yaml",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "github_get_repo_info",
        "description": (
            "Obtenha informacoes basicas de um repositorio: "
            "linguagem, descricao, branches, ultimo push, tamanho. "
            "Use como primeiro passo para entender um projeto."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "repo": {
                    "type": "string",
                    "description": "Nome do repositorio (sem org).",
                },
            },
            "required": ["repo"],
        },
    },
    {
        "name": "github_get_commits",
        "description": (
            "Liste os commits recentes de um repositorio. "
            "Use para ver o que mudou, quem fez, quando foi o ultimo deploy. "
            "Pode filtrar por branch e caminho."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "repo": {
                    "type": "string",
                    "description": "Nome do repositorio (sem org).",
                },
                "branch": {
                    "type": "string",
                    "description": "Branch (default: main).",
                },
                "path": {
                    "type": "string",
                    "description": "Filtrar commits que tocaram este caminho (opcional).",
                },
                "count": {
                    "type": "integer",
                    "description": "Numero de commits (default: 10, max: 30).",
                },
            },
            "required": ["repo"],
        },
    },
    {
        "name": "github_list_prs",
        "description": (
            "Liste pull requests de um repositorio. "
            "Use para ver PRs abertos, recentemente merged, ou buscar uma PR especifica."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "repo": {
                    "type": "string",
                    "description": "Nome do repositorio (sem org).",
                },
                "state": {
                    "type": "string",
                    "description": "Estado: open, closed, all (default: open).",
                },
                "count": {
                    "type": "integer",
                    "description": "Numero de PRs (default: 30, max: 100).",
                },
            },
            "required": ["repo"],
        },
    },
    {
        "name": "github_get_pr_diff",
        "description": (
            "Obtenha o diff completo de uma pull request. "
            "Use para fazer code review, entender mudancas, "
            "identificar problemas no codigo."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "repo": {
                    "type": "string",
                    "description": "Nome do repositorio (sem org).",
                },
                "pr_number": {
                    "type": "integer",
                    "description": "Numero da PR.",
                },
            },
            "required": ["repo", "pr_number"],
        },
    },
    {
        "name": "github_get_workflow_runs",
        "description": (
            "Liste as execucoes recentes de GitHub Actions (CI/CD). "
            "Use para verificar se o CI esta passando, ver falhas de build, "
            "status de deploys."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "repo": {
                    "type": "string",
                    "description": "Nome do repositorio (sem org).",
                },
                "count": {
                    "type": "integer",
                    "description": "Numero de runs (default: 10, max: 20).",
                },
            },
            "required": ["repo"],
        },
    },
    {
        "name": "github_search_prs",
        "description": (
            "Busque pull requests em um ou mais repositorios da org YOUR_ORG. "
            "Use quando o usuario perguntar sobre PRs de um projeto que pode ter "
            "multiplos repos (ex: example-api-api + example-api frontend). "
            "Busca via GitHub Search API — suporta filtros avancados."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": (
                        "Termo de busca (ex: nome do projeto). "
                        "Exemplos: 'example-api', 'observability', 'frontconsig'"
                    ),
                },
                "state": {
                    "type": "string",
                    "description": "Estado: open, closed, all (default: open).",
                },
                "repo": {
                    "type": "string",
                    "description": (
                        "Filtrar por repo especifico (opcional). "
                        "Se omitido, busca em TODOS os repos da org."
                    ),
                },
                "author": {
                    "type": "string",
                    "description": "Filtrar por autor (opcional). Ex: dependabot[bot], anderson-sales",
                },
                "count": {
                    "type": "integer",
                    "description": "Numero de resultados (default: 50, max: 100).",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "github_list_repos",
        "description": (
            "Liste repositorios da org YOUR_ORG. "
            "Use para descobrir todos os repos relacionados a um projeto "
            "(ex: 'example-api' retorna example-api-api, example-api, example-api-infra, etc). "
            "Essencial ANTES de listar PRs para garantir cobertura completa."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": (
                        "Filtro por nome do repo (opcional). "
                        "Exemplos: 'example-api', 'frontconsig', 'observability'"
                    ),
                },
                "count": {
                    "type": "integer",
                    "description": "Numero de repos (default: 30, max: 100).",
                },
            },
            "required": [],
        },
    },
]


# ---------------------------------------------------------------------------
# Tool executors
# ---------------------------------------------------------------------------
async def execute_tool(name: str, input_data: dict) -> str:
    """Execute a GitHub tool by name and return result as string for Claude."""
    if not GITHUB_TOKEN:
        return "GITHUB_TOKEN nao configurado — nao e possivel acessar repositorios."

    executors = {
        "github_list_contents": _exec_list_contents,
        "github_get_file": _exec_get_file,
        "github_search_code": _exec_search_code,
        "github_get_repo_info": _exec_repo_info,
        "github_get_commits": _exec_commits,
        "github_list_prs": _exec_list_prs,
        "github_get_pr_diff": _exec_pr_diff,
        "github_get_workflow_runs": _exec_workflow_runs,
        "github_search_prs": _exec_search_prs,
        "github_list_repos": _exec_list_repos,
    }
    executor = executors.get(name)
    if not executor:
        return f"Tool '{name}' nao encontrada."
    try:
        return await executor(input_data)
    except httpx.HTTPStatusError as e:
        if e.response.status_code == 404:
            return f"Recurso nao encontrado (404). Verifique repo/path/PR."
        if e.response.status_code == 403:
            return f"Acesso negado (403). Token sem permissao para este recurso."
        logger.error(f"GitHub API error: {e}")
        return f"Erro GitHub API ({e.response.status_code}): {e}"
    except Exception as e:
        logger.error(f"Tool {name} error: {e}")
        return f"Erro ao executar {name}: {e}"


async def _exec_list_contents(params: dict) -> str:
    """List directory contents in a repo."""
    client = await _get_client()
    repo = params["repo"]
    path = params.get("path", "")
    ref = params.get("ref", "main")

    resp = await client.get(
        f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}/contents/{path}",
        params={"ref": ref},
    )
    resp.raise_for_status()
    items = resp.json()

    if isinstance(items, dict):
        # Single file, not directory
        return f"`{path}` e um arquivo, nao um diretorio. Use github_get_file para ler."

    formatted = []
    dirs = sorted([i for i in items if i["type"] == "dir"], key=lambda x: x["name"])
    files = sorted([i for i in items if i["type"] != "dir"], key=lambda x: x["name"])

    for d in dirs:
        formatted.append(f"  📁 {d['name']}/")
    for f in files:
        size = f.get("size", 0)
        size_str = f"{size:,}B" if size < 1024 else f"{size/1024:.1f}KB"
        formatted.append(f"  📄 {f['name']} ({size_str})")

    header = f"Conteudo de `{GITHUB_ORG}/{repo}/{path}` (branch: {ref}):"
    return header + "\n" + "\n".join(formatted)


async def _exec_get_file(params: dict) -> str:
    """Read file contents from a repo."""
    client = await _get_client()
    repo = params["repo"]
    path = params["path"]
    ref = params.get("ref", "main")

    resp = await client.get(
        f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}/contents/{path}",
        params={"ref": ref},
    )
    resp.raise_for_status()
    data = resp.json()

    if isinstance(data, list):
        return f"`{path}` e um diretorio. Use github_list_contents para listar."

    size = data.get("size", 0)
    if size > 500_000:
        return f"Arquivo muito grande ({size/1024:.0f}KB). Limite: 500KB."

    content_b64 = data.get("content", "")
    try:
        content = base64.b64decode(content_b64).decode("utf-8")
    except Exception:
        return f"Arquivo binario — nao e possivel exibir conteudo de `{path}`."

    # Truncate very long files
    lines = content.split("\n")
    if len(lines) > 500:
        content = "\n".join(lines[:500])
        content += f"\n\n... (truncado — {len(lines)} linhas total, mostrando 500)"

    return f"Arquivo `{GITHUB_ORG}/{repo}/{path}` ({len(lines)} linhas):\n```\n{content}\n```"


async def _exec_search_code(params: dict) -> str:
    """Search code across repos."""
    client = await _get_client()
    query = params["query"]
    repo = params.get("repo")
    ext = params.get("extension")

    # Build search query
    q = f"{query} org:{GITHUB_ORG}"
    if repo:
        q = f"{query} repo:{GITHUB_ORG}/{repo}"
    if ext:
        q += f" extension:{ext}"

    resp = await client.get(
        f"{GITHUB_API}/search/code",
        params={"q": q, "per_page": 15},
    )
    resp.raise_for_status()
    data = resp.json()

    total = data.get("total_count", 0)
    items = data.get("items", [])

    if not items:
        return f"Nenhum resultado para: `{query}`"

    formatted = []
    for item in items[:15]:
        repo_name = item["repository"]["name"]
        file_path = item["path"]
        formatted.append(f"  {repo_name}/{file_path}")

    return f"{total} resultado(s) para `{query}`:\n" + "\n".join(formatted)


async def _exec_repo_info(params: dict) -> str:
    """Get repository info."""
    client = await _get_client()
    repo = params["repo"]

    resp = await client.get(f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}")
    resp.raise_for_status()
    data = resp.json()

    # Get branches
    branches_resp = await client.get(
        f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}/branches",
        params={"per_page": 10},
    )
    branches = [b["name"] for b in branches_resp.json()] if branches_resp.status_code == 200 else []

    info = [
        f"## {GITHUB_ORG}/{repo}",
        f"**Descricao:** {data.get('description') or 'Sem descricao'}",
        f"**Linguagem:** {data.get('language') or 'N/A'}",
        f"**Visibilidade:** {data.get('visibility', 'N/A')}",
        f"**Default branch:** {data.get('default_branch', 'main')}",
        f"**Branches:** {', '.join(branches[:10]) if branches else 'N/A'}",
        f"**Tamanho:** {data.get('size', 0)/1024:.1f}MB",
        f"**Ultimo push:** {data.get('pushed_at', 'N/A')[:10]}",
        f"**Criado em:** {data.get('created_at', 'N/A')[:10]}",
        f"**Abertos — Issues:** {data.get('open_issues_count', 0)}",
    ]

    return "\n".join(info)


async def _exec_commits(params: dict) -> str:
    """List recent commits."""
    client = await _get_client()
    repo = params["repo"]
    branch = params.get("branch", "main")
    path = params.get("path")
    count = min(params.get("count", 10), 30)

    query_params = {"sha": branch, "per_page": count}
    if path:
        query_params["path"] = path

    resp = await client.get(
        f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}/commits",
        params=query_params,
    )
    resp.raise_for_status()
    commits = resp.json()

    if not commits:
        return f"Nenhum commit encontrado em `{repo}` (branch: {branch})"

    formatted = []
    for c in commits:
        sha = c["sha"][:7]
        msg = c["commit"]["message"].split("\n")[0][:80]
        author = c["commit"]["author"]["name"]
        date = c["commit"]["author"]["date"][:10]
        formatted.append(f"  `{sha}` {date} ({author}): {msg}")

    header = f"{len(commits)} commit(s) recentes em `{repo}` (branch: {branch}):"
    return header + "\n" + "\n".join(formatted)


async def _exec_list_prs(params: dict) -> str:
    """List pull requests."""
    client = await _get_client()
    repo = params["repo"]
    state = params.get("state", "open")
    count = min(params.get("count", 30), 100)

    resp = await client.get(
        f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}/pulls",
        params={"state": state, "per_page": count, "sort": "created", "direction": "desc"},
    )
    resp.raise_for_status()
    prs = resp.json()

    if not prs:
        return f"Nenhuma PR ({state}) em `{repo}`"

    formatted = []
    for pr in prs:
        number = pr["number"]
        title = pr["title"][:60]
        author = pr["user"]["login"]
        state_emoji = "🟢" if pr["state"] == "open" else "🟣"
        merged = " (merged)" if pr.get("merged_at") else ""
        updated = pr["updated_at"][:10]
        formatted.append(f"  {state_emoji} #{number} {title} — {author} ({updated}){merged}")

    header = f"{len(prs)} PR(s) ({state}) em `{repo}`:"
    return header + "\n" + "\n".join(formatted)


async def _exec_pr_diff(params: dict) -> str:
    """Get PR diff for code review."""
    client = await _get_client()
    repo = params["repo"]
    pr_number = params["pr_number"]

    # Get PR info
    pr_resp = await client.get(
        f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}/pulls/{pr_number}",
    )
    pr_resp.raise_for_status()
    pr = pr_resp.json()

    # Get diff
    diff_resp = await client.get(
        f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}/pulls/{pr_number}",
        headers={"Accept": "application/vnd.github.diff"},
    )
    diff_resp.raise_for_status()
    diff = diff_resp.text

    # Truncate long diffs
    if len(diff) > 30_000:
        diff = diff[:30_000] + "\n\n... (diff truncado — muito grande)"

    info = [
        f"## PR #{pr_number}: {pr['title']}",
        f"**Autor:** {pr['user']['login']}",
        f"**Branch:** {pr['head']['ref']} → {pr['base']['ref']}",
        f"**Status:** {pr['state']}{' (merged)' if pr.get('merged_at') else ''}",
        f"**Arquivos alterados:** {pr.get('changed_files', '?')}",
        f"**+{pr.get('additions', 0)} -{pr.get('deletions', 0)}**",
        f"\n```diff\n{diff}\n```",
    ]

    return "\n".join(info)


async def _exec_workflow_runs(params: dict) -> str:
    """List recent GitHub Actions workflow runs."""
    client = await _get_client()
    repo = params["repo"]
    count = min(params.get("count", 10), 20)

    resp = await client.get(
        f"{GITHUB_API}/repos/{GITHUB_ORG}/{repo}/actions/runs",
        params={"per_page": count},
    )
    resp.raise_for_status()
    data = resp.json()

    runs = data.get("workflow_runs", [])
    if not runs:
        return f"Nenhum workflow run encontrado em `{repo}`"

    formatted = []
    for run in runs:
        status = run["status"]
        conclusion = run.get("conclusion", "running")
        name = run["name"][:40]
        branch = run["head_branch"]
        created = run["created_at"][:16].replace("T", " ")

        if conclusion == "success":
            emoji = "✅"
        elif conclusion == "failure":
            emoji = "❌"
        elif status == "in_progress":
            emoji = "🔄"
        else:
            emoji = "⏸️"

        formatted.append(f"  {emoji} {name} ({branch}) — {conclusion} [{created}]")

    header = f"{len(runs)} workflow run(s) recentes em `{repo}`:"
    return header + "\n" + "\n".join(formatted)


async def _exec_search_prs(params: dict) -> str:
    """Search pull requests across repos using GitHub Search API.

    Strategy: when query looks like a project name (no spaces, short),
    first discover matching repos, then search PRs BY REPO — not by text.
    This ensures Dependabot/Actions PRs (which don't mention the project
    name in their title) are included.
    """
    client = await _get_client()
    query = params.get("query", "")
    state = params.get("state", "open")
    repo = params.get("repo")
    author = params.get("author")
    count = min(params.get("count", 50), 100)

    # If a specific repo is given, search directly in that repo
    if repo:
        q_parts = ["is:pr"]
        if state != "all":
            q_parts.append(f"is:{state}")
        q_parts.append(f"repo:{GITHUB_ORG}/{repo}")
        if author:
            q_parts.append(f"author:{author}")
        q = " ".join(q_parts)

        resp = await client.get(
            f"{GITHUB_API}/search/issues",
            params={"q": q, "per_page": count, "sort": "created", "order": "desc"},
        )
        resp.raise_for_status()
        data = resp.json()
        items = data.get("items", [])
        total = data.get("total_count", 0)

    elif query:
        # Discover repos matching the query name first
        repo_resp = await client.get(
            f"{GITHUB_API}/search/repositories",
            params={"q": f"{query} org:{GITHUB_ORG}", "per_page": 10, "sort": "updated"},
        )
        repo_resp.raise_for_status()
        matching_repos = [r["name"] for r in repo_resp.json().get("items", [])]

        if not matching_repos:
            return f"Nenhum repositorio encontrado com nome `{query}` na org {GITHUB_ORG}."

        # Search PRs in ALL matching repos (using repo: filter, not text search)
        items = []
        total = 0
        for repo_name in matching_repos:
            q_parts = ["is:pr"]
            if state != "all":
                q_parts.append(f"is:{state}")
            q_parts.append(f"repo:{GITHUB_ORG}/{repo_name}")
            if author:
                q_parts.append(f"author:{author}")
            q = " ".join(q_parts)

            resp = await client.get(
                f"{GITHUB_API}/search/issues",
                params={"q": q, "per_page": count, "sort": "created", "order": "desc"},
            )
            resp.raise_for_status()
            data = resp.json()
            items.extend(data.get("items", []))
            total += data.get("total_count", 0)

    else:
        # No query, no repo — search all org PRs
        q_parts = ["is:pr", f"org:{GITHUB_ORG}"]
        if state != "all":
            q_parts.append(f"is:{state}")
        if author:
            q_parts.append(f"author:{author}")
        q = " ".join(q_parts)

        resp = await client.get(
            f"{GITHUB_API}/search/issues",
            params={"q": q, "per_page": count, "sort": "created", "order": "desc"},
        )
        resp.raise_for_status()
        data = resp.json()
        items = data.get("items", [])
        total = data.get("total_count", 0)

    if not items:
        return f"Nenhuma PR encontrada para: `{query or 'all'}`"

    # Group by repo
    by_repo: dict[str, list] = {}
    for item in items:
        repo_url = item.get("repository_url", "")
        repo_name = repo_url.rsplit("/", 1)[-1] if repo_url else "unknown"
        by_repo.setdefault(repo_name, []).append(item)

    formatted = [f"{total} PR(s) encontrada(s) em {len(by_repo)} repo(s):\n"]
    for repo_name, prs in sorted(by_repo.items()):
        formatted.append(f"**{GITHUB_ORG}/{repo_name}** ({len(prs)} PRs):")
        for pr in prs:
            number = pr["number"]
            title = pr["title"][:60]
            user = pr["user"]["login"]
            state_emoji = "🟢" if pr["state"] == "open" else "🟣"
            created = pr["created_at"][:10]
            labels = ", ".join(l["name"] for l in pr.get("labels", [])[:3])
            label_str = f" [{labels}]" if labels else ""
            formatted.append(f"  {state_emoji} #{number} {title} — {user} ({created}){label_str}")
        formatted.append("")

    return "\n".join(formatted)


async def _exec_list_repos(params: dict) -> str:
    """List org repos, optionally filtered by name."""
    client = await _get_client()
    query = params.get("query", "")
    count = min(params.get("count", 30), 100)

    if query:
        # Use search API for filtering
        resp = await client.get(
            f"{GITHUB_API}/search/repositories",
            params={"q": f"{query} org:{GITHUB_ORG}", "per_page": count, "sort": "updated"},
        )
        resp.raise_for_status()
        repos = resp.json().get("items", [])
    else:
        # List all org repos
        resp = await client.get(
            f"{GITHUB_API}/orgs/{GITHUB_ORG}/repos",
            params={"per_page": count, "sort": "updated", "direction": "desc"},
        )
        resp.raise_for_status()
        repos = resp.json()

    if not repos:
        return f"Nenhum repositorio encontrado{f' para: {query}' if query else ''}"

    formatted = []
    for r in repos:
        name = r["name"]
        lang = r.get("language") or "N/A"
        desc = (r.get("description") or "Sem descricao")[:50]
        pushed = (r.get("pushed_at") or "")[:10]
        visibility = r.get("visibility", "private")
        formatted.append(f"  {name} ({lang}, {visibility}) — {desc} [push: {pushed}]")

    header = f"{len(repos)} repositorio(s){f' matching `{query}`' if query else ''} em {GITHUB_ORG}:"
    return header + "\n" + "\n".join(formatted)

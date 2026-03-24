"""
MCP Server — GitHub + SonarQube (AG-5)

Exposes GitHub API and SonarQube as MCP tools for code analysis,
PR management, commit history, workflow runs, and quality gates.

Organization: YOUR_ORG
Transport: SSE on port 8002
"""

import os
import logging
from datetime import datetime, timezone

import httpx
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger("mcp-github")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_ORG = os.environ.get("GITHUB_ORG", "YOUR_ORG")
GITHUB_API = "https://api.github.com"

SONARQUBE_URL = os.environ.get("SONARQUBE_URL", "http://sonarqube.observability.local:9000")
SONARQUBE_TOKEN = os.environ.get("SONARQUBE_TOKEN", "")

# ---------------------------------------------------------------------------
# HTTP clients
# ---------------------------------------------------------------------------
_gh_client: httpx.AsyncClient | None = None
_sq_client: httpx.AsyncClient | None = None


def _get_gh_client() -> httpx.AsyncClient:
    global _gh_client
    if _gh_client is None:
        _gh_client = httpx.AsyncClient(
            base_url=GITHUB_API,
            headers={
                "Authorization": f"Bearer {GITHUB_TOKEN}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            timeout=httpx.Timeout(15.0, connect=5.0),
        )
    return _gh_client


def _get_sq_client() -> httpx.AsyncClient:
    global _sq_client
    if _sq_client is None:
        _sq_client = httpx.AsyncClient(
            base_url=SONARQUBE_URL,
            headers={"Authorization": f"Bearer {SONARQUBE_TOKEN}"},
            timeout=httpx.Timeout(10.0, connect=5.0),
        )
    return _sq_client


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------
mcp = FastMCP("GitHub & SonarQube")


# --- GitHub Tools ---

@mcp.tool()
async def github_list_repos(query: str = "") -> str:
    """List repositories in YOUR_ORG org, optionally filtered by name.

    Args:
        query: Optional filter string for repo name (e.g. "example-api", "frontconsig")
    """
    try:
        client = _get_gh_client()
        resp = await client.get(f"/orgs/{GITHUB_ORG}/repos?per_page=30&sort=updated")
        resp.raise_for_status()
        repos = resp.json()

        if query:
            repos = [r for r in repos if query.lower() in r["name"].lower()]

        if not repos:
            return f"No repositories found matching '{query}' in {GITHUB_ORG}"

        lines = [f"## GitHub Repos — {GITHUB_ORG}\n"]
        lines.append("| Repo | Language | Updated | Visibility |")
        lines.append("|------|----------|---------|------------|")

        for r in repos[:20]:
            name = r["name"]
            lang = r.get("language") or "—"
            updated = r.get("updated_at", "")[:10]
            vis = r.get("visibility", "private")
            lines.append(f"| {name} | {lang} | {updated} | {vis} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error listing repos: {e}"


@mcp.tool()
async def github_get_commits(repo: str, branch: str = "main", limit: int = 10) -> str:
    """Get recent commits for a repository.

    Args:
        repo: Repository name (e.g. "example-api-api", "teck-observability-hub")
        branch: Branch name (default "main")
        limit: Number of commits (default 10, max 30)
    """
    try:
        client = _get_gh_client()
        resp = await client.get(f"/repos/{GITHUB_ORG}/{repo}/commits?sha={branch}&per_page={min(limit, 30)}")
        resp.raise_for_status()
        commits = resp.json()

        if not commits:
            return f"No commits found on {repo}/{branch}"

        lines = [f"## Commits — {repo} ({branch})\n"]
        lines.append("| Hash | Date | Author | Message |")
        lines.append("|------|------|--------|---------|")

        for c in commits:
            sha = c["sha"][:7]
            date = c["commit"]["author"]["date"][:10]
            author = c["commit"]["author"]["name"]
            msg = c["commit"]["message"].split("\n")[0][:60]
            lines.append(f"| {sha} | {date} | {author} | {msg} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting commits: {e}"


@mcp.tool()
async def github_list_prs(repo: str, state: str = "open") -> str:
    """List pull requests for a repository.

    Args:
        repo: Repository name
        state: PR state — "open", "closed", or "all" (default "open")
    """
    try:
        client = _get_gh_client()
        resp = await client.get(f"/repos/{GITHUB_ORG}/{repo}/pulls?state={state}&per_page=20&sort=updated&direction=desc")
        resp.raise_for_status()
        prs = resp.json()

        if not prs:
            return f"No {state} PRs found in {repo}"

        lines = [f"## Pull Requests — {repo} ({state})\n"]
        lines.append("| # | Title | Author | Created | Status |")
        lines.append("|---|-------|--------|---------|--------|")

        for pr in prs:
            num = pr["number"]
            title = pr["title"][:50]
            author = pr["user"]["login"]
            created = pr["created_at"][:10]
            merged = "merged" if pr.get("merged_at") else pr["state"]
            lines.append(f"| #{num} | {title} | {author} | {created} | {merged} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error listing PRs: {e}"


@mcp.tool()
async def github_search_prs(query: str, repo: str = "") -> str:
    """Search pull requests across repos or within a specific repo.

    Args:
        query: Search terms (e.g. "fix secret", "KYC", "merged:>2024-03-01")
        repo: Optional repo name to scope search
    """
    try:
        client = _get_gh_client()
        q = f"{query} org:{GITHUB_ORG}"
        if repo:
            q = f"{query} repo:{GITHUB_ORG}/{repo}"
        q += " is:pr"

        resp = await client.get(f"/search/issues?q={q}&per_page=15&sort=updated")
        resp.raise_for_status()
        items = resp.json().get("items", [])

        if not items:
            return f"No PRs found matching '{query}'"

        lines = [f"## PR Search: '{query}'\n"]
        lines.append("| # | Repo | Title | Author | Date | Status |")
        lines.append("|---|------|-------|--------|------|--------|")

        for item in items:
            num = item["number"]
            repo_name = item["repository_url"].split("/")[-1]
            title = item["title"][:40]
            author = item["user"]["login"]
            date = item["updated_at"][:10]
            state = item["state"]
            lines.append(f"| #{num} | {repo_name} | {title} | {author} | {date} | {state} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error searching PRs: {e}"


@mcp.tool()
async def github_get_pr_diff(repo: str, pr_number: int) -> str:
    """Get the diff/changes for a specific pull request.

    Args:
        repo: Repository name
        pr_number: PR number
    """
    try:
        client = _get_gh_client()
        resp = await client.get(
            f"/repos/{GITHUB_ORG}/{repo}/pulls/{pr_number}/files",
            headers={"Accept": "application/vnd.github+json"},
        )
        resp.raise_for_status()
        files = resp.json()

        if not files:
            return f"No files changed in PR #{pr_number}"

        lines = [f"## PR #{pr_number} — Files Changed ({repo})\n"]
        lines.append("| File | Status | Additions | Deletions |")
        lines.append("|------|--------|-----------|-----------|")

        total_add = 0
        total_del = 0
        for f in files:
            fname = f["filename"]
            status = f["status"]
            add = f.get("additions", 0)
            delete = f.get("deletions", 0)
            total_add += add
            total_del += delete
            lines.append(f"| {fname} | {status} | +{add} | -{delete} |")

        lines.append(f"\n**Total: {len(files)} files, +{total_add} -{total_del}**")
        return "\n".join(lines)
    except Exception as e:
        return f"Error getting PR diff: {e}"


@mcp.tool()
async def github_get_workflow_runs(repo: str, limit: int = 10) -> str:
    """Get recent GitHub Actions workflow runs for a repository.

    Args:
        repo: Repository name
        limit: Number of runs (default 10)
    """
    try:
        client = _get_gh_client()
        resp = await client.get(f"/repos/{GITHUB_ORG}/{repo}/actions/runs?per_page={min(limit, 20)}")
        resp.raise_for_status()
        runs = resp.json().get("workflow_runs", [])

        if not runs:
            return f"No workflow runs found in {repo}"

        lines = [f"## Workflow Runs — {repo}\n"]
        lines.append("| Workflow | Branch | Status | Conclusion | Date |")
        lines.append("|----------|--------|--------|------------|------|")

        for run in runs:
            name = run.get("name", "?")[:30]
            branch = run.get("head_branch", "?")
            status = run.get("status", "?")
            conclusion = run.get("conclusion") or "running"
            date = run.get("created_at", "")[:16].replace("T", " ")
            lines.append(f"| {name} | {branch} | {status} | {conclusion} | {date} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting workflow runs: {e}"


@mcp.tool()
async def github_search_code(query: str, repo: str = "") -> str:
    """Search code across YOUR_ORG repositories.

    Args:
        query: Code search query (e.g. "valueFrom", "DB_PORT_RPA", "connection pool")
        repo: Optional repo name to scope search
    """
    try:
        client = _get_gh_client()
        q = f"{query} org:{GITHUB_ORG}"
        if repo:
            q = f"{query} repo:{GITHUB_ORG}/{repo}"

        resp = await client.get(f"/search/code?q={q}&per_page=10")
        resp.raise_for_status()
        items = resp.json().get("items", [])

        if not items:
            return f"No code found matching '{query}'"

        lines = [f"## Code Search: '{query}'\n"]
        for item in items:
            repo_name = item["repository"]["name"]
            path = item["path"]
            lines.append(f"- `{repo_name}/{path}`")

        return "\n".join(lines)
    except Exception as e:
        return f"Error searching code: {e}"


@mcp.tool()
async def github_get_file(repo: str, path: str, branch: str = "main") -> str:
    """Get the content of a file from a GitHub repository.

    Args:
        repo: Repository name
        path: File path (e.g. "config/database.php", "terraform.tfvars")
        branch: Branch name (default "main")
    """
    try:
        client = _get_gh_client()
        resp = await client.get(f"/repos/{GITHUB_ORG}/{repo}/contents/{path}?ref={branch}")
        resp.raise_for_status()
        data = resp.json()

        if data.get("type") != "file":
            return f"{path} is a {data.get('type', 'unknown')}, not a file"

        import base64
        content = base64.b64decode(data["content"]).decode("utf-8")

        if len(content) > 5000:
            content = content[:5000] + "\n... [truncated]"

        return f"## {repo}/{path} ({branch})\n\n```\n{content}\n```"
    except Exception as e:
        return f"Error getting file: {e}"


@mcp.tool()
async def github_list_contents(repo: str, path: str = "", branch: str = "main") -> str:
    """List files and directories in a repository path.

    Args:
        repo: Repository name
        path: Directory path (empty for root)
        branch: Branch name (default "main")
    """
    try:
        client = _get_gh_client()
        url = f"/repos/{GITHUB_ORG}/{repo}/contents/{path}?ref={branch}" if path else f"/repos/{GITHUB_ORG}/{repo}/contents?ref={branch}"
        resp = await client.get(url)
        resp.raise_for_status()
        items = resp.json()

        if not isinstance(items, list):
            return f"{path} is a file, not a directory"

        lines = [f"## {repo}/{path or '/'} ({branch})\n"]
        dirs = [i for i in items if i["type"] == "dir"]
        files = [i for i in items if i["type"] == "file"]

        for d in sorted(dirs, key=lambda x: x["name"]):
            lines.append(f"- 📁 {d['name']}/")
        for f in sorted(files, key=lambda x: x["name"]):
            size = f.get("size", 0)
            lines.append(f"- 📄 {f['name']} ({size:,} bytes)")

        return "\n".join(lines)
    except Exception as e:
        return f"Error listing contents: {e}"


@mcp.tool()
async def github_get_repo_info(repo: str) -> str:
    """Get detailed information about a repository.

    Args:
        repo: Repository name
    """
    try:
        client = _get_gh_client()
        resp = await client.get(f"/repos/{GITHUB_ORG}/{repo}")
        resp.raise_for_status()
        r = resp.json()

        return (
            f"## {r['full_name']}\n\n"
            f"| Attribute | Value |\n"
            f"|-----------|-------|\n"
            f"| Language | {r.get('language', '—')} |\n"
            f"| Default Branch | {r.get('default_branch', 'main')} |\n"
            f"| Stars | {r.get('stargazers_count', 0)} |\n"
            f"| Open Issues | {r.get('open_issues_count', 0)} |\n"
            f"| Created | {r.get('created_at', '')[:10]} |\n"
            f"| Updated | {r.get('updated_at', '')[:10]} |\n"
            f"| Visibility | {r.get('visibility', 'private')} |\n"
            f"| Size | {r.get('size', 0):,} KB |\n"
        )
    except Exception as e:
        return f"Error getting repo info: {e}"


# --- SonarQube Tools ---

@mcp.tool()
async def sonarqube_project_status(project_key: str = "example-api-api") -> str:
    """Get SonarQube quality gate status for a project.

    Args:
        project_key: SonarQube project key (default "example-api-api")
    """
    if not SONARQUBE_TOKEN:
        return "SonarQube not configured (SONARQUBE_TOKEN missing)"

    try:
        client = _get_sq_client()
        resp = await client.get(f"/api/qualitygates/project_status?projectKey={project_key}")
        resp.raise_for_status()
        data = resp.json()

        status = data.get("projectStatus", {}).get("status", "UNKNOWN")
        conditions = data.get("projectStatus", {}).get("conditions", [])

        lines = [f"## SonarQube — {project_key}\n"]
        lines.append(f"**Quality Gate: {status}**\n")

        if conditions:
            lines.append("| Metric | Status | Value | Threshold |")
            lines.append("|--------|--------|-------|-----------|")
            for c in conditions:
                metric = c.get("metricKey", "?")
                cstatus = c.get("status", "?")
                value = c.get("actualValue", "?")
                threshold = c.get("errorThreshold", "?")
                lines.append(f"| {metric} | {cstatus} | {value} | {threshold} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting SonarQube status: {e}"


@mcp.tool()
async def sonarqube_issues(project_key: str = "example-api-api", severity: str = "") -> str:
    """Get SonarQube issues (bugs, vulnerabilities, code smells) for a project.

    Args:
        project_key: SonarQube project key
        severity: Filter by severity — "BLOCKER", "CRITICAL", "MAJOR", "MINOR", "INFO" (empty for all)
    """
    if not SONARQUBE_TOKEN:
        return "SonarQube not configured"

    try:
        client = _get_sq_client()
        url = f"/api/issues/search?componentKeys={project_key}&ps=20&resolved=false"
        if severity:
            url += f"&severities={severity.upper()}"

        resp = await client.get(url)
        resp.raise_for_status()
        data = resp.json()

        issues = data.get("issues", [])
        total = data.get("total", 0)

        if not issues:
            return f"No open issues found in {project_key}" + (f" with severity {severity}" if severity else "")

        lines = [f"## SonarQube Issues — {project_key} ({total} total)\n"]
        lines.append("| Type | Severity | Message | File |")
        lines.append("|------|----------|---------|------|")

        for issue in issues[:20]:
            itype = issue.get("type", "?")
            isev = issue.get("severity", "?")
            msg = issue.get("message", "?")[:50]
            component = issue.get("component", "?").split(":")[-1]
            lines.append(f"| {itype} | {isev} | {msg} | {component} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting SonarQube issues: {e}"


@mcp.tool()
async def sonarqube_metrics(project_key: str = "example-api-api") -> str:
    """Get SonarQube code quality metrics (coverage, duplications, complexity).

    Args:
        project_key: SonarQube project key
    """
    if not SONARQUBE_TOKEN:
        return "SonarQube not configured"

    try:
        client = _get_sq_client()
        metrics = "coverage,duplicated_lines_density,ncloc,bugs,vulnerabilities,code_smells,sqale_rating,reliability_rating,security_rating"
        resp = await client.get(f"/api/measures/component?component={project_key}&metricKeys={metrics}")
        resp.raise_for_status()
        data = resp.json()

        measures = data.get("component", {}).get("measures", [])
        if not measures:
            return f"No metrics found for {project_key}"

        lines = [f"## SonarQube Metrics — {project_key}\n"]
        lines.append("| Metric | Value |")
        lines.append("|--------|-------|")

        for m in measures:
            metric = m.get("metric", "?")
            value = m.get("value", "?")
            lines.append(f"| {metric} | {value} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting SonarQube metrics: {e}"


if __name__ == "__main__":
    import uvicorn
    app = mcp.sse_app()
    uvicorn.run(app, host="0.0.0.0", port=8002)  # noqa: S104

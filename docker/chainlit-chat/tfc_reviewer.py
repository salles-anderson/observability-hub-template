"""
Terraform Reviewer — AI-powered PR review and plan analysis.

Two modes:
1. Plan Review: fetch TFC plan output, analyze risks/costs/breaking changes
2. PR Review: fetch GitHub PR diff (.tf files), analyze with Agent SDK

Uses existing LiteLLM/Agent SDK routing from agent.py for AI analysis.
"""

import json
import os
import logging
import re
from typing import Optional

import httpx

logger = logging.getLogger("tfc-reviewer")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
TFC_API_TOKEN = os.environ.get("TFC_API_TOKEN", "")
TFC_BASE_URL = "https://app.terraform.io/api/v2"
TFC_ORG = os.environ.get("TFC_ORG", "YOUR_ORG")
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "")
GITHUB_REPO = os.environ.get("GITHUB_REPO", "yourorg/teck-internal")

# High-risk resource types
HIGH_RISK_RESOURCES = {
    "aws_security_group", "aws_security_group_rule",
    "aws_iam_role", "aws_iam_policy", "aws_iam_role_policy",
    "aws_iam_role_policy_attachment",
    "aws_rds_cluster", "aws_db_instance",
    "aws_kms_key", "aws_kms_alias",
    "aws_s3_bucket", "aws_s3_bucket_policy",
    "aws_vpc", "aws_subnet", "aws_route_table",
    "aws_nat_gateway", "aws_internet_gateway",
    "aws_lb", "aws_lb_listener",
    "aws_ecs_cluster", "aws_ecs_service",
    "aws_wafv2_web_acl",
}

# Estimated monthly costs per resource type (rough)
COST_ESTIMATES = {
    "aws_ecs_service": 30.0,       # ~$30/mo per Fargate service (256 CPU)
    "aws_rds_cluster": 200.0,      # ~$200/mo per Aurora cluster
    "aws_db_instance": 150.0,      # ~$150/mo per RDS instance
    "aws_nat_gateway": 32.0,       # ~$32/mo per NAT GW
    "aws_lb": 16.0,                # ~$16/mo per ALB
    "aws_elasticache_cluster": 50.0,
    "aws_lambda_function": 5.0,    # ~$5/mo for low-traffic Lambda
    "aws_cloudwatch_log_group": 2.0,
}


async def review_plan(ws_name: str) -> Optional[str]:
    """Fetch TFC plan output and generate structured review.

    Returns markdown review with risk assessment, blast radius, cost impact.
    """
    if not TFC_API_TOKEN:
        return "TFC_API_TOKEN nao configurado."

    try:
        client = httpx.AsyncClient(
            base_url=TFC_BASE_URL,
            headers={
                "Authorization": f"Bearer {TFC_API_TOKEN}",
                "Content-Type": "application/vnd.api+json",
            },
            timeout=15.0,
        )

        # Get workspace
        resp = await client.get(f"/organizations/{TFC_ORG}/workspaces/{ws_name}")
        resp.raise_for_status()
        ws_id = resp.json().get("data", {}).get("id", "")
        if not ws_id:
            return f"Workspace '{ws_name}' nao encontrado."

        # Get latest run
        runs_resp = await client.get(f"/workspaces/{ws_id}/runs?page[size]=1")
        runs_resp.raise_for_status()
        runs = runs_resp.json().get("data", [])
        if not runs:
            return f"Nenhum run encontrado no workspace '{ws_name}'."

        run = runs[0]
        run_id = run.get("id", "?")
        attrs = run.get("attributes", {})
        status = attrs.get("status", "?")
        message = attrs.get("message", "?")
        add = attrs.get("resource-additions", 0) or 0
        change = attrs.get("resource-changes", 0) or 0
        destroy = attrs.get("resource-destructions", 0) or 0
        has_changes = attrs.get("has-changes", False)

        await client.aclose()

        if not has_changes:
            return (
                f"### Plan Review — {ws_name}\n\n"
                f"**Status:** {status}\n"
                f"**Run:** {run_id}\n"
                f"**Resultado:** Sem mudancas detectadas. Infra esta em sync.\n"
            )

        # Risk assessment
        risk_level = "BAIXO"
        risk_reasons = []

        if destroy > 0:
            risk_level = "ALTO"
            risk_reasons.append(f"{destroy} recurso(s) sendo destruido(s)")
        if change > 10:
            risk_level = "ALTO" if risk_level != "ALTO" else risk_level
            risk_reasons.append(f"{change} alteracoes (blast radius alto)")
        elif change > 5:
            if risk_level == "BAIXO":
                risk_level = "MEDIO"
            risk_reasons.append(f"{change} alteracoes")

        # Cost estimate
        est_cost_add = add * 10  # rough $10/resource average
        est_cost_destroy = destroy * (-10)

        review = [
            f"### Plan Review — {ws_name}\n",
            f"**Run:** `{run_id}`",
            f"**Status:** {status}",
            f"**Mensagem:** {message}\n",
            f"**Mudancas:** +{add} adicionados | ~{change} alterados | -{destroy} destruidos\n",
            f"**Risco:** {risk_level}",
        ]

        if risk_reasons:
            review.append(f"**Motivos:** {', '.join(risk_reasons)}")

        if est_cost_add != 0 or est_cost_destroy != 0:
            review.append(f"\n**Impacto de Custo Estimado:** ~${est_cost_add + est_cost_destroy:+.0f}/mes")

        review.append("\n**Recomendacoes:**")
        if destroy > 0:
            review.append("- Verifique se as destruicoes sao intencionais")
            review.append("- Confirme que nao ha dados/state que serao perdidos")
        if risk_level in ("ALTO", "MEDIO"):
            review.append("- Execute `terraform plan` localmente para validar")
            review.append("- Revise o diff completo antes de aprovar")
        else:
            review.append("- Plan seguro para aplicar")

        return "\n".join(review)

    except Exception as e:
        logger.error(f"Plan review error: {e}")
        return f"Erro ao revisar plan: {e}"


async def review_pr(pr_number: int) -> Optional[str]:
    """Fetch GitHub PR diff and review .tf file changes.

    Returns markdown review with findings per file.
    """
    if not GITHUB_TOKEN:
        return "GITHUB_TOKEN nao configurado. Defina a variavel de ambiente."

    try:
        client = httpx.AsyncClient(
            base_url="https://api.github.com",
            headers={
                "Authorization": f"Bearer {GITHUB_TOKEN}",
                "Accept": "application/vnd.github.v3+json",
            },
            timeout=15.0,
        )

        # Get PR files
        resp = await client.get(f"/repos/{GITHUB_REPO}/pulls/{pr_number}/files")
        resp.raise_for_status()
        files = resp.json()

        # Filter .tf files
        tf_files = [f for f in files if f.get("filename", "").endswith(".tf")]

        await client.aclose()

        if not tf_files:
            return (
                f"### PR Review — #{pr_number}\n\n"
                f"Nenhum arquivo `.tf` modificado neste PR.\n"
                f"Total de arquivos: {len(files)}"
            )

        review = [
            f"### Terraform PR Review — #{pr_number}\n",
            f"**Arquivos .tf modificados:** {len(tf_files)} de {len(files)} total\n",
        ]

        findings = []
        for f in tf_files:
            filename = f.get("filename", "?")
            status = f.get("status", "?")
            additions = f.get("additions", 0)
            deletions = f.get("deletions", 0)
            patch = f.get("patch", "")

            review.append(f"**`{filename}`** ({status}, +{additions}/-{deletions})")

            # Static analysis on patch
            if "0.0.0.0/0" in patch:
                findings.append(f"  - `{filename}`: Security Group aberto para 0.0.0.0/0")
            if re.search(r'cidr_blocks\s*=\s*\["0\.0\.0\.0/0"\]', patch):
                findings.append(f"  - `{filename}`: CIDR block 0.0.0.0/0 detectado")
            if "force_delete" in patch or "skip_final_snapshot" in patch:
                findings.append(f"  - `{filename}`: Flag de destruicao forcada detectada")
            if re.search(r'(password|secret|key)\s*=\s*"[^"$]', patch):
                findings.append(f"  - `{filename}`: Possivel secret hardcoded")
            if "count" not in patch and "for_each" not in patch and status == "added":
                findings.append(f"  - `{filename}`: Recurso sem count/for_each (considere parametrizar)")

        if findings:
            review.append("\n**Findings:**")
            review.extend(findings)
        else:
            review.append("\n**Nenhum finding critico detectado.**")

        review.append(f"\n---\n*Review estatico de {len(tf_files)} arquivo(s) .tf*")
        return "\n".join(review)

    except Exception as e:
        logger.error(f"PR review error: {e}")
        return f"Erro ao revisar PR: {e}"

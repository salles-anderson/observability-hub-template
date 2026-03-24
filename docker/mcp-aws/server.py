"""
MCP Server — AWS Infrastructure + FinOps + Security (AG-5)

Exposes AWS APIs as MCP tools for infrastructure monitoring, cost analysis,
and security posture. Supports cross-account access via STS AssumeRole.

Hub Account: YOUR_HUB_ACCOUNT_ID (default)
Spoke Accounts: Dev (YOUR_DEV_ACCOUNT_ID), Prod (YOUR_PRD_ACCOUNT_ID), Capital, Kong, etc.
Transport: SSE on port 8001
"""

import json
import os
import logging
from datetime import datetime, timedelta, timezone

import boto3
from mcp.server.fastmcp import FastMCP

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
logger = logging.getLogger("mcp-aws")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
DEFAULT_REGION = os.environ.get("AWS_REGION", "us-east-1")
SPOKE_ROLE_NAME = os.environ.get("SPOKE_ROLE_NAME", "teck-obs-hub-spoke-role")
CROSS_ACCOUNT_EXTERNAL_ID = os.environ.get("CROSS_ACCOUNT_EXTERNAL_ID", "")

SPOKE_ACCOUNTS = json.loads(os.environ.get("SPOKE_ACCOUNT_IDS", "{}"))

ACCOUNT_NAMES = {
    "YOUR_HUB_ACCOUNT_ID": "YOUR_ORG-Observability (Hub)",
    "YOUR_DEV_ACCOUNT_ID": "YOUR_ORG-Dev",
    "YOUR_PRD_ACCOUNT_ID": "YOUR_ORG-Prod",
    "YOUR_CAPITAL_ACCOUNT_ID": "YOUR_ORG-Capital",
    "YOUR_INFRA_ACCOUNT_ID": "YOUR_ORG-Infra (Kong)",
    "YOUR_HML_ACCOUNT_ID": "YOUR_ORG-Homolog",
    "131602690665": "YOUR_ORG-HubDigital",
    "195835301200": "YOUR_ORG-Admin",
    "YOUR_AKRK_ACCOUNT_ID": "AKRK-Dev",
    "381491855323": "ABC-Card",
    "823557601977": "CloudTrail",
}

# ---------------------------------------------------------------------------
# Cross-account STS
# ---------------------------------------------------------------------------
_sts_client = None


def _get_sts():
    global _sts_client
    if _sts_client is None:
        _sts_client = boto3.client("sts", region_name=DEFAULT_REGION)
    return _sts_client


def _get_client(service: str, account_id: str = ""):
    """Get boto3 client, optionally assuming role in spoke account."""
    if not account_id or account_id == "YOUR_HUB_ACCOUNT_ID":
        return boto3.client(service, region_name=DEFAULT_REGION)

    sts = _get_sts()
    role_arn = f"arn:aws:iam::{account_id}:role/{SPOKE_ROLE_NAME}"

    kwargs = {"RoleArn": role_arn, "RoleSessionName": "mcp-aws-agent"}
    if CROSS_ACCOUNT_EXTERNAL_ID:
        kwargs["ExternalId"] = CROSS_ACCOUNT_EXTERNAL_ID

    creds = sts.assume_role(**kwargs)["Credentials"]
    return boto3.client(
        service,
        region_name=DEFAULT_REGION,
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )


def _account_name(account_id: str) -> str:
    return ACCOUNT_NAMES.get(account_id, account_id)


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------
mcp = FastMCP("AWS Infrastructure")


# --- Infrastructure Tools ---

@mcp.tool()
async def aws_list_ecs_services(cluster: str = "cluster-prod", account_id: str = "") -> str:
    """List ECS services with desired/running/pending counts.

    Args:
        cluster: ECS cluster name (default "cluster-prod")
        account_id: AWS account ID (default: Hub YOUR_HUB_ACCOUNT_ID). Use "YOUR_DEV_ACCOUNT_ID" for Dev.
    """
    try:
        ecs = _get_client("ecs", account_id)
        services_arns = ecs.list_services(cluster=cluster)["serviceArns"]

        if not services_arns:
            return f"No services in cluster `{cluster}` ({_account_name(account_id)})"

        services = ecs.describe_services(cluster=cluster, services=services_arns)["services"]

        lines = [f"## ECS Services — {cluster} ({_account_name(account_id)})\n"]
        lines.append("| Service | Desired | Running | Pending | Status |")
        lines.append("|---------|---------|---------|---------|--------|")

        for s in sorted(services, key=lambda x: x["serviceName"]):
            name = s["serviceName"]
            desired = s["desiredCount"]
            running = s["runningCount"]
            pending = s["pendingCount"]
            status = s["status"]
            health = "✅" if running == desired else "⚠️"
            lines.append(f"| {name} | {desired} | {running} | {pending} | {health} {status} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error listing ECS services: {e}"


@mcp.tool()
async def aws_rds_status(account_id: str = "") -> str:
    """Get status of all RDS instances and Aurora clusters.

    Args:
        account_id: AWS account ID (default: Hub)
    """
    try:
        rds = _get_client("rds", account_id)

        # Instances
        instances = rds.describe_db_instances()["DBInstances"]
        # Clusters
        clusters = rds.describe_db_clusters().get("DBClusters", [])

        lines = [f"## RDS Status ({_account_name(account_id)})\n"]

        if clusters:
            lines.append("### Aurora Clusters")
            lines.append("| Cluster | Engine | Port | Status | Endpoint |")
            lines.append("|---------|--------|------|--------|----------|")
            for c in clusters:
                lines.append(
                    f"| {c['DBClusterIdentifier']} | {c['Engine']} {c.get('EngineVersion','')} | "
                    f"{c['Port']} | {c['Status']} | {c['Endpoint'][:50]} |"
                )

        if instances:
            lines.append("\n### Instances")
            lines.append("| Instance | Engine | Class | Storage | Multi-AZ | Status |")
            lines.append("|----------|--------|-------|---------|----------|--------|")
            for i in instances:
                lines.append(
                    f"| {i['DBInstanceIdentifier']} | {i['Engine']} {i.get('EngineVersion','')} | "
                    f"{i['DBInstanceClass']} | {i.get('AllocatedStorage',0)}GB | "
                    f"{'Yes' if i.get('MultiAZ') else 'No'} | {i['DBInstanceStatus']} |"
                )

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting RDS status: {e}"


@mcp.tool()
async def aws_elasticache_status(account_id: str = "") -> str:
    """Get status of ElastiCache Redis/Memcached clusters.

    Args:
        account_id: AWS account ID
    """
    try:
        ec = _get_client("elasticache", account_id)
        clusters = ec.describe_cache_clusters(ShowCacheNodeInfo=True)["CacheClusters"]

        if not clusters:
            return f"No ElastiCache clusters found ({_account_name(account_id)})"

        lines = [f"## ElastiCache ({_account_name(account_id)})\n"]
        lines.append("| Cluster | Engine | Node Type | Nodes | Status |")
        lines.append("|---------|--------|-----------|-------|--------|")

        for c in clusters:
            lines.append(
                f"| {c['CacheClusterId']} | {c['Engine']} {c.get('EngineVersion','')} | "
                f"{c['CacheNodeType']} | {c.get('NumCacheNodes',0)} | {c['CacheClusterStatus']} |"
            )

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting ElastiCache status: {e}"


# --- FinOps Tools ---

@mcp.tool()
async def finops_cost_current_month(account_id: str = "") -> str:
    """Get current month's AWS costs by service (Cost Explorer).

    Args:
        account_id: AWS account ID (costs are always queried from the account directly)
    """
    try:
        ce = _get_client("ce", account_id)
        now = datetime.now(timezone.utc)
        start = now.replace(day=1).strftime("%Y-%m-%d")
        end = now.strftime("%Y-%m-%d")

        resp = ce.get_cost_and_usage(
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
        )

        groups = resp["ResultsByTime"][0]["Groups"] if resp["ResultsByTime"] else []
        groups.sort(key=lambda g: float(g["Metrics"]["UnblendedCost"]["Amount"]), reverse=True)

        total = sum(float(g["Metrics"]["UnblendedCost"]["Amount"]) for g in groups)

        lines = [f"## AWS Costs — {now.strftime('%B %Y')} ({_account_name(account_id)})\n"]
        lines.append("| # | Service | Cost | % |")
        lines.append("|---|---------|------|---|")

        for i, g in enumerate(groups[:10], 1):
            service = g["Keys"][0]
            cost = float(g["Metrics"]["UnblendedCost"]["Amount"])
            pct = (cost / total * 100) if total > 0 else 0
            lines.append(f"| {i} | {service} | ${cost:.2f} | {pct:.1f}% |")

        lines.append(f"\n**Total: ${total:.2f}**")
        return "\n".join(lines)
    except Exception as e:
        return f"Error getting costs: {e}"


@mcp.tool()
async def finops_cost_forecast(account_id: str = "") -> str:
    """Get cost forecast for end of current month.

    Args:
        account_id: AWS account ID
    """
    try:
        ce = _get_client("ce", account_id)
        now = datetime.now(timezone.utc)
        start = now.strftime("%Y-%m-%d")

        # End of month
        if now.month == 12:
            end = now.replace(year=now.year + 1, month=1, day=1)
        else:
            end = now.replace(month=now.month + 1, day=1)
        end_str = end.strftime("%Y-%m-%d")

        resp = ce.get_cost_forecast(
            TimePeriod={"Start": start, "End": end_str},
            Metric="UNBLENDED_COST",
            Granularity="MONTHLY",
        )

        forecast = float(resp["Total"]["Amount"])
        return f"## Cost Forecast — {_account_name(account_id)}\n\nForecast for end of {now.strftime('%B %Y')}: **${forecast:.2f}**"
    except Exception as e:
        return f"Error getting forecast: {e}"


# --- Security Tools ---

@mcp.tool()
async def security_guardduty_findings(account_id: str = "", max_results: int = 10) -> str:
    """Get GuardDuty findings (threats, anomalies).

    Args:
        account_id: AWS account ID
        max_results: Max findings to return (default 10)
    """
    try:
        gd = _get_client("guardduty", account_id)
        detectors = gd.list_detectors()["DetectorIds"]

        if not detectors:
            return f"GuardDuty is NOT enabled in {_account_name(account_id)}"

        detector_id = detectors[0]
        findings_ids = gd.list_findings(
            DetectorId=detector_id,
            MaxResults=max_results,
            SortCriteria={"AttributeName": "severity", "OrderBy": "DESC"},
        )["FindingIds"]

        if not findings_ids:
            return f"No GuardDuty findings in {_account_name(account_id)} — all clear."

        findings = gd.get_findings(DetectorId=detector_id, FindingIds=findings_ids)["Findings"]

        lines = [f"## GuardDuty Findings ({_account_name(account_id)})\n"]
        lines.append("| Severity | Type | Title | Updated |")
        lines.append("|----------|------|-------|---------|")

        for f in findings:
            sev = f.get("Severity", 0)
            sev_label = "HIGH" if sev >= 7 else "MEDIUM" if sev >= 4 else "LOW"
            ftype = f.get("Type", "?")
            title = f.get("Title", "?")[:50]
            updated = f.get("UpdatedAt", "?")[:10]
            lines.append(f"| {sev_label} ({sev}) | {ftype} | {title} | {updated} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting GuardDuty findings: {e}"


@mcp.tool()
async def security_cloudtrail_logins(account_id: str = "", hours: int = 24) -> str:
    """Get recent console login events from CloudTrail.

    Args:
        account_id: AWS account ID
        hours: How many hours to look back (default 24)
    """
    try:
        ct = _get_client("cloudtrail", account_id)
        start = datetime.now(timezone.utc) - timedelta(hours=hours)

        events = ct.lookup_events(
            LookupAttributes=[{"AttributeKey": "EventName", "AttributeValue": "ConsoleLogin"}],
            StartTime=start,
            MaxResults=20,
        )["Events"]

        if not events:
            return f"No console logins in the last {hours}h ({_account_name(account_id)})"

        lines = [f"## Console Logins — last {hours}h ({_account_name(account_id)})\n"]
        lines.append("| Time | User | Source IP | Result |")
        lines.append("|------|------|-----------|--------|")

        for e in events:
            time_str = e["EventTime"].strftime("%Y-%m-%d %H:%M")
            user = e.get("Username", "?")
            detail = json.loads(e.get("CloudTrailEvent", "{}"))
            src_ip = detail.get("sourceIPAddress", "?")
            result = detail.get("responseElements", {}).get("ConsoleLogin", "?")
            lines.append(f"| {time_str} | {user} | {src_ip} | {result} |")

        return "\n".join(lines)
    except Exception as e:
        return f"Error getting CloudTrail logins: {e}"


@mcp.tool()
async def aws_list_accounts() -> str:
    """List all known AWS accounts in the YOUR_ORG organization."""
    lines = ["## AWS Accounts\n"]
    lines.append("| Account ID | Name |")
    lines.append("|------------|------|")
    for acc_id, name in sorted(ACCOUNT_NAMES.items(), key=lambda x: x[1]):
        lines.append(f"| {acc_id} | {name} |")
    return "\n".join(lines)


if __name__ == "__main__":
    import uvicorn
    app = mcp.sse_app()
    uvicorn.run(app, host="0.0.0.0", port=8001)  # noqa: S104

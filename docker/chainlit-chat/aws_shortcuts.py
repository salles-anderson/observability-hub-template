"""
AWS shortcuts — Level 1 cache for infrastructure queries.

Bypasses LLM for common AWS questions using boto3 directly:
1. Pattern-match user question (regex, Portuguese/English)
2. Query AWS API via boto3 + IAM Task Role (~1-3s)
3. Format response with markdown templates

Result: ~2-3s response vs ~10-12s with LLM.
"""

import asyncio
import json
import re
import os
import time
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

import boto3

logger = logging.getLogger("aws-shortcuts")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
ECS_CLUSTER = os.environ.get("ECS_CLUSTER", "cluster-prod")
ACCOUNT_ID = os.environ.get("AWS_ACCOUNT_ID", "YOUR_HUB_ACCOUNT_ID")

# Cross-account config (injected by Terraform)
SPOKE_ROLE_NAME = os.environ.get("SPOKE_ROLE_NAME", "obs-hub-readonly")
CROSS_ACCOUNT_EXTERNAL_ID = os.environ.get(
    "CROSS_ACCOUNT_EXTERNAL_ID", "teck-observability-hub-2024"
)

# ---------------------------------------------------------------------------
# boto3 lazy clients (sync — wrapped with asyncio.to_thread)
# ---------------------------------------------------------------------------
_clients: dict = {}
_assumed_sessions: dict[str, boto3.Session] = {}

# Context variable for cross-account — set by dispatcher, read by _call()
import contextvars
_current_account_id: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "_current_account_id", default=None
)


def set_account_context(account_id: str | None):
    """Set cross-account context for current async task.

    Called by tools_registry dispatcher before invoking handlers.
    All _call() invocations within the handler will use this account.
    """
    _current_account_id.set(account_id)


def _get_spoke_session(account_id: str) -> boto3.Session:
    """AssumeRole in spoke account, cached per account_id."""
    if account_id in _assumed_sessions:
        return _assumed_sessions[account_id]

    sts = boto3.client("sts", region_name=AWS_REGION)
    role_arn = f"arn:aws:iam::{account_id}:role/{SPOKE_ROLE_NAME}"
    logger.info(f"AssumeRole: {role_arn}")
    creds = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName=f"obs-hub-{account_id[-4:]}",
        ExternalId=CROSS_ACCOUNT_EXTERNAL_ID,
    )["Credentials"]

    session = boto3.Session(
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )
    _assumed_sessions[account_id] = session
    return session


def _client(service: str, account_id: str | None = None):
    """Get boto3 client, optionally for a spoke account via AssumeRole."""
    effective = account_id or ACCOUNT_ID
    cache_key = f"{effective}:{service}"

    if cache_key not in _clients:
        if effective == ACCOUNT_ID or not account_id:
            _clients[cache_key] = boto3.client(service, region_name=AWS_REGION)
        else:
            session = _get_spoke_session(effective)
            _clients[cache_key] = session.client(service, region_name=AWS_REGION)

    return _clients[cache_key]


async def _call(service: str, method: str, account_id: str | None = None, **kwargs):
    """Call boto3 method in thread pool. Supports cross-account via account_id.

    account_id resolution order:
    1. Explicit parameter (highest priority)
    2. Context variable _current_account_id (set by dispatcher)
    3. Default Hub account (ACCOUNT_ID)
    """
    effective = account_id or _current_account_id.get()
    client = _client(service, account_id=effective)
    func = getattr(client, method)
    return await asyncio.to_thread(func, **kwargs)


# ---------------------------------------------------------------------------
# Response formatting
# ---------------------------------------------------------------------------
def _fmt_aws(
    title: str,
    headers: list[str],
    rows: list[list[str]],
    interpretation: str,
    details: str = "",
) -> str:
    """Build consistent markdown response for AWS queries."""
    hdr = "| " + " | ".join(headers) + " |"
    sep = "|" + "|".join("-------" for _ in headers) + "|"
    body = "\n".join("| " + " | ".join(r) + " |" for r in rows)

    parts = [f"### {title}", "", hdr, sep, body, "", interpretation]

    if details:
        parts.extend(["", f"```json\n{details}\n```"])

    return "\n".join(parts)


NO_DATA_AWS = "Sem dados disponiveis. Verifique permissoes ou regiao."


# ---------------------------------------------------------------------------
# Cluster resolver — detect which cluster user is asking about
# ---------------------------------------------------------------------------
def _resolve_cluster(question: str) -> str:
    q = question.lower()
    if any(w in q for w in ["cluster-dev", "dev", "example-api", "negocio"]):
        return "cluster-dev"
    if any(w in q for w in ["cluster-prod", "prod", "observability", "hub", "grafana", "prometheus"]):
        return ECS_CLUSTER
    return ECS_CLUSTER


# ===================================================================
# SRE HANDLERS
# ===================================================================
async def _ecs_services(**kwargs) -> Optional[str]:
    """List ECS services with status and task counts."""
    cluster = _resolve_cluster(kwargs.get("question", ""))
    try:
        svc_arns = await _call("ecs", "list_services", cluster=cluster, maxResults=50)
        arns = svc_arns.get("serviceArns", [])
        if not arns:
            return _fmt_aws(
                f"Servicos ECS — {cluster}", ["Info"], [["Nenhum servico encontrado"]],
                f"Cluster `{cluster}` sem servicos ativos.", "",
            )

        # API limit: max 10 services per describe_services call
        services = []
        for i in range(0, len(arns), 10):
            batch = arns[i:i + 10]
            desc = await _call("ecs", "describe_services", cluster=cluster, services=batch)
            services.extend(desc.get("services", []))

        rows = []
        for svc in sorted(services, key=lambda s: s.get("serviceName", "")):
            name = svc.get("serviceName", "?")
            status = svc.get("status", "?")
            desired = svc.get("desiredCount", 0)
            running = svc.get("runningCount", 0)
            pending = svc.get("pendingCount", 0)
            health = "OK" if running == desired else "**ATENCAO**"
            rows.append([name, status, str(desired), str(running), str(pending), health])

        total = len(services)
        healthy = sum(1 for s in services if s.get("runningCount", 0) == s.get("desiredCount", 0))
        interp = f"{healthy}/{total} servicos saudaveis." if healthy == total else f"**{total - healthy} servico(s) com tasks faltando!**"

        return _fmt_aws(
            f"Servicos ECS — {cluster}",
            ["Servico", "Status", "Desired", "Running", "Pending", "Saude"],
            rows, interp,
        )
    except Exception as e:
        logger.error(f"ECS services error: {e}")
        return _fmt_aws(
            "Erro — Servicos ECS", ["Detalhe"], [[str(e)[:200]]],
            f"Falha ao consultar cluster `{cluster}` na regiao `{AWS_REGION}`.",
            "Verifique se o cluster existe e se a IAM Role tem permissao.",
        )


async def _ecs_tasks(**kwargs) -> Optional[str]:
    """List tasks for a service with IPs and status."""
    cluster = _resolve_cluster(kwargs.get("question", ""))
    try:
        svc_arns = await _call("ecs", "list_services", cluster=cluster, maxResults=50)
        arns = svc_arns.get("serviceArns", [])
        if not arns:
            return None

        task_arns = await _call("ecs", "list_tasks", cluster=cluster, maxResults=50)
        tarns = task_arns.get("taskArns", [])
        if not tarns:
            return _fmt_aws(f"Tasks ECS — {cluster}", ["Info"], [["Nenhuma task rodando"]], "Cluster sem tasks ativas.", "")

        desc = await _call("ecs", "describe_tasks", cluster=cluster, tasks=tarns[:20])
        tasks = desc.get("tasks", [])

        rows = []
        for t in tasks:
            td = t.get("taskDefinitionArn", "").split("/")[-1]
            status = t.get("lastStatus", "?")
            health = t.get("healthStatus", "—")
            cpu = t.get("cpu", "?")
            mem = t.get("memory", "?")
            started = t.get("startedAt")
            uptime = ""
            if started:
                delta = datetime.now(timezone.utc) - started
                hours = int(delta.total_seconds() / 3600)
                uptime = f"{hours}h" if hours > 0 else f"{int(delta.total_seconds() / 60)}min"
            rows.append([td, status, health, f"{cpu}/{mem}", uptime])

        return _fmt_aws(
            f"Tasks ECS — {cluster}",
            ["Task Definition", "Status", "Health", "CPU/Mem", "Uptime"],
            rows, f"{len(tasks)} task(s) rodando.",
        )
    except Exception as e:
        logger.error(f"ECS tasks error: {e}")
        return None


async def _rds_status(**kwargs) -> Optional[str]:
    """RDS instances status, storage, engine."""
    try:
        resp = await _call("rds", "describe_db_instances")
        instances = resp.get("DBInstances", [])
        if not instances:
            return _fmt_aws("RDS Instances", ["Info"], [["Nenhuma instancia RDS encontrada"]], "Sem RDS nesta conta/regiao.", "")

        rows = []
        for db in instances:
            name = db.get("DBInstanceIdentifier", "?")
            status = db.get("DBInstanceStatus", "?")
            engine = f"{db.get('Engine', '?')} {db.get('EngineVersion', '')}"
            cls = db.get("DBInstanceClass", "?")
            storage = f"{db.get('AllocatedStorage', '?')} GB"
            multi_az = "Sim" if db.get("MultiAZ") else "Nao"
            health = "OK" if status == "available" else f"**{status.upper()}**"
            rows.append([name, health, engine, cls, storage, multi_az])

        return _fmt_aws(
            "RDS Instances",
            ["Instancia", "Status", "Engine", "Classe", "Storage", "Multi-AZ"],
            rows, f"{len(instances)} instancia(s) RDS encontrada(s).",
        )
    except Exception as e:
        logger.error(f"RDS status error: {e}")
        return None


async def _elasticache_status(**kwargs) -> Optional[str]:
    """ElastiCache clusters status."""
    try:
        resp = await _call("elasticache", "describe_cache_clusters", ShowCacheNodeInfo=True)
        clusters = resp.get("CacheClusters", [])
        if not clusters:
            return _fmt_aws("ElastiCache", ["Info"], [["Nenhum cluster encontrado"]], "Sem ElastiCache nesta conta.", "")

        rows = []
        for c in clusters:
            name = c.get("CacheClusterId", "?")
            status = c.get("CacheClusterStatus", "?")
            engine = f"{c.get('Engine', '?')} {c.get('EngineVersion', '')}"
            node_type = c.get("CacheNodeType", "?")
            nodes = str(c.get("NumCacheNodes", 0))
            health = "OK" if status == "available" else f"**{status.upper()}**"
            rows.append([name, health, engine, node_type, nodes])

        return _fmt_aws(
            "ElastiCache Clusters",
            ["Cluster", "Status", "Engine", "Node Type", "Nodes"],
            rows, f"{len(clusters)} cluster(s) encontrado(s).",
        )
    except Exception as e:
        logger.error(f"ElastiCache error: {e}")
        return None


async def _alarms_active(**kwargs) -> Optional[str]:
    """CloudWatch alarms in ALARM state."""
    try:
        resp = await _call("cloudwatch", "describe_alarms", StateValue="ALARM", MaxRecords=20)
        alarms = resp.get("MetricAlarms", []) + resp.get("CompositeAlarms", [])
        if not alarms:
            return _fmt_aws("CloudWatch Alarms", ["Info"], [["Nenhum alarme ativo"]], "Todos os alarmes OK — nenhum em estado ALARM.", "")

        rows = []
        for a in alarms:
            name = a.get("AlarmName", "?")[:40]
            metric = a.get("MetricName", a.get("AlarmRule", "composite"))[:30]
            ns = a.get("Namespace", "—")[:25]
            updated = a.get("StateUpdatedTimestamp", "")
            ts = str(updated)[:19] if updated else "—"
            rows.append([name, metric, ns, ts])

        return _fmt_aws(
            f"CloudWatch Alarms Ativos ({len(alarms)})",
            ["Alarm", "Metrica", "Namespace", "Desde"],
            rows, f"**{len(alarms)} alarme(s) em estado ALARM!** Verificar imediatamente.",
        )
    except Exception as e:
        logger.error(f"Alarms error: {e}")
        return None


async def _ecs_deployments(**kwargs) -> Optional[str]:
    """Recent ECS deployments for all services."""
    cluster = _resolve_cluster(kwargs.get("question", ""))
    try:
        svc_arns = await _call("ecs", "list_services", cluster=cluster, maxResults=50)
        arns = svc_arns.get("serviceArns", [])
        if not arns:
            return None

        # API limit: max 10 services per describe_services call
        all_services = []
        for i in range(0, len(arns), 10):
            batch = arns[i:i + 10]
            desc = await _call("ecs", "describe_services", cluster=cluster, services=batch)
            all_services.extend(desc.get("services", []))
        rows = []
        for svc in all_services:
            name = svc.get("serviceName", "?")
            for d in svc.get("deployments", []):
                status = d.get("rolloutState", d.get("status", "?"))
                desired = d.get("desiredCount", 0)
                running = d.get("runningCount", 0)
                created = d.get("createdAt")
                ts = str(created)[:19] if created else "—"
                td = d.get("taskDefinition", "").split("/")[-1].split(":")[-1]
                rows.append([name, f"rev:{td}", status, f"{running}/{desired}", ts])

        if not rows:
            return None

        return _fmt_aws(
            f"Deployments ECS — {cluster}",
            ["Servico", "Revision", "Status", "Running/Desired", "Criado"],
            rows, f"{len(rows)} deployment(s) encontrado(s).",
        )
    except Exception as e:
        logger.error(f"ECS deployments error: {e}")
        return None


# ===================================================================
# DEVOPS HANDLERS
# ===================================================================
async def _ecr_images(**kwargs) -> Optional[str]:
    """Latest ECR images for obs-hub repos."""
    try:
        repos = await _call("ecr", "describe_repositories", maxResults=50)
        repo_list = repos.get("repositories", [])
        if not repo_list:
            return None

        rows = []
        for repo in sorted(repo_list, key=lambda r: r.get("repositoryName", "")):
            name = repo.get("repositoryName", "?")
            try:
                images = await _call(
                    "ecr", "describe_images",
                    repositoryName=name,
                    filter={"tagStatus": "TAGGED"},
                    maxResults=3,
                )
                for img in images.get("imageDetails", [])[:1]:
                    tags = ", ".join(img.get("imageTags", ["untagged"])[:2])
                    size_mb = round(img.get("imageSizeInBytes", 0) / (1024 * 1024), 1)
                    pushed = img.get("imagePushedAt")
                    ts = str(pushed)[:19] if pushed else "—"
                    scan = img.get("imageScanStatus", {}).get("status", "—")
                    rows.append([name, tags, f"{size_mb} MB", ts, scan])
            except Exception:
                rows.append([name, "—", "—", "—", "—"])

        return _fmt_aws(
            "ECR Images (ultima tag)",
            ["Repositorio", "Tag", "Tamanho", "Push", "Scan"],
            rows, f"{len(rows)} repositorio(s) encontrado(s).",
        )
    except Exception as e:
        logger.error(f"ECR images error: {e}")
        return None


async def _ecs_events(**kwargs) -> Optional[str]:
    """Recent ECS service events."""
    cluster = _resolve_cluster(kwargs.get("question", ""))
    try:
        svc_arns = await _call("ecs", "list_services", cluster=cluster, maxResults=50)
        arns = svc_arns.get("serviceArns", [])
        if not arns:
            return None

        # API limit: max 10 services per describe_services call
        all_services = []
        for i in range(0, len(arns), 10):
            batch = arns[i:i + 10]
            desc = await _call("ecs", "describe_services", cluster=cluster, services=batch)
            all_services.extend(desc.get("services", []))
        rows = []
        for svc in all_services:
            name = svc.get("serviceName", "?")
            for ev in svc.get("events", [])[:3]:
                msg = ev.get("message", "")[:100]
                ts = str(ev.get("createdAt", ""))[:19]
                rows.append([name, ts, msg])

        if not rows:
            return None

        return _fmt_aws(
            f"Eventos ECS Recentes — {cluster}",
            ["Servico", "Timestamp", "Evento"],
            rows[:15], f"{len(rows)} evento(s) recente(s).",
        )
    except Exception as e:
        logger.error(f"ECS events error: {e}")
        return None


async def _cloudtrail_recent(**kwargs) -> Optional[str]:
    """Last 20 management events from CloudTrail."""
    try:
        resp = await _call(
            "cloudtrail", "lookup_events",
            MaxResults=20,
        )
        events = resp.get("Events", [])
        if not events:
            return _fmt_aws("CloudTrail", ["Info"], [["Nenhum evento recente"]], "Sem eventos no CloudTrail.", "")

        rows = []
        for ev in events:
            ts = str(ev.get("EventTime", ""))[:19]
            name = ev.get("EventName", "?")
            user = ev.get("Username", "?")[:25]
            src = ev.get("EventSource", "?").replace(".amazonaws.com", "")
            rows.append([ts, name, user, src])

        return _fmt_aws(
            "CloudTrail — Eventos Recentes",
            ["Timestamp", "Evento", "Usuario", "Servico"],
            rows, f"Ultimos {len(events)} eventos de management.",
        )
    except Exception as e:
        logger.error(f"CloudTrail recent error: {e}")
        return None


# ===================================================================
# PLATFORM HANDLERS
# ===================================================================
async def _vpc_overview(**kwargs) -> Optional[str]:
    """VPC overview with CIDRs and subnets."""
    try:
        vpcs = await _call("ec2", "describe_vpcs")
        vpc_list = vpcs.get("Vpcs", [])
        if not vpc_list:
            return None

        rows = []
        for vpc in vpc_list:
            vpc_id = vpc.get("VpcId", "?")
            cidr = vpc.get("CidrBlock", "?")
            state = vpc.get("State", "?")
            name = "—"
            for tag in vpc.get("Tags", []):
                if tag.get("Key") == "Name":
                    name = tag.get("Value", "—")[:30]
                    break
            is_default = "Sim" if vpc.get("IsDefault") else "Nao"
            rows.append([name, vpc_id, cidr, state, is_default])

        return _fmt_aws(
            "VPCs",
            ["Nome", "VPC ID", "CIDR", "Estado", "Default"],
            rows, f"{len(vpc_list)} VPC(s) encontrada(s).",
        )
    except Exception as e:
        logger.error(f"VPC overview error: {e}")
        return None


async def _security_groups(**kwargs) -> Optional[str]:
    """Security groups summary."""
    try:
        resp = await _call("ec2", "describe_security_groups")
        sgs = resp.get("SecurityGroups", [])
        if not sgs:
            return None

        rows = []
        for sg in sorted(sgs, key=lambda s: s.get("GroupName", "")):
            name = sg.get("GroupName", "?")[:30]
            sg_id = sg.get("GroupId", "?")
            inbound = len(sg.get("IpPermissions", []))
            outbound = len(sg.get("IpPermissionsEgress", []))
            vpc = sg.get("VpcId", "?")[-8:]
            desc = sg.get("Description", "—")[:30]
            rows.append([name, sg_id, str(inbound), str(outbound), vpc, desc])

        return _fmt_aws(
            "Security Groups",
            ["Nome", "SG ID", "Inbound", "Outbound", "VPC", "Descricao"],
            rows[:20], f"{len(sgs)} security group(s).",
        )
    except Exception as e:
        logger.error(f"Security groups error: {e}")
        return None


async def _nat_gateways(**kwargs) -> Optional[str]:
    """NAT Gateways status."""
    try:
        resp = await _call("ec2", "describe_nat_gateways")
        nats = resp.get("NatGateways", [])
        if not nats:
            return _fmt_aws("NAT Gateways", ["Info"], [["Nenhum NAT Gateway encontrado"]], "Sem NAT Gateways nesta conta.", "")

        rows = []
        for nat in nats:
            nat_id = nat.get("NatGatewayId", "?")
            state = nat.get("State", "?")
            subnet = nat.get("SubnetId", "?")[-8:]
            eips = [a.get("PublicIp", "—") for a in nat.get("NatGatewayAddresses", [])]
            eip = ", ".join(eips) if eips else "—"
            name = "—"
            for tag in nat.get("Tags", []):
                if tag.get("Key") == "Name":
                    name = tag.get("Value", "—")[:25]
                    break
            health = "OK" if state == "available" else f"**{state.upper()}**"
            rows.append([name, nat_id, health, subnet, eip])

        return _fmt_aws(
            "NAT Gateways",
            ["Nome", "ID", "Status", "Subnet", "EIP"],
            rows, f"{len(nats)} NAT Gateway(s).",
        )
    except Exception as e:
        logger.error(f"NAT gateways error: {e}")
        return None


async def _cloudmap_services(**kwargs) -> Optional[str]:
    """Cloud Map namespaces and services."""
    try:
        ns_resp = await _call("servicediscovery", "list_namespaces")
        namespaces = ns_resp.get("Namespaces", [])
        if not namespaces:
            return _fmt_aws("Cloud Map", ["Info"], [["Nenhum namespace encontrado"]], "Sem Cloud Map nesta conta.", "")

        rows = []
        for ns in namespaces:
            ns_name = ns.get("Name", "?")
            ns_type = ns.get("Type", "?")
            ns_id = ns.get("Id", "?")
            try:
                svc_resp = await _call("servicediscovery", "list_services",
                    Filters=[{"Name": "NAMESPACE_ID", "Values": [ns_id], "Condition": "EQ"}])
                svcs = svc_resp.get("Services", [])
                for svc in svcs:
                    svc_name = svc.get("Name", "?")
                    instances = svc.get("InstanceCount", 0)
                    rows.append([ns_name, ns_type, svc_name, str(instances)])
            except Exception:
                rows.append([ns_name, ns_type, "—", "—"])

        return _fmt_aws(
            "Cloud Map — Service Discovery",
            ["Namespace", "Tipo", "Servico", "Instancias"],
            rows, f"{len(rows)} servico(s) registrado(s).",
        )
    except Exception as e:
        logger.error(f"Cloud Map error: {e}")
        return None


async def _route53_overview(**kwargs) -> Optional[str]:
    """Route53 hosted zones."""
    try:
        resp = await _call("route53", "list_hosted_zones")
        zones = resp.get("HostedZones", [])
        if not zones:
            return None

        rows = []
        for z in zones:
            name = z.get("Name", "?")
            zone_id = z.get("Id", "?").split("/")[-1]
            records = z.get("ResourceRecordSetCount", 0)
            private = "Sim" if z.get("Config", {}).get("PrivateZone") else "Nao"
            rows.append([name, zone_id, str(records), private])

        return _fmt_aws(
            "Route53 — Hosted Zones",
            ["Dominio", "Zone ID", "Records", "Privada"],
            rows, f"{len(zones)} hosted zone(s).",
        )
    except Exception as e:
        logger.error(f"Route53 error: {e}")
        return None


# ===================================================================
# FINOPS HANDLERS
# ===================================================================
async def _cost_current_month(**kwargs) -> Optional[str]:
    """Current month AWS cost."""
    try:
        now = datetime.now(timezone.utc)
        start = now.replace(day=1).strftime("%Y-%m-%d")
        # End is exclusive in Cost Explorer API — use tomorrow to include today
        end = (now + timedelta(days=1)).strftime("%Y-%m-%d")

        resp = await _call(
            "ce", "get_cost_and_usage",
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
        )
        results = resp.get("ResultsByTime", [])
        if not results:
            return None

        total = float(results[0].get("Total", {}).get("UnblendedCost", {}).get("Amount", 0))
        unit = results[0].get("Total", {}).get("UnblendedCost", {}).get("Unit", "USD")

        return _fmt_aws(
            f"Custo AWS — {now.strftime('%B %Y')}",
            ["Periodo", "Custo"],
            [[f"01 a {now.strftime('%d/%m/%Y')}", f"**${total:.2f} {unit}**"]],
            f"Custo acumulado ate hoje: **${total:.2f}**.",
        )
    except Exception as e:
        logger.error(f"Cost current month error: {e}")
        return None


async def _cost_forecast(**kwargs) -> Optional[str]:
    """Cost forecast for end of month."""
    try:
        now = datetime.now(timezone.utc)
        start = now.strftime("%Y-%m-%d")
        if now.month == 12:
            end = now.replace(year=now.year + 1, month=1, day=1).strftime("%Y-%m-%d")
        else:
            end = now.replace(month=now.month + 1, day=1).strftime("%Y-%m-%d")

        resp = await _call(
            "ce", "get_cost_forecast",
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metric="UNBLENDED_COST",
        )
        total = float(resp.get("Total", {}).get("Amount", 0))
        mean = float(resp.get("ForecastResultsByTime", [{}])[0].get("MeanValue", 0)) if resp.get("ForecastResultsByTime") else total

        return _fmt_aws(
            f"Forecast AWS — {now.strftime('%B %Y')}",
            ["Metrica", "Valor"],
            [
                ["Previsao total", f"**${total:.2f} USD**"],
                ["Media estimada", f"${mean:.2f} USD"],
            ],
            f"Forecast para fim do mes: **${total:.2f} USD**.",
        )
    except Exception as e:
        logger.error(f"Cost forecast error: {e}")
        return None


async def _cost_by_service(**kwargs) -> Optional[str]:
    """Top 10 AWS services by cost this month."""
    try:
        now = datetime.now(timezone.utc)
        start = now.replace(day=1).strftime("%Y-%m-%d")
        # End is exclusive in Cost Explorer API — use tomorrow to include today
        end = (now + timedelta(days=1)).strftime("%Y-%m-%d")

        resp = await _call(
            "ce", "get_cost_and_usage",
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
            Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
        )
        results = resp.get("ResultsByTime", [])
        if not results:
            return None

        groups = results[0].get("Groups", [])
        services = []
        for g in groups:
            svc_name = g.get("Keys", ["?"])[0]
            cost = float(g.get("Metrics", {}).get("UnblendedCost", {}).get("Amount", 0))
            if cost > 0.01:
                services.append((svc_name, cost))

        services.sort(key=lambda x: -x[1])
        total = sum(c for _, c in services)

        rows = []
        for svc_name, cost in services[:10]:
            pct = (cost / total * 100) if total > 0 else 0
            rows.append([svc_name[:40], f"${cost:.2f}", f"{pct:.1f}%"])

        return _fmt_aws(
            f"Top Servicos por Custo — {now.strftime('%B %Y')}",
            ["Servico", "Custo", "% Total"],
            rows, f"Total: **${total:.2f} USD** | Top 10 servicos mostrados.",
        )
    except Exception as e:
        logger.error(f"Cost by service error: {e}")
        return None


async def _cost_daily_trend(**kwargs) -> Optional[str]:
    """Daily cost trend for last 7 days."""
    try:
        now = datetime.now(timezone.utc)
        start = (now - timedelta(days=7)).strftime("%Y-%m-%d")
        # End is exclusive in Cost Explorer API — use tomorrow to include today
        end = (now + timedelta(days=1)).strftime("%Y-%m-%d")

        resp = await _call(
            "ce", "get_cost_and_usage",
            TimePeriod={"Start": start, "End": end},
            Granularity="DAILY",
            Metrics=["UnblendedCost"],
        )
        results = resp.get("ResultsByTime", [])
        if not results:
            return None

        rows = []
        total = 0
        for r in results:
            date = r.get("TimePeriod", {}).get("Start", "?")
            cost = float(r.get("Total", {}).get("UnblendedCost", {}).get("Amount", 0))
            total += cost
            rows.append([date, f"${cost:.2f}"])

        avg = total / len(results) if results else 0

        return _fmt_aws(
            "Custo Diario — Ultimos 7 dias",
            ["Data", "Custo"],
            rows, f"Media diaria: **${avg:.2f} USD** | Total 7d: **${total:.2f} USD**.",
        )
    except Exception as e:
        logger.error(f"Cost daily trend error: {e}")
        return None


# ===================================================================
# FINOPS ADVANCED HANDLERS
# ===================================================================
async def _savings_plan_coverage(**kwargs) -> Optional[str]:
    """Savings Plans coverage for the last 30 days."""
    try:
        now = datetime.now(timezone.utc)
        start = (now - timedelta(days=30)).strftime("%Y-%m-%d")
        end = now.strftime("%Y-%m-%d")

        resp = await _call(
            "ce", "get_savings_plans_coverage",
            TimePeriod={"Start": start, "End": end},
            Granularity="MONTHLY",
        )
        results = resp.get("SavingsPlansCoverages", [])
        if not results:
            return _fmt_aws(
                "Savings Plans Coverage", ["Info"],
                [["Sem dados de cobertura"]], "Nenhum Savings Plan ativo.", "",
            )

        cov = results[0].get("Coverage", {})
        spend_pct = cov.get("SpendCoveredBySavingsPlans", "0")
        on_demand = cov.get("OnDemandCost", "0")
        sp_spend = cov.get("SpendCoveredBySavingsPlans", "0")
        total = cov.get("TotalCost", "0")

        attrs = results[0].get("Attributes", {})
        rows = [
            ["Cobertura SP", f"{float(cov.get('CoveragePercentage', '0')):.1f}%"],
            ["Custo coberto por SP", f"${float(sp_spend):.2f}"],
            ["Custo On-Demand", f"${float(on_demand):.2f}"],
            ["Custo Total", f"${float(total):.2f}"],
        ]

        coverage_pct = float(cov.get("CoveragePercentage", "0"))
        tip = ""
        if coverage_pct < 60:
            tip = "Cobertura baixa (<60%). Considere adquirir Compute Savings Plan."
        elif coverage_pct < 80:
            tip = "Cobertura moderada. Avalie aumentar o commitment para reduzir On-Demand."
        else:
            tip = "Boa cobertura de Savings Plans!"

        return _fmt_aws(
            "Savings Plans — Cobertura (30 dias)",
            ["Metrica", "Valor"], rows, tip,
        )
    except Exception as e:
        logger.error(f"Savings plan coverage error: {e}")
        return None


async def _ri_recommendations(**kwargs) -> Optional[str]:
    """Reserved Instance purchase recommendations."""
    try:
        resp = await _call(
            "ce", "get_reservation_purchase_recommendation",
            Service="Amazon Elastic Compute Cloud - Compute",
            LookbackPeriodInDays="SIXTY_DAYS",
            TermInYears="ONE_YEAR",
            PaymentOption="NO_UPFRONT",
        )
        recs = resp.get("Recommendations", [])
        if not recs:
            return _fmt_aws(
                "RI Recommendations", ["Info"],
                [["Sem recomendacoes de RI para EC2"]],
                "Nenhuma oportunidade de Reserved Instance identificada.", "",
            )

        rows = []
        total_savings = 0
        for rec in recs:
            details = rec.get("RecommendationDetails", [])
            for d in details[:10]:
                instance = d.get("InstanceDetails", {})
                ec2 = instance.get("EC2InstanceDetails", {})
                family = ec2.get("InstanceType", "?")
                region = ec2.get("Region", "?")
                est_savings = float(d.get("EstimatedMonthlySavingsAmount", "0"))
                est_cost = float(d.get("EstimatedMonthlyOnDemandCost", "0"))
                total_savings += est_savings
                rows.append([family, region, f"${est_cost:.2f}", f"${est_savings:.2f}/mes"])

        if not rows:
            return _fmt_aws(
                "RI Recommendations", ["Info"],
                [["Sem instancias candidatas a RI"]],
                "Workloads atuais nao justificam Reserved Instances.", "",
            )

        return _fmt_aws(
            "Reserved Instance — Recomendacoes",
            ["Tipo", "Regiao", "On-Demand", "Economia Estimada"],
            rows, f"Economia total estimada: **${total_savings:.2f}/mes**.",
        )
    except Exception as e:
        logger.error(f"RI recommendations error: {e}")
        return None


async def _rightsizing_recommendations(**kwargs) -> Optional[str]:
    """Rightsizing recommendations from Cost Explorer."""
    try:
        resp = await _call(
            "ce", "get_rightsizing_recommendation",
            Service="AmazonEC2",
            Configuration={
                "RecommendationTarget": "SAME_INSTANCE_FAMILY",
                "BenefitsConsidered": True,
            },
        )
        recs = resp.get("RightsizingRecommendations", [])
        summary = resp.get("Summary", {})

        if not recs:
            return _fmt_aws(
                "Rightsizing Recommendations", ["Info"],
                [["Sem recomendacoes de rightsizing"]],
                "Todos os recursos estao right-sized ou sem dados suficientes.", "",
            )

        rows = []
        total_savings = float(summary.get("EstimatedTotalMonthlySavingsAmount", "0"))
        for rec in recs[:10]:
            action = rec.get("RightsizingType", "?")
            current = rec.get("CurrentInstance", {})
            name = current.get("ResourceId", "?")[:20]
            instance_type = current.get("InstanceType", "?") if "InstanceType" in current else "?"

            target = rec.get("ModifyRecommendationDetail", {})
            targets = target.get("TargetInstances", [])
            new_type = targets[0].get("ResourceDetails", {}).get("EC2ResourceDetails", {}).get("InstanceType", "?") if targets else "—"
            savings = float(targets[0].get("EstimatedMonthlySavings", "0")) if targets else 0

            rows.append([name, action, instance_type, new_type, f"${savings:.2f}/mes"])

        return _fmt_aws(
            "Rightsizing — Recomendacoes",
            ["Recurso", "Acao", "Atual", "Sugerido", "Economia"],
            rows,
            f"Total de recomendacoes: **{len(recs)}** | "
            f"Economia estimada: **${total_savings:.2f}/mes**.",
        )
    except Exception as e:
        logger.error(f"Rightsizing error: {e}")
        return None


async def _cost_anomalies(**kwargs) -> Optional[str]:
    """Cost anomalies from AWS Cost Anomaly Detection."""
    try:
        now = datetime.now(timezone.utc)
        start = (now - timedelta(days=30)).strftime("%Y-%m-%d")
        end = now.strftime("%Y-%m-%d")

        resp = await _call(
            "ce", "get_anomalies",
            DateInterval={"StartDate": start, "EndDate": end},
            MaxResults=20,
        )
        anomalies = resp.get("Anomalies", [])
        if not anomalies:
            return _fmt_aws(
                "Anomalias de Custo (30 dias)", ["Info"],
                [["Nenhuma anomalia detectada"]],
                "Sem anomalias de custo nos ultimos 30 dias. Padroes normais.", "",
            )

        rows = []
        for a in anomalies[:15]:
            anomaly_id = a.get("AnomalyId", "?")[:12]
            start_date = a.get("AnomalyStartDate", "?")[:10]
            end_date = a.get("AnomalyEndDate", "?")[:10] if a.get("AnomalyEndDate") else "em andamento"
            impact = a.get("Impact", {})
            max_impact = float(impact.get("MaxImpact", 0))
            total_impact = float(impact.get("TotalImpact", 0))
            root_causes = a.get("RootCauses", [])
            cause = root_causes[0].get("Service", "?") if root_causes else "?"
            rows.append([start_date, end_date, cause, f"${total_impact:.2f}", f"${max_impact:.2f}"])

        return _fmt_aws(
            "Anomalias de Custo — Ultimos 30 dias",
            ["Inicio", "Fim", "Servico", "Impacto Total", "Impacto Max"],
            rows, f"**{len(anomalies)} anomalia(s)** detectada(s). Investigue as de maior impacto.",
        )
    except Exception as e:
        logger.error(f"Cost anomalies error: {e}")
        return None


async def _finops_roi(**kwargs) -> Optional[str]:
    """FinOps ROI — compare current vs previous month + savings summary."""
    try:
        now = datetime.now(timezone.utc)
        # Current month
        curr_start = now.replace(day=1).strftime("%Y-%m-%d")
        curr_end = now.strftime("%Y-%m-%d")
        # Previous month
        if now.month == 1:
            prev_start = now.replace(year=now.year - 1, month=12, day=1).strftime("%Y-%m-%d")
            prev_end = now.replace(day=1).strftime("%Y-%m-%d")
        else:
            prev_start = now.replace(month=now.month - 1, day=1).strftime("%Y-%m-%d")
            prev_end = now.replace(day=1).strftime("%Y-%m-%d")

        curr_resp, prev_resp = await asyncio.gather(
            _call("ce", "get_cost_and_usage",
                  TimePeriod={"Start": curr_start, "End": curr_end},
                  Granularity="MONTHLY", Metrics=["UnblendedCost"]),
            _call("ce", "get_cost_and_usage",
                  TimePeriod={"Start": prev_start, "End": prev_end},
                  Granularity="MONTHLY", Metrics=["UnblendedCost"]),
            return_exceptions=True,
        )

        curr_cost = 0
        if not isinstance(curr_resp, Exception):
            results = curr_resp.get("ResultsByTime", [])
            if results:
                curr_cost = float(results[0].get("Total", {}).get("UnblendedCost", {}).get("Amount", 0))

        prev_cost = 0
        if not isinstance(prev_resp, Exception):
            results = prev_resp.get("ResultsByTime", [])
            if results:
                prev_cost = float(results[0].get("Total", {}).get("UnblendedCost", {}).get("Amount", 0))

        delta = curr_cost - prev_cost
        delta_pct = (delta / prev_cost * 100) if prev_cost > 0 else 0
        trend = "↑" if delta > 0 else "↓" if delta < 0 else "→"

        # Savings estimates from platform optimizations
        # LiteLLM multi-tier: 55% DeepSeek ($0.27/M) vs 100% Sonnet ($15/M)
        estimated_llm_savings = curr_cost * 0.15  # conservative 15% of total from LLM optimization
        services_off = 3  # aiops-agent, chainlit, litellm at desired_count=0
        est_savings_off = services_off * 0.04048 * 1024 / 1024 * 730  # rough Fargate savings per service

        rows = [
            ["Custo Mes Atual (parcial)", f"${curr_cost:.2f}"],
            ["Custo Mes Anterior", f"${prev_cost:.2f}"],
            [f"Variacao {trend}", f"${delta:+.2f} ({delta_pct:+.1f}%)"],
            ["", ""],
            ["**Economias Ativas**", ""],
            ["Servicos desligados (desired_count=0)", f"~${est_savings_off:.2f}/mes"],
            ["LLM multi-tier (DeepSeek 55%)", "~70% vs full Sonnet"],
            ["Shortcuts (sem LLM)", "$0 por query"],
        ]

        return _fmt_aws(
            "FinOps ROI — Plataforma Observability",
            ["Metrica", "Valor"], rows,
            f"Custo atual: **${curr_cost:.2f}** | Mes anterior: **${prev_cost:.2f}** | "
            f"Delta: **{delta_pct:+.1f}%** {trend}",
        )
    except Exception as e:
        logger.error(f"FinOps ROI error: {e}")
        return None


# ===================================================================
# SECURITY / AUDIT HANDLERS
# ===================================================================
async def _cloudtrail_logins(**kwargs) -> Optional[str]:
    """Recent console logins from CloudTrail."""
    try:
        resp = await _call(
            "cloudtrail", "lookup_events",
            LookupAttributes=[{"AttributeKey": "EventName", "AttributeValue": "ConsoleLogin"}],
            MaxResults=15,
        )
        events = resp.get("Events", [])
        if not events:
            return _fmt_aws("Console Logins", ["Info"], [["Nenhum login recente"]], "Sem logins registrados no CloudTrail.", "")

        rows = []
        for ev in events:
            ts = str(ev.get("EventTime", ""))[:19]
            user = ev.get("Username", "?")[:25]
            detail = ev.get("CloudTrailEvent", "{}")
            try:
                parsed = json.loads(detail)
                src_ip = parsed.get("sourceIPAddress", "—")
                result = parsed.get("responseElements", {}).get("ConsoleLogin", "—")
                mfa = "Sim" if parsed.get("additionalEventData", {}).get("MFAUsed") == "Yes" else "Nao"
            except (json.JSONDecodeError, TypeError):
                src_ip = "—"
                result = "—"
                mfa = "—"
            rows.append([ts, user, result, src_ip, mfa])

        return _fmt_aws(
            "Console Logins (CloudTrail)",
            ["Timestamp", "Usuario", "Resultado", "IP", "MFA"],
            rows, f"{len(events)} login(s) recente(s).",
        )
    except Exception as e:
        logger.error(f"CloudTrail logins error: {e}")
        return None


async def _cloudtrail_changes(**kwargs) -> Optional[str]:
    """Recent resource changes from CloudTrail."""
    try:
        now = datetime.now(timezone.utc)
        start = now - timedelta(hours=24)

        resp = await _call(
            "cloudtrail", "lookup_events",
            StartTime=start,
            EndTime=now,
            MaxResults=20,
        )
        events = resp.get("Events", [])

        write_events = []
        for ev in events:
            name = ev.get("EventName", "")
            if any(name.startswith(p) for p in ["Create", "Delete", "Update", "Put", "Modify", "Run", "Start", "Stop", "Terminate"]):
                write_events.append(ev)

        if not write_events:
            return _fmt_aws("Mudancas (24h)", ["Info"], [["Nenhuma mudanca detectada"]], "Sem alteracoes nas ultimas 24 horas.", "")

        rows = []
        for ev in write_events[:15]:
            ts = str(ev.get("EventTime", ""))[:19]
            name = ev.get("EventName", "?")
            user = ev.get("Username", "?")[:20]
            src = ev.get("EventSource", "?").replace(".amazonaws.com", "")[:15]
            rows.append([ts, name, user, src])

        return _fmt_aws(
            "Mudancas Recentes (CloudTrail — 24h)",
            ["Timestamp", "Evento", "Usuario", "Servico"],
            rows, f"**{len(write_events)} mudanca(s)** detectada(s) nas ultimas 24h.",
        )
    except Exception as e:
        logger.error(f"CloudTrail changes error: {e}")
        return None


async def _waf_overview(**kwargs) -> Optional[str]:
    """WAF Web ACL overview."""
    try:
        resp = await _call("wafv2", "list_web_acls", Scope="REGIONAL")
        acls = resp.get("WebACLs", [])
        if not acls:
            return _fmt_aws("WAF Web ACLs", ["Info"], [["Nenhuma Web ACL encontrada"]], "Sem WAF nesta conta/regiao.", "")

        rows = []
        for acl in acls:
            name = acl.get("Name", "?")
            acl_id = acl.get("Id", "?")[:12]
            desc = acl.get("Description", "—")[:30]
            rows.append([name, acl_id, desc])

        return _fmt_aws(
            "WAF Web ACLs",
            ["Nome", "ID", "Descricao"],
            rows, f"{len(acls)} Web ACL(s) configurada(s).",
        )
    except Exception as e:
        logger.error(f"WAF overview error: {e}")
        return None


# ===================================================================
# OVERVIEW HANDLER — aggregates multiple boto3 calls
# ===================================================================
async def _account_overview(**kwargs) -> Optional[str]:
    """Full account overview: ECS services, RDS, ElastiCache, S3, costs."""
    try:
        # Run all queries in parallel
        ecs_svc, rds_resp, cache_resp, s3_resp, cost_resp, lambda_resp = await asyncio.gather(
            _call("ecs", "list_services", cluster=ECS_CLUSTER, maxResults=50),
            _call("rds", "describe_db_instances"),
            _call("elasticache", "describe_cache_clusters"),
            _call("s3", "list_buckets"),
            _call("ce", "get_cost_and_usage",
                  TimePeriod={
                      "Start": (datetime.now(timezone.utc).replace(day=1)).strftime("%Y-%m-%d"),
                      "End": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
                  },
                  Granularity="MONTHLY",
                  Metrics=["UnblendedCost"],
                  GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}],
            ),
            _call("lambda", "list_functions"),
            return_exceptions=True,
        )

        sections = []

        # --- ECS Services ---
        sections.append("## ECS Services (Fargate)")
        if isinstance(ecs_svc, Exception):
            sections.append(f"Erro: {ecs_svc}")
        else:
            arns = ecs_svc.get("serviceArns", [])
            if arns:
                # API limit: max 10 services per describe_services call
                services = []
                for i in range(0, len(arns), 10):
                    batch = arns[i:i + 10]
                    desc = await _call("ecs", "describe_services", cluster=ECS_CLUSTER, services=batch)
                    services.extend(desc.get("services", []))
                sections.append(f"| Servico | Status | Tasks (running/desired) |")
                sections.append("|---------|--------|------------------------|")
                for svc in sorted(services, key=lambda s: s.get("serviceName", "")):
                    name = svc.get("serviceName", "?")
                    status = svc.get("status", "?")
                    running = svc.get("runningCount", 0)
                    desired = svc.get("desiredCount", 0)
                    sections.append(f"| {name} | {status} | {running}/{desired} |")
                sections.append(f"\n**{len(services)} servico(s)** no cluster `{ECS_CLUSTER}`")
            else:
                sections.append("Nenhum servico encontrado.")

        # --- RDS ---
        sections.append("\n## RDS (Banco de Dados)")
        if isinstance(rds_resp, Exception):
            sections.append(f"Erro: {rds_resp}")
        else:
            dbs = rds_resp.get("DBInstances", [])
            if dbs:
                sections.append("| Instancia | Engine | Class | Storage | Status |")
                sections.append("|-----------|--------|-------|---------|--------|")
                for db in dbs:
                    name = db.get("DBInstanceIdentifier", "?")
                    engine = f"{db.get('Engine', '?')} {db.get('EngineVersion', '')}"
                    cls = db.get("DBInstanceClass", "?")
                    storage = f"{db.get('AllocatedStorage', '?')} GB"
                    status = db.get("DBInstanceStatus", "?")
                    sections.append(f"| {name} | {engine} | {cls} | {storage} | {status} |")
            else:
                sections.append("Nenhuma instancia RDS encontrada.")

        # --- ElastiCache ---
        sections.append("\n## ElastiCache (Cache)")
        if isinstance(cache_resp, Exception):
            sections.append(f"Erro: {cache_resp}")
        else:
            clusters = cache_resp.get("CacheClusters", [])
            if clusters:
                sections.append("| Cluster | Engine | Node Type | Nodes | Status |")
                sections.append("|---------|--------|-----------|-------|--------|")
                for c in clusters:
                    name = c.get("CacheClusterId", "?")
                    engine = f"{c.get('Engine', '?')} {c.get('EngineVersion', '')}"
                    node_type = c.get("CacheNodeType", "?")
                    nodes = c.get("NumCacheNodes", 0)
                    status = c.get("CacheClusterStatus", "?")
                    sections.append(f"| {name} | {engine} | {node_type} | {nodes} | {status} |")
            else:
                sections.append("Nenhum cluster ElastiCache encontrado.")

        # --- S3 Buckets ---
        sections.append("\n## S3 Buckets")
        if isinstance(s3_resp, Exception):
            sections.append(f"Erro: {s3_resp}")
        else:
            buckets = s3_resp.get("Buckets", [])
            if buckets:
                sections.append("| Bucket | Criado em |")
                sections.append("|--------|-----------|")
                for b in sorted(buckets, key=lambda x: x.get("Name", "")):
                    name = b.get("Name", "?")
                    created = str(b.get("CreationDate", ""))[:10]
                    sections.append(f"| {name} | {created} |")
                sections.append(f"\n**{len(buckets)} bucket(s)**")
            else:
                sections.append("Nenhum bucket S3 encontrado.")

        # --- Lambda Functions ---
        sections.append("\n## Lambda Functions")
        if isinstance(lambda_resp, Exception):
            sections.append(f"Erro: {lambda_resp}")
        else:
            funcs = lambda_resp.get("Functions", [])
            if funcs:
                sections.append("| Funcao | Runtime | Memoria | Timeout |")
                sections.append("|--------|---------|---------|---------|")
                for f in sorted(funcs, key=lambda x: x.get("FunctionName", "")):
                    name = f.get("FunctionName", "?")
                    runtime = f.get("Runtime", "?")
                    mem = f"{f.get('MemorySize', '?')} MB"
                    timeout = f"{f.get('Timeout', '?')}s"
                    sections.append(f"| {name} | {runtime} | {mem} | {timeout} |")
                sections.append(f"\n**{len(funcs)} funcao(oes)**")
            else:
                sections.append("Nenhuma funcao Lambda encontrada.")

        # --- Costs ---
        sections.append("\n## Custos do Mes Atual")
        if isinstance(cost_resp, Exception):
            sections.append(f"Erro ao consultar custos: {cost_resp}")
        else:
            groups = cost_resp.get("ResultsByTime", [{}])[0].get("Groups", [])
            if groups:
                cost_items = []
                for g in groups:
                    svc_name = g["Keys"][0]
                    amount = float(g["Metrics"]["UnblendedCost"]["Amount"])
                    if amount > 0.01:
                        cost_items.append((svc_name, amount))
                cost_items.sort(key=lambda x: x[1], reverse=True)
                total = sum(a for _, a in cost_items)

                sections.append("| Servico AWS | Custo (USD) |")
                sections.append("|-------------|-------------|")
                for svc_name, amount in cost_items[:15]:
                    sections.append(f"| {svc_name} | ${amount:.2f} |")
                sections.append(f"| **TOTAL** | **${total:.2f}** |")
            else:
                sections.append("Sem dados de custo para o periodo.")

        title = f"# Recursos AWS — Conta {ACCOUNT_ID} (us-east-1)\n"
        return title + "\n".join(sections)

    except Exception as e:
        logger.error(f"Account overview error: {e}")
        return _fmt_aws(
            "Erro — Overview da Conta", ["Detalhe"], [[str(e)[:200]]],
            "Falha ao consultar recursos da conta.", "",
        )


# ===================================================================
# SHORTCUT REGISTRY — ordered most specific → most general
# ===================================================================
_AWS_SHORTCUTS: list[tuple[re.Pattern, callable]] = [
    # FinOps — most specific first
    (re.compile(r"savings?\s*plans?|cobertura\s*(sp|savings)", re.I), _savings_plan_coverage),
    (re.compile(r"reserved?\s*instance|ri\s*(recomenda|recommendation|compra)", re.I), _ri_recommendations),
    (re.compile(r"rightsiz(e|ing)|dimensionamento|redimensionar", re.I), _rightsizing_recommendations),
    (re.compile(r"anomalia\s*(de\s*)?(custo|gasto|cost)|cost\s*anomal|spike\s*(de\s*)?custo", re.I), _cost_anomalies),
    (re.compile(r"roi\s*(finops|plataforma|observ)|retorno.*investimento.*finops|finops\s*roi", re.I), _finops_roi),
    (re.compile(r"forecast|previs[aã]o\s*(de\s*)?(custo|gasto)", re.I), _cost_forecast),
    (re.compile(r"custo\s*(por|de\s*cada|top|maiores?)\s*servi[cç]o|top\s*servi[cç]o.*custo|servi[cç]os?\s*mais\s*caros?", re.I), _cost_by_service),
    (re.compile(r"custo\s*di[aá]rio|gasto\s*di[aá]rio|trend\s*de\s*custo|custo.*[u\u00fa]ltimos?\s*\d+\s*dias?", re.I), _cost_daily_trend),
    (re.compile(r"(?!.*(?:otimizar|reduzir|economizar|diminuir|cortar|baixar|melhorar|dicas?|estrat[eé]gi|como\s+(?:otimizar|reduzir|economizar|diminuir)))(?:quanto\s*(?:custa|gasta|gastou|custou)|gasto\s*(?:aws|mensal|m[eê]s|atual)|custo\s*(?:atual|total|m[eê]s|mensal|da\s+conta|aws)|(?:qual|me\s+(?:d[aá]|mostr[ae]))\s*o?\s*custo|cost\s+(?:current|this\s+month))", re.I), _cost_current_month),

    # Security — CloudTrail
    (re.compile(r"login|console\s*login|quem\s*(logou|entrou|acessou)", re.I), _cloudtrail_logins),
    (re.compile(r"mudan[cç]as?|altera[cç][oõ]es?|quem\s*(fez|alterou|criou|deletou|modificou)|o\s*que\s*(mudou|alterou|aconteceu)", re.I), _cloudtrail_changes),
    (re.compile(r"cloud\s*trail|audit|eventos?\s*(recentes?|aws)", re.I), _cloudtrail_recent),
    (re.compile(r"waf\b|web\s*acl|firewall\s*aplicacao", re.I), _waf_overview),

    # ECS — specific first
    (re.compile(r"deploy(ment)?s?\s*(ecs|recentes?)|rollout|ecs\s*deploy", re.I), _ecs_deployments),
    (re.compile(r"eventos?\s*ecs|ecs\s*eventos?|eventos?\s*(do\s*)?(servico|cluster)", re.I), _ecs_events),
    (re.compile(r"tasks?\s*(ecs|rodando|running|ativas?)|ecs\s*tasks?|quantas?\s*tasks?", re.I), _ecs_tasks),
    (re.compile(r"servi[cç]os?\s*(ecs|rodando|running|ativos?|no\s*cluster|do\s*cluster)|ecs\s*servi[cç]os?|quantos?\s*servi[cç]os?|list(ar|e)?\s*servi[cç]os?|o\s*que\s*(est[aá]|tem)\s*rodando|quais?\s*(servi[cç]os?|containers?)\s*(est[aã]o|rodando|ativos?)", re.I), _ecs_services),

    # RDS / ElastiCache
    (re.compile(r"rds\b|banco\s*de\s*dados|database|postgres|mysql|aurora", re.I), _rds_status),
    (re.compile(r"elasticache|redis\b|cache\s*(cluster|status)", re.I), _elasticache_status),

    # ECR
    (re.compile(r"ecr\b|imagens?\s*(docker|container|ecr)|reposit[oó]rios?\s*ecr", re.I), _ecr_images),

    # Platform
    (re.compile(r"vpc\b|vpcs?\b|cidr|subnets?", re.I), _vpc_overview),
    (re.compile(r"security\s*groups?|sg\b|grupos?\s*de\s*seguran[cç]a", re.I), _security_groups),
    (re.compile(r"nat\s*gateway|nat\s*gw|natgw", re.I), _nat_gateways),
    (re.compile(r"cloud\s*map|service\s*discovery|namespace", re.I), _cloudmap_services),
    (re.compile(r"route\s*53|hosted\s*zones?|dns\s*(zones?|registros?)", re.I), _route53_overview),

    # CloudWatch alarms — general
    (re.compile(r"alarm(es?|s)?\s*(cloudwatch|ativo|active|disparando)|cloudwatch\s*alarm", re.I), _alarms_active),

    # Account overview — MUST be last (most general, catches broad questions)
    (re.compile(
        r"(quais|todos)\s*(os\s*)?(recursos|servi[cç]os)\s*(aprovisionados|rodando|ativos|consumidos|tem|temos)|"
        r"overview\s*(da\s*)?(conta|account)|"
        r"inventario|inventory|"
        r"o\s*que\s*(tem|temos|esta|roda)\s*(na|nessa|nesta)\s*(conta|aws|infra)|"
        r"recursos?\s*(da\s*)?(conta|aws|infra)|"
        r"resumo\s*(da\s*)?(conta|infra|aws)",
        re.I,
    ), _account_overview),
]


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------
async def try_aws_shortcut(question: str) -> Optional[str]:
    """Try to answer AWS question with direct boto3 call.

    Returns formatted markdown response or None (fallback to LLM).
    """
    start = time.monotonic()
    q_lower = question.lower()

    for pattern, handler in _AWS_SHORTCUTS:
        if pattern.search(q_lower):
            try:
                response = await handler(question=question)
                elapsed_ms = (time.monotonic() - start) * 1000

                if response:
                    source = "AWS API (boto3)"
                    response += (
                        f"\n\n---\n*Resposta direta via {source} — "
                        f"{elapsed_ms:.0f}ms (sem LLM)*"
                    )
                    logger.info(json.dumps({
                        "event": "aws_shortcut",
                        "hit": True,
                        "handler": handler.__name__ if hasattr(handler, "__name__") else "lambda",
                        "latency_ms": round(elapsed_ms),
                        "question": question[:100],
                    }))
                    return response

                logger.info(json.dumps({
                    "event": "aws_shortcut",
                    "hit": False,
                    "reason": "no_data",
                    "latency_ms": round(elapsed_ms),
                    "question": question[:100],
                }))
                return None

            except Exception as e:
                logger.error(f"AWS shortcut handler error: {e}")
                return None

    elapsed_ms = (time.monotonic() - start) * 1000
    logger.info(json.dumps({
        "event": "aws_shortcut",
        "hit": False,
        "reason": "no_match",
        "latency_ms": round(elapsed_ms),
        "question": question[:100],
    }))
    return None

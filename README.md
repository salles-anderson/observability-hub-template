# 🔭 Observability Hub — Enterprise AIOps Platform

> Enterprise-grade observability platform with LGTM stack, AI-powered agents, and MCP servers.
> Built for high-criticality environments (financial services, stock exchanges, fintechs).

[![Terraform](https://img.shields.io/badge/Terraform-1.14+-623CE4?logo=terraform)](https://terraform.io)
[![Grafana](https://img.shields.io/badge/Grafana-11.4+-F46800?logo=grafana)](https://grafana.com)
[![Claude](https://img.shields.io/badge/Claude-Sonnet_4.6-D97706?logo=anthropic)](https://anthropic.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## 📋 Table of Contents

- [Architecture](#architecture)
- [Stack](#stack)
- [Quick Start](#quick-start)
- [Directory Structure](#directory-structure)
- [Terraform Workspaces](#terraform-workspaces)
- [Docker Services](#docker-services)
- [MCP Servers](#mcp-servers)
- [Dashboards](#dashboards)
- [Alerts](#alerts)
- [AI Agents](#ai-agents)
- [Sprint Roadmap](#sprint-roadmap)
- [Cost Analysis](#cost-analysis)

---

## 🏗 Architecture

```
                         ┌─────────────────────────────────┐
                         │        Your Applications        │
                         │   API-1 │ API-2 │ ... │ API-N   │
                         └────────────┬────────────────────┘
                                      │ OTLP + Logs + Metrics
                         ┌────────────▼────────────────────┐
                         │      Telemetry Collectors        │
                         │   Alloy (OTEL) + Fluent Bit      │
                         └────────────┬────────────────────┘
                                      │
            ┌─────────────────────────┼─────────────────────────┐
            ▼                         ▼                         ▼
     ┌────────────┐           ┌────────────┐            ┌────────────┐
     │ Prometheus  │           │    Loki    │            │   Tempo    │
     │  Metrics    │           │    Logs    │            │  Traces    │
     └──────┬─────┘           └──────┬─────┘            └──────┬─────┘
            │                        │                         │
            └────────────────────────┼─────────────────────────┘
                                     ▼
                         ┌───────────────────────┐
                         │       Grafana          │
                         │  38+ Dashboards        │
                         │  26+ Alert Rules       │
                         │  SLO/Error Budget      │
                         └───────────┬───────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
             ┌──────────┐   ┌──────────┐    ┌──────────────┐
             │  Slack    │   │PagerDuty │    │  AI Agent    │
             │ #alerts   │   │  On-Call  │    │  (AG-5)      │
             └──────────┘   └──────────┘    └──────┬───────┘
                                                    │
                                    ┌───────────────┼───────────────┐
                                    ▼               ▼               ▼
                              ┌──────────┐   ┌──────────┐   ┌──────────┐
                              │ mcp-aws  │   │mcp-github│   │ mcp-tfc  │
                              │ 8 tools  │   │ 13 tools │   │ 5 tools  │
                              └──────────┘   └──────────┘   └──────────┘
                                    ▼               ▼               ▼
                              ┌──────────┐   ┌──────────┐   ┌──────────┐
                              │mcp-qdrant│   │mcp-grafna│   │mcp-conflu│
                              │ 3 tools  │   │ PromQL   │   │ 6 tools  │
                              └──────────┘   └──────────┘   └──────────┘
```

### Hub-and-Spoke Topology

```
                    ┌─────────────────┐
                    │   Hub Account   │
                    │ Observability   │
                    │ LGTM + AI + SQ  │
                    └────────┬────────┘
                             │ Transit Gateway
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │  Spoke: Dev  │  │ Spoke: Prod  │  │ Spoke: Infra │
   │  APIs + Apps │  │  Production  │  │  Kong + WAF  │
   └──────────────┘  └──────────────┘  └──────────────┘
```

---

## 🛠 Stack

### Core Observability (LGTM+)

| Component | Version | Purpose |
|-----------|---------|---------|
| **Grafana** | 11.4+ | Dashboards, alerting, visualization |
| **Prometheus** | 2.54+ | Time-series metrics (PromQL) |
| **Loki** | 3.0+ | Log aggregation (LogQL) |
| **Tempo** | 2.4+ | Distributed tracing (TraceQL) |
| **Alloy** | 1.8+ | Telemetry collector (replaces OTel/Promtail) |
| **AlertManager** | 0.27+ | Alert routing, dedup, silencing |

### AI/ML Layer

| Component | Version | Purpose |
|-----------|---------|---------|
| **Claude Sonnet** | 4.6 | AI orchestrator + correlator |
| **Gemini Pro** | 3.1 | Router + specialized agents |
| **DeepSeek** | V3.2 | Cost-efficient agents (FinOps, Security) |
| **LiteLLM** | latest | Multi-model proxy with budget controls |
| **Qdrant** | 1.13+ | Vector DB for RAG + semantic cache |
| **Chainlit** | latest | Web chat UI with OAuth |

### Infrastructure

| Component | Purpose |
|-----------|---------|
| **AWS ECS Fargate** | Container orchestration (11+ services) |
| **Terraform Cloud** | IaC with remote state + plan/apply |
| **GitHub Actions** | CI/CD with auto-deploy on push |
| **Transit Gateway** | Cross-account networking |
| **WAF + Cognito** | Security (IP allowlist + OAuth MFA) |
| **ElastiCache Redis** | LLM response cache |
| **RDS Aurora** | Grafana backend + business KPIs |

### MCP Servers (7)

| Server | Port | Tools | Purpose |
|--------|------|-------|---------|
| mcp-aws | 8001 | 8 | ECS, RDS, Redis, VPC, Cost Explorer, GuardDuty |
| mcp-github | 8002 | 13 | Repos, PRs, commits, workflows, code search |
| mcp-tfc | 8003 | 5 | Terraform Cloud workspaces, runs, state |
| mcp-qdrant | 8004 | 3 | RAG knowledge base, semantic cache |
| mcp-grafana | 8000 | N/A | PromQL, LogQL, TraceQL, dashboards |
| mcp-confluence | 8005 | 6 | Create/read/update Confluence pages |
| mcp-eraser | 8006 | 2 | Architecture diagram generation |

---

## 🚀 Quick Start

### Prerequisites

- AWS Account with admin access
- Terraform Cloud account (free tier works)
- GitHub account
- Anthropic API key (Claude)
- Docker installed locally

### Step 1: Clone and configure

```bash
git clone https://github.com/YOUR_USER/observability-hub-template.git
cd observability-hub-template

# Copy example configs
cp terraform/hub/terraform.tfvars.example terraform/hub/terraform.tfvars
cp terraform/grafana/terraform.tfvars.example terraform/grafana/terraform.tfvars

# Edit with your values
vim terraform/hub/terraform.tfvars
```

### Step 2: Deploy infrastructure

```bash
# Initialize Terraform Cloud workspace
cd terraform/hub
terraform init
terraform plan
terraform apply

# Deploy Grafana dashboards
cd ../grafana
terraform init
terraform plan
terraform apply
```

### Step 3: Build and push Docker images

```bash
# Login to ECR
aws ecr get-login-password | docker login --username AWS --password-stdin YOUR_ACCOUNT.dkr.ecr.REGION.amazonaws.com

# Build all images
./scripts/build-all.sh

# Or build individually
docker build -t YOUR_ECR/grafana:11.4.0 docker/grafana/
docker build -t YOUR_ECR/chainlit-chat:latest docker/chainlit-chat/
```

### Step 4: Verify

```bash
# Check all services are running
aws ecs describe-services --cluster YOUR_CLUSTER --services $(aws ecs list-services --cluster YOUR_CLUSTER --query 'serviceArns' --output text)

# Open Grafana
echo "https://grafana.YOUR_DOMAIN"
```

---

## 📁 Directory Structure

```
observability-hub-template/
│
├── terraform/
│   ├── hub/                          # Main infrastructure (ECS, ALB, RDS, IAM)
│   │   ├── main.tf                   # Provider + backend
│   │   ├── variables.tf              # All variables
│   │   ├── terraform.tfvars.example  # Example values
│   │   ├── grafana.tf                # Grafana ECS service
│   │   ├── prometheus.tf             # Prometheus ECS service
│   │   ├── loki.tf                   # Loki ECS service
│   │   ├── tempo.tf                  # Tempo ECS service
│   │   ├── alloy.tf                  # Alloy ECS service
│   │   ├── alertmanager.tf           # AlertManager ECS service
│   │   ├── litellm.tf                # LiteLLM proxy
│   │   ├── chainlit-chat.tf          # AI Assistant + MCP sidecars
│   │   ├── sonarqube.tf              # SonarQube (optional)
│   │   ├── waf.tf                    # WAF IP allowlist
│   │   ├── cognito.tf                # Cognito OAuth
│   │   ├── secrets.tf                # SSM parameters
│   │   ├── iam.tf                    # IAM roles + policies
│   │   ├── ecr.tf                    # ECR repositories
│   │   └── configs/
│   │       ├── prometheus.yml        # Prometheus scrape config
│   │       ├── prometheus-rules.yml  # SLI/SLO recording rules
│   │       └── litellm-config.yaml   # LiteLLM multi-model config
│   │
│   ├── grafana/                      # Dashboards + Alerts (separate workspace)
│   │   ├── dashboards.tf             # Dashboard provisioning logic
│   │   ├── folders.tf                # Grafana folders
│   │   ├── alerts.tf                 # Alert rules
│   │   ├── alerts-slo.tf             # SLO burn-rate alerts
│   │   ├── notifications.tf          # Slack/PagerDuty contact points
│   │   ├── variables.tf              # Projects + datasources config
│   │   └── dashboards/
│   │       ├── templates/            # Reusable dashboard templates (.tftpl)
│   │       ├── observability/        # Self-monitoring dashboards
│   │       └── projects/             # Per-project static dashboards
│   │
│   └── vpc/                          # VPC + Transit Gateway (optional)
│
├── docker/
│   ├── grafana/                      # Custom Grafana with branding
│   │   ├── Dockerfile
│   │   ├── grafana-custom.ini
│   │   ├── css/teck-theme.css
│   │   └── img/                      # Logo assets
│   │
│   ├── chainlit-chat/                # AI Assistant (AG-5)
│   │   ├── Dockerfile
│   │   ├── app.py                    # Chainlit UI
│   │   ├── agent.py                  # AG-1/AG-2 entry point
│   │   ├── semantic_cache.py         # Qdrant-based response cache
│   │   ├── rag_retriever.py          # RAG knowledge base
│   │   ├── rag_indexer.py            # Document indexer
│   │   ├── guardrails.py             # Input/output security
│   │   ├── core/
│   │   │   ├── orchestrator.py       # AG-2 pipeline
│   │   │   ├── orchestrator_ag5.py   # AG-5 pipeline (Claude + MCP)
│   │   │   ├── router.py             # Gemini query classifier
│   │   │   ├── base_agent.py         # ReAct loop (Anthropic + OpenAI SDK)
│   │   │   ├── mcp_client.py         # MCP server manager
│   │   │   ├── guardrails.py         # RBAC + input/output scanning
│   │   │   └── models.py             # Data models
│   │   ├── agents/                   # 7 specialized agents
│   │   │   ├── observability.py      # Prometheus/Loki/Tempo
│   │   │   ├── infrastructure.py     # AWS ECS/RDS/VPC
│   │   │   ├── code.py               # GitHub/SonarQube
│   │   │   ├── cicd.py               # Terraform Cloud
│   │   │   ├── finops.py             # AWS Cost Explorer
│   │   │   ├── security.py           # GuardDuty/CloudTrail
│   │   │   └── correlator.py         # Cross-domain synthesis (Claude)
│   │   ├── prompts/                  # System prompts per domain
│   │   ├── shortcuts/                # Regex fast-path (no LLM)
│   │   └── tools/                    # Tool registry + executors
│   │
│   ├── mcp-aws/                      # MCP Server: AWS tools
│   ├── mcp-github/                   # MCP Server: GitHub tools
│   ├── mcp-tfc/                      # MCP Server: Terraform Cloud
│   ├── mcp-qdrant/                   # MCP Server: RAG + Cache
│   ├── mcp-grafana/                  # MCP Server: Grafana (Go binary)
│   ├── mcp-confluence/               # MCP Server: Confluence API
│   ├── mcp-eraser/                   # MCP Server: Diagram generation
│   ├── kong-ai/                      # Kong AI Gateway (PII removal)
│   └── aiops-agent/                  # Slack /ask-hub bot
│
├── docs/
│   ├── 01-overview.md                # Architecture overview
│   ├── 02-lgtm-stack.md              # LGTM deep dive
│   ├── 03-aiops-llm.md               # AI agents + LLM
│   ├── 04-infrastructure.md          # AWS infrastructure
│   ├── 05-terraform-iac.md           # Terraform patterns
│   ├── 06-telemetry-pipeline.md      # Alloy + Fluent Bit
│   ├── 07-alerts-dashboards.md       # Alerting strategy
│   ├── 08-cicd.md                    # GitHub Actions
│   ├── 09-security.md                # Security & compliance
│   ├── 10-runbook.md                 # Operational runbook
│   ├── 11-multi-agent.md             # Agent architecture
│   ├── 12-rag-knowledge.md           # RAG pipeline
│   ├── 13-prompt-engineering.md      # Prompts & guardrails
│   └── 14-repository-structure.md    # This structure explained
│
├── .github/workflows/
│   └── ecr-sync.yml                  # Auto-build + deploy on push
│
├── k6/
│   └── scripts/                      # Load testing scripts
│
├── scripts/
│   ├── build-all.sh                  # Build all Docker images
│   ├── deploy.sh                     # Force deploy ECS services
│   └── waf-update-ip.sh              # Update WAF IP allowlist
│
└── README.md                         # This file
```

---

## 🎯 Sprint Roadmap

### Phase 0: Foundation (Week 1-2)
- [ ] S0.1 — AWS account setup, VPC, networking
- [ ] S0.2 — Terraform Cloud workspaces
- [ ] S0.3 — ECS cluster + ECR repositories
- [ ] S0.4 — ALB + WAF + Cognito

### Phase 1: LGTM Core (Week 3-5)
- [ ] S1.1 — Prometheus + Loki + Tempo + Alloy
- [ ] S1.2 — Grafana (custom branding)
- [ ] S1.3 — AlertManager + Slack integration
- [ ] S1.4 — Telemetry sidecars (Fluent Bit + ADOT)

### Phase 2: SLOs & Alerts (Week 6-7)
- [ ] S2.1 — SLI recording rules (RED/USE/Golden Signals)
- [ ] S2.2 — SLO framework (error budget, burn rate)
- [ ] S2.3 — Multi-tier alerts (P1→PagerDuty, P2→Slack)
- [ ] S2.4 — Anomaly detection (z-score)

### Phase 3: Dashboards (Week 8-9)
- [ ] S3.1 — Infrastructure dashboards (ECS, RDS, Redis, ALB)
- [ ] S3.2 — API dashboards (per-service health)
- [ ] S3.3 — SLO dashboard + Error Budget
- [ ] S3.4 — Business KPIs (PostgreSQL datasource)
- [ ] S3.5 — Home executive dashboard (branded)

### Phase 4: AI Agents (Week 10-12)
- [ ] S4.1 — LiteLLM proxy (multi-model)
- [ ] S4.2 — Qdrant RAG (knowledge base)
- [ ] S4.3 — Chainlit chat UI (OAuth)
- [ ] S4.4 — AG-2 Multi-agent (Router → Agents → Correlator)
- [ ] S4.5 — AG-5 Claude + MCP Servers
- [ ] S4.6 — Semantic cache (Qdrant)
- [ ] S4.7 — Alert investigation (AG-3)

### Phase 5: Hardening (Week 13-16)
- [ ] S5.1 — RBAC (Cognito SSO + folder permissions)
- [ ] S5.2 — Security (GuardDuty, CloudTrail, WAF)
- [ ] S5.3 — Chaos engineering (game days)
- [ ] S5.4 — DR testing (failover, backup/restore)
- [ ] S5.5 — On-call rotation (PagerDuty)
- [ ] S5.6 — Documentation (Confluence auto-generation)

---

## 💰 Cost Analysis

### Infrastructure (~$400/month)

| Service | Monthly Cost |
|---------|-------------|
| ECS Fargate (11 services) | ~$160 |
| RDS Aurora (Grafana backend) | ~$55 |
| ElastiCache Redis | ~$13 |
| ALB + NAT | ~$62 |
| WAF | ~$12 |
| EFS (Prometheus/Loki/Tempo data) | ~$15 |
| Other (ECR, CloudWatch, S3) | ~$20 |
| **Total Infra** | **~$337** |

### LLM Tokens (~$30/month)

| Provider | Model | Budget |
|----------|-------|--------|
| Anthropic | Claude Sonnet 4.6 | $20 |
| Google | Gemini 3.1 Pro / 2.0 Flash | $5 |
| DeepSeek | V3.2 / Reasoner | $5 |
| **Total LLM** | | **~$30** |

### ROI

| Metric | Value |
|--------|-------|
| Total monthly cost | ~$407 |
| Datadog equivalent | ~$738/month |
| Dynatrace equivalent | ~$1,329/month |
| **ROI vs Datadog** | **22x** |
| **Annual savings** | **~$4,000-11,000** |

---

## 📚 References

- [Google SRE Book](https://sre.google/sre-book/table-of-contents/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Anthropic Claude API](https://docs.anthropic.com/)
- [MCP Protocol](https://modelcontextprotocol.io/)
- [Terraform AWS Modules](https://github.com/salles-anderson/modules-aws-tf)

---

## 📄 License

MIT License — See [LICENSE](LICENSE) for details.

---

> Built with ❤️ by [Anderson Sales](https://github.com/salles-anderson)
> Platform Engineer | SRE | AIOps

# 📋 Sprint Roadmap — Observability Hub

> Plano completo de implementação com tasks e subtasks.
> Baseado em experiência real: 483 commits, 8 sprints concluídas, 11 contas AWS.

---

## Fase 0: Foundation (Semanas 1-2)

### Sprint S0.1 — Discovery & Assessment
**Duração:** 3-4 dias | **Prioridade:** P1

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Inventário de infraestrutura** | | SRE | |
| | | Listar todos os serviços AWS (ECS, EC2, RDS, Lambda) | | [ ] |
| | | Mapear VPCs, subnets, security groups, CIDRs | | [ ] |
| | | Identificar contas AWS e AWS Organization | | [ ] |
| | | Documentar DNS (Route53), domínios, certificados (ACM) | | [ ] |
| | | Listar ALBs, Target Groups, listeners | | [ ] |
| | | Mapear ElastiCache, SQS, S3 buckets | | [ ] |
| 2 | **Assessment do monitoramento existente** | | SRE | |
| | | Listar ferramentas atuais (Zabbix, CloudWatch, etc.) | | [ ] |
| | | Identificar alertas configurados e canais de notificação | | [ ] |
| | | Mapear gaps de cobertura (o que NÃO é monitorado) | | [ ] |
| | | Avaliar o que migrar vs descartar | | [ ] |
| 3 | **Mapeamento de serviços críticos** | | SRE + PO | |
| | | Classificar serviços por criticidade (Tier 1/2/3) | | [ ] |
| | | Mapear dependências entre serviços | | [ ] |
| | | Identificar dependências externas (APIs terceiras) | | [ ] |
| | | Documentar SLAs regulatórios/contratuais existentes | | [ ] |
| 4 | **Baseline de métricas** | | SRE | |
| | | Coletar latência atual por serviço (P50/P95/P99) | | [ ] |
| | | Coletar error rate por serviço | | [ ] |
| | | Coletar throughput (requests/segundo) | | [ ] |
| | | Documentar volume de logs/dia | | [ ] |
| | | Estimar custo atual de monitoramento | | [ ] |

### Sprint S0.2 — IaC Foundation
**Duração:** 3-4 dias | **Prioridade:** P1

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Setup Terraform Cloud** | | DevOps | |
| | | Criar organização | | [ ] |
| | | Configurar VCS integration (GitHub) | | [ ] |
| | | Criar workspace: observability-hub-prod | | [ ] |
| | | Criar workspace: grafana-dashboards | | [ ] |
| | | Configurar variáveis (AWS keys, tokens) | | [ ] |
| 2 | **VPC & Networking** | | DevOps | |
| | | Criar VPC dedicada (CIDR sem conflito) | | [ ] |
| | | Subnets privadas (2 AZs mínimo) | | [ ] |
| | | NAT Gateway | | [ ] |
| | | Transit Gateway ou VPC Peering (cross-account) | | [ ] |
| | | Security Groups (restritivos, least privilege) | | [ ] |
| | | Cloud Map namespace (service discovery) | | [ ] |
| 3 | **ECS Cluster** | | DevOps | |
| | | Cluster Fargate | | [ ] |
| | | Task execution role + task role | | [ ] |
| | | ECR repositories (11 imagens) | | [ ] |
| | | CloudWatch log groups | | [ ] |
| 4 | **ALB + WAF + DNS** | | DevOps | |
| | | ALB com TLS 1.3 (ACM certificate) | | [ ] |
| | | WAF com IP allowlist | | [ ] |
| | | Route53 records (grafana.yourdomain.com) | | [ ] |
| | | Health check targets | | [ ] |
| 5 | **Storage** | | DevOps | |
| | | EFS file system (Prometheus/Loki/Tempo data) | | [ ] |
| | | EFS access points (1 por serviço) | | [ ] |
| | | RDS Aurora (Grafana backend) | | [ ] |
| | | S3 bucket (ALB logs, backups) | | [ ] |

---

## Fase 1: LGTM Stack (Semanas 3-5)

### Sprint S1.1 — Core LGTM
**Duração:** 5 dias | **Prioridade:** P1

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Prometheus** | | SRE | |
| | | ECS service + EFS mount | | [ ] |
| | | prometheus.yml (scrape config) | | [ ] |
| | | Recording rules (SLI: latência, error rate, throughput) | | [ ] |
| | | Remote write receiver habilitado | | [ ] |
| | | Retention configurada (30-90 dias) | | [ ] |
| | | Health check endpoint | | [ ] |
| 2 | **Loki** | | SRE | |
| | | ECS service + EFS mount | | [ ] |
| | | loki-config.yaml | | [ ] |
| | | Structured metadata habilitado | | [ ] |
| | | Retention configurada | | [ ] |
| | | Compactor configurado | | [ ] |
| 3 | **Tempo** | | SRE | |
| | | ECS service + EFS mount | | [ ] |
| | | tempo-config.yaml | | [ ] |
| | | OTLP receiver (gRPC :4317 + HTTP :4318) | | [ ] |
| | | Service graph generation | | [ ] |
| 4 | **Alloy** | | SRE | |
| | | ECS service (telemetry collector) | | [ ] |
| | | Scrape Prometheus targets | | [ ] |
| | | Forward logs to Loki | | [ ] |
| | | Forward traces to Tempo | | [ ] |
| 5 | **AlertManager** | | SRE | |
| | | ECS service | | [ ] |
| | | Slack webhook configuration | | [ ] |
| | | Routing rules (por severidade) | | [ ] |
| | | Silencing e inhibition rules | | [ ] |
| 6 | **Grafana** | | SRE | |
| | | ECS service + RDS backend | | [ ] |
| | | Datasources: Prometheus, Loki, Tempo, AlertManager | | [ ] |
| | | Admin user + password (SSM) | | [ ] |
| | | Custom branding (logo, CSS, favicon) | | [ ] |
| | | Plugins: Dynamic Text | | [ ] |
| | | Validar: todos os datasources conectam | | [ ] |

### Sprint S1.2 — Telemetry Sidecars
**Duração:** 3 dias | **Prioridade:** P1

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Template de sidecar** | | DevOps | |
| | | Fluent Bit (FireLens) → Loki | | [ ] |
| | | ADOT Collector → Tempo | | [ ] |
| | | Container definition reutilizável (locals.tf) | | [ ] |
| | | Labels padrão: job, service, environment | | [ ] |
| 2 | **Instrumentar serviços Tier 1** | | DevOps | |
| | | Adicionar sidecars no task definition | | [ ] |
| | | Validar logs chegando no Loki | | [ ] |
| | | Validar traces chegando no Tempo | | [ ] |
| | | Validar métricas no Prometheus | | [ ] |
| 3 | **Instrumentar serviços Tier 2/3** | | DevOps | |
| | | Repetir para todos os serviços restantes | | [ ] |
| | | Validar label mapping (Loki vs Prometheus) | | [ ] |

---

## Fase 2: SLOs & Alertas (Semanas 6-7)

### Sprint S2.1 — SLI/SLO Framework
**Duração:** 3-4 dias | **Prioridade:** P1

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Definir SLIs** | | SRE + PO | |
| | | Availability: % requests < 500 | | [ ] |
| | | Latency: P95 e P99 | | [ ] |
| | | Error rate: % 5xx / total | | [ ] |
| | | Throughput: req/s | | [ ] |
| 2 | **Definir SLOs** | | SRE + PO | |
| | | Tier 1: 99.9% (43 min/mês downtime) | | [ ] |
| | | Tier 2: 99.5% (3.6h/mês) | | [ ] |
| | | Tier 3: 99.0% (7.3h/mês) | | [ ] |
| | | Error Budget policy document | | [ ] |
| 3 | **Recording rules** | | SRE | |
| | | `sli:http_requests_total:rate5m` | | [ ] |
| | | `sli:http_error_rate:ratio_rate1h` | | [ ] |
| | | `sli:http_latency_p95:5m` | | [ ] |
| | | `sli:http_availability:ratio_rate1d` | | [ ] |
| | | `slo:error_budget_remaining:ratio` | | [ ] |
| | | `slo:burn_rate:ratio_1h/6h/1d` | | [ ] |
| 4 | **Anomaly detection** | | SRE | |
| | | Z-score recording rules (1h, 6h) | | [ ] |
| | | Error rate anomaly | | [ ] |
| | | Latency anomaly | | [ ] |
| | | Throughput drop | | [ ] |

### Sprint S2.2 — Alertas Multi-Tier
**Duração:** 2-3 dias | **Prioridade:** P1

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Alertas API (por serviço)** | | SRE | |
| | | High Error Rate (> 5%) | | [ ] |
| | | High Latency P95 | | [ ] |
| | | Service Down (0 health checks) | | [ ] |
| | | High Request Rate (capacity) | | [ ] |
| | | High Client Error Rate (4xx) | | [ ] |
| 2 | **Alertas Infra** | | SRE | |
| | | ECS CPU > 80% | | [ ] |
| | | ECS Memory > 80% | | [ ] |
| | | ECS Tasks Unhealthy | | [ ] |
| | | RDS CPU > 80% | | [ ] |
| | | RDS Connections > 80% max | | [ ] |
| | | RDS Storage < 20% | | [ ] |
| | | Redis Memory > 80% | | [ ] |
| | | Redis Evictions > 0 | | [ ] |
| 3 | **Alertas SLO** | | SRE | |
| | | Fast Burn (14.4x budget, 2min) | | [ ] |
| | | Slow Burn (6x budget, 5min) | | [ ] |
| | | Chronic Burn (1x budget, 30min) | | [ ] |
| | | Latency P99 SLO violation | | [ ] |
| 4 | **Alertas Anomaly** | | SRE | |
| | | Error Rate z-score > 3σ | | [ ] |
| | | Latency z-score > 3σ | | [ ] |
| | | Throughput Drop z-score < -3σ | | [ ] |
| 5 | **Notification routing** | | SRE | |
| | | P1 → Slack #incidents + PagerDuty | | [ ] |
| | | P2 → Slack #alerts | | [ ] |
| | | P3 → Slack #monitoring | | [ ] |
| | | Anomaly → Slack + AI Agent webhook | | [ ] |

---

## Fase 3: Dashboards (Semanas 8-9)

### Sprint S3.1 — Dashboards Infra
**Duração:** 3-4 dias | **Prioridade:** P1

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Templates reutilizáveis (.tftpl)** | | SRE | |
| | | api-overview.json.tftpl (RED metrics) | | [ ] |
| | | ecs-metrics.json.tftpl (CPU/Memory/Tasks) | | [ ] |
| | | logs.json.tftpl (Loki structured) | | [ ] |
| | | traces.json.tftpl (Tempo) | | [ ] |
| | | rds.json.tftpl (connections, IOPS, storage) | | [ ] |
| | | elasticache-redis.json.tftpl | | [ ] |
| | | alb.json.tftpl (requests, latency, errors) | | [ ] |
| | | sqs.json.tftpl (depth, DLQ, age) | | [ ] |
| 2 | **Dashboards por projeto** | | SRE | |
| | | Project A: DEV (8 dashboards) | | [ ] |
| | | Project A: HML (8 dashboards) | | [ ] |
| | | Project A: PRD (8 dashboards) | | [ ] |
| 3 | **Dashboards DBA avançado** | | SRE | |
| | | Connections vs MAX (gauge) | | [ ] |
| | | Swap Usage | | [ ] |
| | | Transaction Logs Disk | | [ ] |
| | | Deadlocks | | [ ] |
| | | Disk Queue Depth | | [ ] |
| | | Performance Insights habilitado | | [ ] |

### Sprint S3.2 — Dashboards Negócio + Observability
**Duração:** 3-4 dias | **Prioridade:** P2

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Business KPIs** | | SRE + PO | |
| | | PostgreSQL datasource (read-only user) | | [ ] |
| | | SG Rule Hub → RDS via TGW | | [ ] |
| | | KPIs de negócio (SQL direto) | | [ ] |
| | | Funnel / conversão (pie charts) | | [ ] |
| | | Tendências (time series por dia) | | [ ] |
| 2 | **SLO Dashboard** | | SRE | |
| | | Error budget remaining (gauge) | | [ ] |
| | | Burn rate 1h/6h/1d (multi-line) | | [ ] |
| | | SLO compliance history | | [ ] |
| 3 | **Home Executive** | | SRE | |
| | | Logo + branding | | [ ] |
| | | KPIs globais (alertas, error rate, latência, availability) | | [ ] |
| | | Project cards com links | | [ ] |
| | | Métricas globais (request rate, error rate) | | [ ] |
| 4 | **Observability Self-Monitoring** | | SRE | |
| | | Agent Operations (AI agent health) | | [ ] |
| | | LLM Cost Center | | [ ] |
| | | Prometheus/Loki/Tempo health | | [ ] |

---

## Fase 4: AI Agents (Semanas 10-12)

### Sprint S4.1 — LLM Infrastructure
**Duração:** 3 dias | **Prioridade:** P2

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **LiteLLM Proxy** | | SRE | |
| | | ECS service + Redis cache | | [ ] |
| | | Multi-model config (Claude + Gemini + DeepSeek) | | [ ] |
| | | Budget controls ($50/mês) | | [ ] |
| | | Prompt caching (Claude) | | [ ] |
| | | Prometheus callback habilitado | | [ ] |
| 2 | **Qdrant** | | SRE | |
| | | ECS service + EFS volume | | [ ] |
| | | Collection: obs_hub_knowledge (RAG) | | [ ] |
| | | Collection: semantic_cache | | [ ] |
| | | Indexar documentação (rag_indexer.py) | | [ ] |

### Sprint S4.2 — AI Assistant (AG-1 → AG-5)
**Duração:** 5 dias | **Prioridade:** P2

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Chainlit Chat** | | SRE | |
| | | ECS service + Cognito OAuth | | [ ] |
| | | app.py (UI) + agent.py (entry point) | | [ ] |
| | | Guardrails (input/output) | | [ ] |
| | | Session history (20 messages) | | [ ] |
| 2 | **AG-2 Multi-Agent** | | SRE | |
| | | Router (Gemini Flash) | | [ ] |
| | | 7 Agents (obs, infra, code, cicd, finops, security, correlator) | | [ ] |
| | | 42 tools across 7 domains | | [ ] |
| | | Shortcuts (regex fast-path) | | [ ] |
| 3 | **AG-5 Claude + MCP** | | SRE | |
| | | orchestrator_ag5.py | | [ ] |
| | | mcp_client.py (MCP SDK) | | [ ] |
| | | 7 MCP servers como sidecars | | [ ] |
| | | Semantic cache integration | | [ ] |
| 4 | **AG-3 Alert Investigation** | | SRE | |
| | | alert_investigator.py | | [ ] |
| | | AlertManager webhook → AG-5 → Slack | | [ ] |
| | | Feature flag: ENABLE_ALERT_INVESTIGATION | | [ ] |

### Sprint S4.3 — MCP Servers
**Duração:** 3-4 dias | **Prioridade:** P2

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **mcp-aws** | 8 tools (ECS, RDS, VPC, Cost, GuardDuty) | | [ ] |
| 2 | **mcp-github** | 13 tools (repos, PRs, commits, workflows) | | [ ] |
| 3 | **mcp-tfc** | 5 tools (workspaces, runs, state, plans) | | [ ] |
| 4 | **mcp-qdrant** | 3 tools (RAG search, semantic cache) | | [ ] |
| 5 | **mcp-grafana** | PromQL, LogQL, TraceQL, dashboards | | [ ] |
| 6 | **mcp-confluence** | 6 tools (create/read/update pages) | | [ ] |
| 7 | **mcp-eraser** | 2 tools (DiagramGPT, diagram-as-code) | | [ ] |

---

## Fase 5: Hardening (Semanas 13-16)

### Sprint S5.1 — Security & RBAC
**Duração:** 5 dias | **Prioridade:** P1

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Cognito SSO** | | SRE | |
| | | User Pool com MFA obrigatório | | [ ] |
| | | Grafana OAuth integration | | [ ] |
| | | Cognito groups → Grafana teams | | [ ] |
| 2 | **RBAC Grafana** | | SRE | |
| | | Folder permissions por team | | [ ] |
| | | Devs: Viewer (só seus dashboards) | | [ ] |
| | | SRE: Editor (Explore habilitado) | | [ ] |
| | | Admin: Full access | | [ ] |
| 3 | **Audit Trail** | | SRE | |
| | | CloudTrail → Loki | | [ ] |
| | | Login events tracking | | [ ] |
| | | API call logging | | [ ] |
| 4 | **WAF hardening** | | SRE | |
| | | IP allowlist automatizado | | [ ] |
| | | Rate limiting rules | | [ ] |
| | | Bot protection | | [ ] |

### Sprint S5.2 — CI/CD & Automation
**Duração:** 3 dias | **Prioridade:** P2

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **GitHub Actions** | | DevOps | |
| | | ecr-sync.yml (auto-build on push) | | [ ] |
| | | Path-based triggers (só build imagem alterada) | | [ ] |
| | | Manual dispatch (workflow_dispatch) | | [ ] |
| 2 | **Slack integrations** | | DevOps | |
| | | GitHub webhooks → Slack (PRs, merges, deploys) | | [ ] |
| | | TFC notifications → Slack (plan/apply) | | [ ] |
| | | Grafana alerts → Slack contact points | | [ ] |

### Sprint S5.3 — Chaos Engineering & DR
**Duração:** 5 dias | **Prioridade:** P2

| # | Task | Subtask | Owner | Status |
|---|------|---------|-------|--------|
| 1 | **Game Days** | | SRE | |
| | | ECS task kill + auto-recovery | | [ ] |
| | | RDS failover test | | [ ] |
| | | Network partition simulation | | [ ] |
| 2 | **Load Testing (k6)** | | SRE | |
| | | Smoke test (baseline) | | [ ] |
| | | Load test (pico normal) | | [ ] |
| | | Stress test (acima do pico) | | [ ] |
| 3 | **Runbooks** | | SRE | |
| | | Incident response procedure | | [ ] |
| | | Escalation matrix | | [ ] |
| | | Per-service runbooks | | [ ] |
| | | Postmortem template | | [ ] |

---

## Fase 6: Advanced (Semanas 17+)

### Sprint S6.1 — LLM Cost & ROI
| # | Task | Status |
|---|------|--------|
| 1 | LiteLLM Prometheus metrics (custo real $) | [ ] |
| 2 | Dashboard: custo por user/team/model | [ ] |
| 3 | Dashboard: ROI (queries resolvidas × custo manual) | [ ] |
| 4 | Thumbs up/down feedback no Chainlit | [ ] |
| 5 | Query history table (PostgreSQL) | [ ] |

### Sprint S6.2 — Documentation Automation
| # | Task | Status |
|---|------|--------|
| 1 | AG-5 + mcp-github + mcp-confluence = doc auto | [ ] |
| 2 | Scanner: para cada repo → lê → analisa → publica | [ ] |
| 3 | Eraser diagrams via mcp-eraser | [ ] |
| 4 | Grafana dashboard: % APIs documentadas | [ ] |

### Sprint S6.3 — LGTM Upgrade
| # | Task | Status |
|---|------|--------|
| 1 | Grafana 11.4 → 12.4 | [ ] |
| 2 | Prometheus 2.54 → 3.10 | [ ] |
| 3 | Loki 2.9 → 3.6 | [ ] |
| 4 | Tempo 2.4 → 2.9 | [ ] |
| 5 | Alloy 1.8 → 1.13 | [ ] |
| 6 | AlertManager 0.27 → 0.31 | [ ] |

### Sprint S6.4 — AG-5 Write Capabilities
| # | Task | Status |
|---|------|--------|
| 1 | GitHub write tools (create PR, commit) | [ ] |
| 2 | Secrets Manager update tool | [ ] |
| 3 | TFC trigger run tool | [ ] |
| 4 | Approval flow (Chainlit ask_user) | [ ] |
| 5 | RBAC for write operations | [ ] |

---

## Métricas de Sucesso

| Métrica | Target | Como medir |
|---------|--------|-----------|
| MTTD (Mean Time to Detect) | < 5 min | Tempo entre problema e alerta |
| MTTR (Mean Time to Recover) | < 30 min | Tempo entre alerta e resolução |
| SLO Compliance | > 99.9% | Error budget remaining |
| Dashboard coverage | 100% Tier 1 services | Dashboards / total services |
| Alert noise ratio | < 5:1 | Alerts / real incidents |
| Toil reduction | > 50% | Horas manuais antes vs depois |
| Cost vs alternatives | > 10x ROI | Custo hub / custo Datadog |

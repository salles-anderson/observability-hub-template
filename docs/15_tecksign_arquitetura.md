# TeckSign - Documentacao Tecnica Completa (DOC-1)

## 1. Visao Geral

TeckSign e uma plataforma de assinatura digital desenvolvida pela Teck Solucoes. Permite upload, assinatura (PAdES + Email-OTP), versionamento e gestao de documentos PDF com compliance LGPD.

### Repositorios

| Repo | Branch | URL |
|------|--------|-----|
| tecksign-api | develop | https://github.com/TeckSolucoes/tecksign-api |
| tecksign-frontend | develop | https://github.com/TeckSolucoes/tecksign-frontend |
| tecksign-infra | main | https://github.com/TeckSolucoes/tecksign-infra |

### Terraform Cloud Workspaces

| Workspace | Camada | URL |
|-----------|--------|-----|
| tecksign-ses-develop | BASE (SES) | https://app.terraform.io/app/TeckSolucoes/workspaces/tecksign-ses-develop |
| tecksign-base-develop | BASE (VPC, RDS, S3, Cognito) | https://app.terraform.io/app/TeckSolucoes/workspaces/tecksign-base-develop |
| tecksign-app-develop | APP (ECS, ALB, Amplify) | https://app.terraform.io/app/TeckSolucoes/workspaces/tecksign-app-develop |

### AWS Account

- **Account ID**: 919739341165 (TeckSolucoes-Dev)
- **Region**: us-east-1
- **Dominio**: *.dev.tecksign.com.br
- **VPC**: vpc-0aaf8d3291bfb0548 (172.19.0.0/16) — vpc-core-infra-dev-vpc

---

## 2. Arquitetura de Servicos

### Stack Tecnologico

| Camada | Tecnologia |
|--------|-----------|
| Frontend | Next.js 16 + React 19 + TailwindCSS 4 + shadcn/ui (Radix) |
| API | NestJS 10 + TypeScript 5.6 + Node.js 20 + pnpm 9 |
| ORM | Prisma 5 (PostgreSQL 17) |
| Auth | AWS Cognito (OIDC/PKCE) + JWT + MFA (TOTP) |
| Storage | S3 (presigned URLs, SSE-KMS) |
| Email | SES via SMTP (Nodemailer + circuit breaker) |
| Queue | Bull (Redis) — notificacoes async |
| Cache | ElastiCache Redis 7.1 (TLS) |
| Document DB | DocumentDB 5.0 (MongoDB-compatible) |
| Sessions | DynamoDB (PAY_PER_REQUEST, TTL) |
| Observability | Fluent Bit (logs→Loki) + ADOT (traces→Tempo, metrics→Prometheus) |
| CI/CD | GitHub Actions + Terraform Cloud + AWS Amplify |

### URLs dos Servicos

| Servico | URL |
|---------|-----|
| Frontend App | https://app.dev.tecksign.com.br |
| Frontend Admin | https://admin.dev.tecksign.com.br |
| API | https://api.dev.tecksign.com.br |
| Cognito Auth | https://authentication.app.dev.tecksign.com.br |
| Swagger Docs | https://api.dev.tecksign.com.br/docs |
| Health Check | https://api.dev.tecksign.com.br/health |
| Metrics | https://api.dev.tecksign.com.br/metrics |

---

## 3. ECS Services

### Cluster: cluster-dev

| Service | Task Def | CPU | Memory | Desired | Running | Auto Scale |
|---------|----------|-----|--------|---------|---------|-----------|
| tecksign-dev-api | :32 | 2048 (2 vCPU) | 4096 MB | 1 | 1 | min:1 max:2 (CPU 70%, Mem 80%) |

### Containers na Task Definition

| Container | Funcao | Porta | Memoria |
|-----------|--------|-------|---------|
| log-router (Fluent Bit) | FireLens → Loki | — | 50 MB |
| adot-collector (ADOT) | OTel → Tempo/Prometheus | 4317 (gRPC), 4318 (HTTP) | 256 MB |
| tecksign-api (Node.js) | API NestJS | 3000 | Restante |

### Health Check
- Path: `/health` (HTTP)
- Interval: 30s, Timeout: 5s, Retries: 3, Grace: 30s
- Readiness: verifica DB + S3

### Observability (Sidecars)
- **Fluent Bit**: log driver `awsfirelens`, output para Loki (`loki.tecksign.local:3100`)
- **ADOT**: auto-instrumentation via `NODE_OPTIONS=--require @opentelemetry/auto-instrumentations-node/register`
- **Labels Loki**: `job=ecs, project=tecksign, environment=dev, service=tecksign-api`
- **Service Name OTel**: `tecksign-api`
- **Exporter**: OTLP HTTP (localhost:4318)

### Environment Variables Injetadas

```
# Cognito
COGNITO_ISSUER=https://cognito-idp.us-east-1.amazonaws.com/{USER_POOL_ID}
COGNITO_JWKS_URI=.../.well-known/jwks.json
COGNITO_CLIENT_ID, COGNITO_ADMIN_CLIENT_ID, COGNITO_DOMAIN

# Database
DATABASE_URL (from Secrets Manager - RDS credentials)
REDIS_URL=rediss://endpoint:6379 (TLS)
DOCUMENTDB_URL (from SSM)
DYNAMODB_TABLE_SESSIONS=tecksign-dev-sessions

# Email
SMTP_HOST=email-smtp.us-east-1.amazonaws.com
SMTP_PORT=587, SMTP_FROM=noreply@dev.tecksign.com.br

# SQS
SQS_QUEUE_URL, SQS_QUEUE_ARN, SQS_REGION=us-east-1

# OpenTelemetry
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SERVICE_NAME=tecksign-api

# CORS
CORS_ORIGINS=https://app.dev.tecksign.com.br,https://admin.dev.tecksign.com.br
```

---

## 4. Databases

### RDS PostgreSQL (principal)
- **Identifier**: tecksign-dev-rds
- **Engine**: PostgreSQL 17.6
- **Instance**: db.t3.micro (20GB gp3)
- **Endpoint**: tecksign-dev-rds.c2ryuk6emrec.us-east-1.rds.amazonaws.com:5432
- **Database**: tecksigndbdev
- **User**: tecksignadmin
- **Encryption**: KMS (alias/tecksign-dev-s3)
- **Multi-AZ**: Nao (dev)
- **Backup**: 7 dias retencao
- **IAM Auth**: Habilitado
- **Credential Rotation**: 30 dias (Lambda)
- **Secret**: tecksign-dev-rds-credentials

### Modelos Prisma (15 tabelas)

| Modelo | Funcao | Relacionamentos |
|--------|--------|----------------|
| Tenant | Multi-tenancy (row-level isolation) | 1:N com User, Document, Recipient, Folder |
| User | Contas + Cognito sync + MFA | cognitoSub, cognitoUsername imutaveis |
| Document | Documentos com status (DRAFT/ACTIVE/ARCHIVED) | 1:N DocumentVersion, Signature |
| DocumentVersion | Snapshots imutaveis + refs S3 + checksums | Pertence a Document |
| Signature | Assinaturas (User ou Recipient) + evidencia | FK Document, User/Recipient |
| SignatureEvidence | Provas imutaveis de assinatura | FK Signature |
| Recipient | Destinatarios externos (sem conta) | Email-based, FK Document |
| EmailOtp | OTP para assinatura (partial unique index) | FK Recipient |
| Folder | Hierarquia de pastas (self-referencing) | FK Tenant, parent Folder |
| Audit | Trail imutavel (tenant-scoped) | Nunca atualizado |
| LgpdConsent | Consentimento versionado (LGPD) | Nunca atualizado |
| Notification | Fila email/SMS | FK Tenant |
| RefreshToken | Lifecycle tokens (TTL cleanup job 02:00) | FK User |
| EmailVerification | Tokens de verificacao email | FK User |
| PhoneOtp | OTP telefone | FK User |

### Padroes de Design
- **Soft delete**: `deletedAt` timestamp (nunca hard delete)
- **Imutabilidade**: Audit, Signatures, Evidence, Consent nunca alterados
- **Multi-tenant**: todas entidades ligadas a `tenantId`
- **Indexes**: otimizados para queries por tenant + status + deletedAt

### ElastiCache Redis
- **Identifier**: tecksign-dev-redis-001
- **Engine**: Redis 7.1
- **Instance**: cache.t3.micro (1 node)
- **Encryption**: at-rest + transit (TLS, `rediss://`)
- **Auth**: Token-based
- **Uso**: Cache, rate limiting, Bull queue, sessions

### DocumentDB
- **Cluster**: tecksign-dev-docdb-01
- **Engine**: MongoDB-compatible 5.0
- **Instance**: db.t3.medium
- **Encryption**: AES-256 KMS
- **Backup**: 7 dias
- **Uso**: Document storage, complex objects

### DynamoDB
- **Table**: tecksign-dev-sessions
- **Billing**: PAY_PER_REQUEST
- **Keys**: pk (String) + sk (String)
- **TTL**: Habilitado (attribute: `ttl`)
- **PITR**: Habilitado
- **Uso**: Sessions (TTL-based cleanup)

---

## 5. API — Modulos e Endpoints

### Modulos NestJS (22 modulos)

#### Auth (`/auth`)
- `POST /auth/register` — Registro
- `POST /auth/login` — Login (retorna JWT + flag MFA)
- `POST /auth/refresh` — Refresh token
- `POST /auth/logout` — Logout
- `GET /auth/me` — Perfil do usuario
- `POST /auth/2fa/verify` — Verificacao OTP (MFA)
- `POST /auth/verify-email/request` — Solicitar verificacao email
- `POST /auth/verify-email/confirm` — Confirmar token
- `POST /auth/verify-phone/request` — Solicitar OTP telefone
- `POST /auth/verify-phone/confirm` — Confirmar OTP
- `POST /auth/mfa/setup` — Gerar TOTP secret
- `POST /auth/mfa/enable` — Habilitar MFA
- `POST /auth/mfa/verify` — Verificar TOTP
- `POST /auth/callback` — OAuth2 callback (Cognito)
- `GET /auth/session` — Info sessao

#### Documents (`/documents`)
- `POST /documents/presign` — Presigned URL para upload S3
- `POST /documents/finalize` — Finalizar upload (valida checksum SHA256)
- `POST /documents/download` — Presigned URL para download
- `POST /documents/signatures` — Listar assinaturas (paginado)
- `POST /documents/signed-url` — URL temporaria
- `GET /documents` — Listar documentos (paginado, filtrado)
- `GET /documents/:id` — Detalhes + versoes
- `DELETE /documents/:id` — Soft delete
- `PUT /documents/:id/metadata` — Atualizar metadata (JSON)
- `PUT /documents/:id/folder` — Mover para pasta
- `POST /documents/chunking/init` — Iniciar upload chunked
- `POST /documents/chunking/presign-chunk` — Presigned por chunk
- `POST /documents/chunking/complete` — Finalizar chunked

#### Sign (`/sign`)
- `POST /sign/pades` — Assinatura digital PAdES (requer cert P12)
- `POST /sign/email-otp` — Assinatura via Email OTP

#### Public Sign (`/public/sign/:token`)
- `GET /public/sign/:token` — Dados da pagina de assinatura
- `GET /public/sign/:token/document` — Buscar documento
- `GET /public/sign/:token/signed-document` — Download PDF assinado
- `POST /public/sign/:token/confirm-data` — Confirmar dados do assinante
- `POST /public/sign/:token/viewed` — Marcar como visualizado
- `POST /public/sign/:token/sign` — Assinar
- `POST /public/sign/:token/decline` — Recusar

#### Partners (`/api/v1/partners`) — NOVO (IA-800/801/802)
- `GET /api/v1/partners/ping` — Health check parceiro
- `POST /api/v1/partners/documents` — Presign upload (API Key + idempotencia)
- `POST /api/v1/partners/documents/finalize` — Finalizar upload (SHA256)

Auth: API Key (header), cache de idempotencia, validacao MIME (PDF only), max 100MB.

#### Recipients (`/recipients`)
- `POST /recipients` — Adicionar destinatario
- `POST /recipients/:id/otp/send` — Enviar OTP email
- `POST /recipients/:id/otp/verify` — Verificar OTP

#### Users (`/users`)
- `POST /users` — Criar usuario (admin)
- `PATCH /users/:id` — Atualizar
- `POST /users/:id/disable` — Desabilitar (Cognito)
- `DELETE /users/:id` — Deletar permanente

#### Folders (`/folders`)
- `POST /folders` — Criar pasta
- `GET /folders` — Listar (paginado)
- `GET /folders/:id` — Detalhes
- `PUT /folders/:id` — Atualizar
- `DELETE /folders/:id` — Soft delete

#### Outros
- `POST /consent/accept` — Aceitar consentimento LGPD
- `GET /audit/export` — Exportar audit trail (JSON)
- `POST /webhooks/ses` — Receber eventos SES (bounce/complaint/delivery)
- `GET /health` / `GET /health/liveness` / `GET /health/readiness` — Health checks
- `GET /metrics` — Prometheus metrics
- `GET /` — Info API (versao, commit SHA)

---

## 6. Frontend

### Stack
- **Framework**: Next.js 16 (App Router) + React 19
- **UI**: shadcn/ui + Radix UI + TailwindCSS 4
- **PDF**: pdfjs-dist 5.4 (Mozilla PDF.js)
- **Temas**: next-themes (dark/light)
- **Deploy**: AWS Amplify Hosting
- **Testes**: Vitest + React Testing Library

### Rotas

| Rota | Tipo | Funcao |
|------|------|--------|
| `/login` | Publica | Email/password + SSO Cognito |
| `/register` | Publica | Registro de usuario |
| `/s/assinatura/:token` | Publica | Portal de assinatura para destinatarios |
| `/s/assinatura/:token/assinar` | Publica | Tela de assinatura |
| `/s/assinatura/:token/visualizar` | Publica | Visualizar documento |
| `/s/assinatura/:token/concluido` | Publica | Confirmacao pos-assinatura |
| `/auth/callback` | Especial | Callback OAuth2 Cognito |
| `/dashboard` | Protegida | Dashboard + lista documentos |
| `/uploadDocument` | Protegida | Upload de PDF |
| `/previewDocument` | Protegida | Preview + validacao |
| `/signature` | Protegida | Assinatura interna |
| `/send` | Protegida | Envio para assinatura externa |

### Auth Frontend
- **Local**: email/password → JWT → localStorage (`tecksign_auth_token`)
- **SSO**: Cognito Hosted UI (Authorization Code + PKCE)
- **Admin**: subdomain `admin.dev.tecksign.com.br` (client ID separado)
- **Tokens Cognito**: `tecksign_cognito_id_token`, `tecksign_cognito_refresh_token`

### API Client
- Fetch nativo com timeout 30s
- Bearer token injection automatico
- Tenant ID header (`X-Tenant-Id`)
- Error handling com mensagens amigaveis (status code mapping)
- Mock fallback para dev sem backend (`NEXT_PUBLIC_ENABLE_MOCKS=true`)

---

## 7. Infraestrutura AWS

### Networking
- **VPC**: vpc-0aaf8d3291bfb0548 (172.19.0.0/16)
- **Subnets publicas**: 2 (AZ-1, AZ-2) — ALB
- **Subnets privadas**: 2 (AZ-1, AZ-2) — ECS, RDS, Redis, DocDB
- **Cloud Map**: `tecksign.local` (DNS privado, namespace ns-syyxvjgzqjzfpykv)

### Load Balancer
- **ALB**: tecksign-dev-alb (internet-facing, active)
- **DNS**: tecksign-dev-alb-779462026.us-east-1.elb.amazonaws.com
- **Listeners**: HTTPS 443 (ACM cert) + HTTP 80 (redirect 301)
- **Target Group**: HTTP 3000, health path `/health`, matcher 200-399
- **Access Logs**: S3 bucket `tecksign-dev-alb-logs`

### Security Groups

| SG | Regras Inbound |
|----|---------------|
| ALB | 0.0.0.0/0:80, 0.0.0.0/0:443 |
| ECS | ALB→3000, Kong (172.29.0.0/16)→3000 |
| RDS | ECS→5432, Bastion→5432 |
| Redis | ECS→6379 |
| DocumentDB | ECS→27017 |

### S3 Buckets

| Bucket | Funcao | Encryption | Versionamento |
|--------|--------|-----------|--------------|
| tecksign-dev | Documentos | KMS (alias/tecksign-dev-s3) | Sim |
| tecksign-dev-manifests | Audit WORM (7 anos retencao) | KMS (manifest-signing) | Locked |
| tecksign-dev-kyc-photos | Biometric (90 dias TTL) | KMS (kyc-biometric) | Sim |
| tecksign-dev-alb-logs | Access logs ALB | — | — |

### KMS Keys

| Alias | Funcao |
|-------|--------|
| alias/tecksign-dev-s3 | Documentos S3 |
| alias/tecksign-dev-manifest-signing | Audit WORM |
| alias/tecksign-dev-kyc-biometric | KYC PII |

### Cognito
- **User Pool**: tecksign-dev-user-pool (us-east-1_h2duuIgYl)
- **Custom Domain**: authentication.app.dev.tecksign.com.br
- **MFA**: TOTP habilitado
- **Access Token TTL**: 60 min
- **Refresh Token TTL**: 30 dias
- **Admin Token TTL**: 30 min (shorter)
- **Pre-signup**: Lambda (email domain whitelist)

### SQS
- **Queue**: tecksign-dev-events (Standard)
- **DLQ**: tecksign-dev-events-dlq (5 retries, 14d retention)
- **Message retention**: 4 dias
- **Visibility timeout**: 60s
- **Long polling**: 10s

### Secrets Manager

| Secret | Funcao | Rotacao |
|--------|--------|---------|
| tecksign/dev/app-env | JWT, S3, configs | Manual |
| tecksign-dev-rds-credentials | RDS user/pass | 30 dias (Lambda) |
| tecksign/dev/ses-smtp | SMTP credentials | Manual |
| tecksign-dev-facetec-credentials | KYC FaceTec keys | Manual |

### ECR
- **Repository**: tecksign-backend-api-dev
- **Scan on push**: Sim (vulnerability scan)
- **Tag**: latest + commit SHA

### Amplify
- **App**: tecksign-dev-frontend (d2zfk03tftbkv8)
- **Repo**: TeckSolucoes/tecksign-frontend
- **Branch**: develop
- **Domains**: app.dev.tecksign.com.br, admin.dev.tecksign.com.br

### Route53 DNS

| Record | Destino |
|--------|---------|
| api.dev.tecksign.com.br | ALB (Alias A/AAAA) |
| app.dev.tecksign.com.br | Amplify (CNAME) |
| admin.dev.tecksign.com.br | Amplify (CNAME) |
| authentication.app.dev.tecksign.com.br | Cognito Custom Domain (A) |

---

## 8. CI/CD Pipelines

### API — GitHub Actions

#### ci.yml (PR + push main/develop)
1. Lint (ESLint)
2. Typecheck (tsc --noEmit)
3. Test:unit (Vitest, cobertura >= 25%)
4. Build (NestJS)
5. SonarQube scan (se SONAR_TOKEN configurado)
6. E2E separado: PostgreSQL + Redis + MinIO → migrate → test:e2e

#### deploy-develop.yml (Manual / pos-CI)
1. AWS credentials (secrets)
2. ECR login + Docker build (commit SHA + latest)
3. Push ECR (919739341165)
4. Run DB migration (ECS one-off task)
5. Force new deployment (ECS update-service)

### Frontend — GitHub Actions + Amplify

#### ci.yml (PR + push main/develop)
1. Lint + Typecheck + Test:coverage + Build + SonarQube

#### Amplify (auto)
- Push develop → pnpm build → deploy CloudFront

### Infra — Terraform Cloud
- VCS-driven: push → plan, merge main → apply

### Ordem de Deploy
```
1. tecksign-ses-develop    (SES + Lambda credentials)
2. tecksign-base-develop   (VPC, RDS, S3, Cognito, Redis, DynamoDB, DocumentDB)
3. tecksign-app-develop    (ECS, ALB, Amplify, SQS, Cloud Map)
```

---

## 9. Seguranca e Compliance

| Aspecto | Implementacao |
|---------|--------------|
| Encryption at rest | KMS: S3, RDS, DynamoDB, DocumentDB, Manifests |
| Encryption in transit | TLS 1.2+: ALB, Redis (rediss://), HTTPS |
| Auth | Cognito MFA (TOTP) + JWT (15min TTL) + refresh (7d) |
| Rate limiting | OTP multi-nivel (min/hora/dia/tenant) |
| LGPD | Consentimento versionado, retencao automatica, KYC 90d TTL |
| Audit | Trail imutavel + S3 WORM (7 anos, object lock) |
| Secrets | Secrets Manager + SSM (rotacao 30d RDS) |
| Security headers | Helmet.js (CSP, X-Frame, etc.) |
| CORS | Restrito por origins (app + admin subdomains) |
| Input validation | class-validator (NestJS decorators) |
| Idempotencia | S3 uploads + Partners API (64-char hex key) |
| Circuit breaker | SMTP (3 falhas → 30s timeout, retry exponencial) |
| Soft delete | Nunca hard delete (deletedAt timestamp) |
| Image scan | ECR scan on push (vulnerability detection) |

---

## 10. Integracao com Observability Hub

### Fluxo de Dados

```
tecksign-dev-api (ECS)
  ├── Fluent Bit (FireLens) ──→ Loki (Hub: loki.observability.local:3100)
  │     Labels: project=tecksign, service=tecksign-api, environment=dev
  ├── ADOT Collector ──→ Tempo (Hub: traces)
  │     Service: tecksign-api, Protocol: OTLP HTTP
  └── ADOT Collector ──→ Prometheus (Hub: metrics)
        Service: tecksign-api
```

### Grafana (Hub)
- **Projeto**: tecksign (label `project="tecksign"`)
- **Logs**: Loki query `{project="tecksign", service="tecksign-api-dev"}`
- **Traces**: Tempo by service.name `tecksign-api`
- **Metricas**: Prometheus scrape via remote write (ADOT)
- **Dashboards**: existentes no Hub para TeckSign

### Alertas
- Cobertura parcial (apenas TeckSign DEV configurado)
- Expansao necessaria para prod

---

## 11. Outros Projetos na Mesma Conta

A conta TeckSolucoes-Dev (919739341165) tambem hospeda o projeto **Gestao Cartao**:

| Recurso | TeckSign | Gestao Cartao |
|---------|----------|--------------|
| ECS Services | 1 (tecksign-dev-api) | 3 (proposta-api, proposta-worker, web-api) |
| RDS | tecksign-dev-rds (PG 17) | gestao-cartao (PG 16) |
| ECR | 1 repo | 4 repos |
| S3 | 4 buckets | 1 bucket |
| Cognito | tecksign-dev-user-pool | gestao-cartao-front-user-pool |
| SQS | 1 queue + DLQ | 3 queues + DLQs (1 FIFO) |
| Amplify | 1 app | 1 app |
| Secrets | 4 secrets | 4 secrets |

---

## 12. KYC / FaceTech / Rekognition

### Status
- **Infra provisionada**: S3 bucket (tecksign-dev-kyc-photos), KMS key (kyc-biometric), IAM Rekognition permissions
- **FaceTec**: secrets no Secrets Manager (license key, production key, device key, public encryption key)
- **Aguardando**: time de desenvolvimento informar pendencias e conclusao do FaceTech
- **Proximo passo**: integracao com AWS Rekognition (CompareFaces, DetectFaces, DetectText, DetectLabels)
- **TTL**: 90 dias para fotos biometricas (LGPD compliance)

---

## 13. Dependencias Criticas

### API (principais)
- `@nestjs/*` (10 packages) — framework
- `@prisma/client` — ORM PostgreSQL
- `jose`, `passport`, `argon2` — auth/crypto
- `@aws-sdk/client-s3`, `@aws-sdk/client-cognito-identity-provider`, `@aws-sdk/client-ses` — AWS
- `pdf-lib`, `node-signpdf`, `node-forge` — assinatura digital
- `pino`, `prom-client`, `@opentelemetry/*` — observability
- `bull` — queue (Redis)
- `nodemailer` — email
- `otplib` — MFA TOTP
- `helmet` — security headers

### Frontend (principais)
- `next` 16.0.1, `react` 19.2.0
- `@radix-ui/*` (5 packages) — UI primitives
- `tailwindcss` 4, `tailwind-merge`, `clsx`, `class-variance-authority`
- `pdfjs-dist` 5.4 — renderizacao PDF
- `next-themes` — dark/light mode
- `lucide-react` — icons

# TeckSign - Troubleshooting e Runbooks Operacionais

## 1. Health Checks e Diagnostico Rapido

### Verificar se API esta saudavel
```bash
curl -s https://api.dev.tecksign.com.br/health | jq
curl -s https://api.dev.tecksign.com.br/health/readiness | jq  # verifica DB + S3
curl -s https://api.dev.tecksign.com.br/health/liveness | jq
```

### Verificar ECS service
```bash
export AWS_PROFILE=TeckSolucoes-Dev
aws ecs describe-services --cluster cluster-dev --services tecksign-dev-api \
  --query 'services[0].{Status:status,Desired:desiredCount,Running:runningCount,Pending:pendingCount,Events:events[:3]}' \
  --region us-east-1
```

### Verificar logs recentes (CloudWatch)
```bash
aws logs tail /ecs/cluster-dev --since 30m --filter-pattern "ERROR" --region us-east-1
```

### Verificar via Grafana (Loki)
```
{project="tecksign", service="tecksign-api-dev"} |= "error" | json
```

---

## 2. Problemas Comuns

### 2.1 API retorna 502/503 (Bad Gateway / Service Unavailable)

**Causa provavel**: ECS task nao esta saudavel ou ALB health check falhando.

**Diagnostico**:
```bash
# Verificar tasks rodando
aws ecs list-tasks --cluster cluster-dev --service-name tecksign-dev-api --region us-east-1

# Verificar stopped tasks (ultimas falhas)
aws ecs list-tasks --cluster cluster-dev --service-name tecksign-dev-api --desired-status STOPPED --region us-east-1

# Detalhes da task parada
aws ecs describe-tasks --cluster cluster-dev --tasks <TASK_ARN> --query 'tasks[0].{StopCode:stopCode,StopReason:stoppedReason,Containers:containers[*].{Name:name,ExitCode:exitCode,Reason:reason}}' --region us-east-1

# Verificar target health no ALB
aws elbv2 describe-target-health --target-group-arn <TG_ARN> --region us-east-1
```

**Resolucao**:
1. Se task parada por OOM: aumentar memoria na task definition
2. Se health check falhando: verificar `/health` endpoint e dependencias (DB, S3)
3. Force new deployment: `aws ecs update-service --cluster cluster-dev --service tecksign-dev-api --force-new-deployment --region us-east-1`

### 2.2 Conexao com RDS falhando

**Causa provavel**: credentials expiradas, security group, ou RDS indisponivel.

**Diagnostico**:
```bash
# Verificar status RDS
aws rds describe-db-instances --db-instance-identifier tecksign-dev-rds \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}' --region us-east-1

# Verificar secret de credentials (ultima rotacao)
aws secretsmanager describe-secret --secret-id tecksign-dev-rds-credentials \
  --query '{LastRotated:LastRotatedDate,NextRotation:NextRotationDate}' --region us-east-1

# Testar conectividade via ECS Exec
aws ecs execute-command --cluster cluster-dev --task <TASK_ID> --container tecksign-api \
  --interactive --command "node -e \"const { PrismaClient } = require('@prisma/client'); new PrismaClient().\$connect().then(() => console.log('DB OK')).catch(e => console.error(e))\"" --region us-east-1
```

**Resolucao**:
1. Se credentials rotacionadas: forcar novo deploy (task pega novo secret)
2. Se SG bloqueando: verificar regra ECS→5432 no RDS SG
3. Se RDS down: verificar events `aws rds describe-events --source-identifier tecksign-dev-rds`

### 2.3 Sidecar Fluent Bit nao inicia

**Sintoma**: Container `log-router` em estado STOPPED, logs nao chegam ao Loki.

**Diagnostico**:
```bash
# Verificar status dos containers na task
aws ecs describe-tasks --cluster cluster-dev --tasks <TASK_ARN> \
  --query 'tasks[0].containers[*].{Name:name,Status:lastStatus,ExitCode:exitCode,Reason:reason}' --region us-east-1

# Logs do Fluent Bit (CloudWatch, nao Loki)
aws logs tail /ecs/tecksign-dev/log-router --since 15m --region us-east-1
```

**Resolucao**:
1. Verificar config do FireLens em `/fluent-bit/configs/parse-json.conf`
2. Verificar se Loki esta acessivel: `loki.tecksign.local:3100`
3. Se OOM (exit code 137): aumentar memoria reservada (atualmente 50MB)

### 2.4 Sidecar ADOT nao inicia ou traces nao chegam

**Sintoma**: Container `adot-collector` unhealthy, traces ausentes no Tempo.

**Diagnostico**:
```bash
# Logs do ADOT
aws logs tail /ecs/tecksign-dev/adot-collector --since 15m --region us-east-1

# Health check ADOT
aws ecs execute-command --cluster cluster-dev --task <TASK_ID> --container tecksign-api \
  --interactive --command "curl -s http://localhost:4318/healthcheck" --region us-east-1
```

**Resolucao**:
1. Verificar `AOT_CONFIG_CONTENT` env var na task definition
2. ADOT depende de conectividade com Hub (Tempo endpoint)
3. Se ADOT falha, API continua funcionando (sidecar nao e essential)

### 2.5 Upload S3 falhando (presign 500)

**Sintoma**: Erro ao fazer upload de documento, presigned URL nao gerada.

**Diagnostico**:
```bash
# Verificar acesso ao bucket
aws ecs execute-command --cluster cluster-dev --task <TASK_ID> --container tecksign-api \
  --interactive --command "node -e \"const { S3Client, ListBucketsCommand } = require('@aws-sdk/client-s3'); new S3Client({}).send(new ListBucketsCommand({})).then(r => console.log(r.Buckets.map(b => b.Name)))\"" --region us-east-1

# Verificar KMS key
aws kms describe-key --key-id alias/tecksign-dev-s3 --region us-east-1 --query 'KeyMetadata.{Status:KeyState,Enabled:Enabled}'
```

**Resolucao**:
1. Verificar IAM role da task tem permissao S3 + KMS
2. Verificar se bucket existe: `aws s3 ls tecksign-dev`
3. Verificar CORS no S3 (presigned PUT do browser precisa CORS)
4. Ver doc detalhado: `docs/DIAGNOSTICO-PRESIGN-500.md` no repo API

### 2.6 Emails nao sendo enviados (SMTP/SES)

**Sintoma**: OTP nao chega, convites nao enviados, notificacoes perdidas.

**Diagnostico**:
```bash
# Verificar SES sending stats
aws sesv2 get-account --region us-east-1 --query '{SendingEnabled:SendingEnabled,ProductionAccess:ProductionAccessEnabled}'

# Verificar identidade SES
aws sesv2 get-email-identity --email-identity dev.tecksign.com.br --region us-east-1 --query '{Verified:VerifiedForSendingStatus}'

# Verificar Bull queue (se habilitada)
# Via ECS Exec no container
```

**Resolucao**:
1. Circuit breaker pode estar aberto (3 falhas SMTP → 30s timeout). Aguardar ou restartar task
2. SES em sandbox: so envia para emails verificados. Solicitar production access
3. Verificar SMTP credentials em `tecksign/dev/ses-smtp`
4. Verificar bounce/complaint via webhook SES (`/webhooks/ses`)

### 2.7 Cognito login falhando

**Sintoma**: Erro no login SSO, callback nao funciona.

**Diagnostico**:
```bash
# Verificar User Pool
aws cognito-idp describe-user-pool --user-pool-id us-east-1_h2duuIgYl \
  --query 'UserPool.{Status:Status,MFA:MfaConfiguration,Domain:Domain}' --region us-east-1

# Verificar app client
aws cognito-idp describe-user-pool-client --user-pool-id us-east-1_h2duuIgYl \
  --client-id <CLIENT_ID> --query 'UserPoolClient.{CallbackURLs:CallbackURLs,LogoutURLs:LogoutURLs}' --region us-east-1
```

**Resolucao**:
1. Verificar se callback URL esta correto no Cognito (deve ser `https://app.dev.tecksign.com.br/auth/callback`)
2. Verificar se custom domain (`authentication.app.dev.tecksign.com.br`) resolve
3. Verificar ACM certificate associado ao Cognito domain

### 2.8 Rate limiting bloqueando OTP

**Sintoma**: Erro "Too many requests" ao solicitar OTP.

**Causa**: Rate limiting multi-nivel:
- Cooldown: 8s entre requests
- Max per minute: 5
- Max per hour: 15
- Max per day: 40
- Max per tenant/day: 400

**Resolucao**:
1. Aguardar cooldown period
2. Em dev: setar `OTP_RATE_LIMIT_BYPASS_DEV=true` (NAO usar em prod)
3. Verificar se Redis esta acessivel (rate limiter depende de Redis)

---

## 3. Runbooks Operacionais

### 3.1 Restart Service (zero downtime)
```bash
export AWS_PROFILE=TeckSolucoes-Dev
aws ecs update-service --cluster cluster-dev --service tecksign-dev-api \
  --force-new-deployment --region us-east-1
```
Nota: auto scaling min=1, max=2. Novo task inicia antes do antigo parar.

### 3.2 Rollback para versao anterior
```bash
# Listar task definitions
aws ecs list-task-definitions --family-prefix tecksign-dev-api --sort DESC --max-items 5 --region us-east-1

# Usar revisao anterior
aws ecs update-service --cluster cluster-dev --service tecksign-dev-api \
  --task-definition tecksign-dev-api:<REVISAO_ANTERIOR> --region us-east-1
```

### 3.3 Scale up/down
```bash
# Scale up para 2 instancias
aws ecs update-service --cluster cluster-dev --service tecksign-dev-api \
  --desired-count 2 --region us-east-1

# Scale down para 1
aws ecs update-service --cluster cluster-dev --service tecksign-dev-api \
  --desired-count 1 --region us-east-1
```

### 3.4 Executar migration de banco
```bash
# Via ECS Exec
aws ecs execute-command --cluster cluster-dev --task <TASK_ID> --container tecksign-api \
  --interactive --command "npx prisma migrate deploy" --region us-east-1
```

### 3.5 ECS Exec (acesso ao container)
```bash
# Listar tasks ativas
TASK_ID=$(aws ecs list-tasks --cluster cluster-dev --service-name tecksign-dev-api \
  --query 'taskArns[0]' --output text --region us-east-1)

# Conectar ao container
aws ecs execute-command --cluster cluster-dev --task $TASK_ID --container tecksign-api \
  --interactive --command "/bin/sh" --region us-east-1
```

### 3.6 Verificar Redis
```bash
# Via ECS Exec
aws ecs execute-command --cluster cluster-dev --task <TASK_ID> --container tecksign-api \
  --interactive --command "node -e \"const Redis = require('ioredis'); const r = new Redis(process.env.REDIS_URL); r.ping().then(console.log).catch(console.error)\"" --region us-east-1
```

### 3.7 Rotacao manual de credentials RDS
```bash
aws secretsmanager rotate-secret --secret-id tecksign-dev-rds-credentials --region us-east-1
# Apos rotacao, forcar novo deploy do ECS para pegar novo secret
```

### 3.8 Verificar filas SQS (mensagens presas)
```bash
# Verificar mensagens na fila
aws sqs get-queue-attributes --queue-url https://sqs.us-east-1.amazonaws.com/919739341165/tecksign-dev-events \
  --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible \
  --region us-east-1

# Verificar DLQ
aws sqs get-queue-attributes --queue-url https://sqs.us-east-1.amazonaws.com/919739341165/tecksign-dev-events-dlq \
  --attribute-names ApproximateNumberOfMessages --region us-east-1
```

### 3.9 Limpar tokens expirados (manual)
O job automatico roda as 02:00 AM. Para executar manualmente:
```bash
aws ecs execute-command --cluster cluster-dev --task <TASK_ID> --container tecksign-api \
  --interactive --command "node -e \"const { PrismaClient } = require('@prisma/client'); const p = new PrismaClient(); p.refreshToken.deleteMany({where:{expiresAt:{lt:new Date()}}}).then(r => console.log('Deleted:', r.count))\"" --region us-east-1
```

---

## 4. Metricas e Alertas

### Metricas Prometheus expostas (/metrics)
- `http_request_duration_seconds` — latencia por rota
- `http_requests_total` — total requests por status/method/route
- `prisma_query_duration_seconds` — latencia queries DB
- `s3_operation_duration_seconds` — latencia operacoes S3
- `smtp_send_total` — emails enviados (success/failure)
- `bull_queue_jobs_total` — jobs processados
- `node_*` — metricas Node.js (heap, event loop, GC)

### Queries Loki uteis
```
# Erros da API
{project="tecksign"} |= "error" | json | level="error"

# Requests lentas (>5s)
{project="tecksign"} | json | responseTime > 5000

# Falhas de email
{project="tecksign"} |= "smtp" |= "error"

# Auth failures
{project="tecksign"} |= "auth" |= "unauthorized"

# Partner API calls
{project="tecksign"} |= "partner_document"
```

### Alertas sugeridos (a implementar)
- API health check falhando > 5min
- Error rate > 5% (5xx)
- Latencia p95 > 3s
- DLQ com mensagens > 10
- RDS connections > 80%
- Redis memory > 80%
- ECS task restarts > 3 em 15min

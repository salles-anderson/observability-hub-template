# -----------------------------------------------------------------------------
# Import blocks (strangler) — adoção dos recursos do "cimento" de segurança
# -----------------------------------------------------------------------------
# O workspace hub-foundation-security ASSUME os recursos já criados pelo monolito
# teck-observability-hub-prod (state serial 442), SEM recriar.
# Resultado esperado no `terraform plan` (TFC): SÓ imports, ZERO create/destroy/replace.
#
# Fonte dos endereços+IDs: extraído read-only do state do build (serial 442) e
# verificado contra a AWS. Ver docs/plans/2026-06-14-sprint2-import-ids-gabarito.md.
#
# Total: 30 instâncias
#   KMS:     2  (key + alias[0])
#   SGs:     5  (alb, ecs_tasks, efs[0], rds, redis[0])
#   IAM:    14  (2 roles + 11 inline policies + 1 attachment)
#   secrets: 9  (SSM SecureString; sonarqube_token count=0 = NÃO importado)
#
# NÃO importar (ficam no build / fora do cimento):
#   - data.aws_ssm_parameter.grafana_admin_password (mode=data, é leitura)
#   - aws_ssm_parameter.chainlit_auth_secret / cognito_prov_* (vão p/ chainlit/S5)
#   - aws_ssm_parameter.sonarqube_token (count=0 em prod, var vazia)
#   - random_password.* (eliminados; db/admin password agora via var sensível)
# -----------------------------------------------------------------------------

# ---------- KMS ----------
import {
  to = module.kms.aws_kms_key.this
  id = "a248adde-1aeb-4272-b5b7-02f2b3764593"
}
import {
  to = module.kms.aws_kms_alias.this[0]
  id = "alias/teck-obs-hub-prod"
}

# ---------- Security Groups ----------
import {
  to = module.alb_sg.aws_security_group.this
  id = "sg-00000000000000001"
}
import {
  to = module.ecs_tasks_sg.aws_security_group.this
  id = "sg-00000000000000002"
}
import {
  to = module.efs_sg[0].aws_security_group.this
  id = "sg-00000000000000003"
}
import {
  to = module.rds_sg.aws_security_group.this
  id = "sg-00000000000000004"
}
import {
  to = module.redis_sg[0].aws_security_group.this
  id = "sg-00000000000000005"
}

# ---------- IAM Roles ----------
import {
  to = aws_iam_role.ecs_task_execution
  id = "teck-obs-hub-prod-ecs-task-execution-role"
}
import {
  to = aws_iam_role.ecs_task
  id = "teck-obs-hub-prod-ecs-task-role"
}

# ---------- IAM Role Policy Attachment (managed) ----------
# Formato de import: <role_name>/<policy_arn> (NÃO o id gerado do state).
import {
  to = aws_iam_role_policy_attachment.ecs_task_execution
  id = "teck-obs-hub-prod-ecs-task-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ---------- IAM Inline Policies (formato <role_name>:<policy_name>) ----------
import {
  to = aws_iam_role_policy.ecs_task_execution_ssm
  id = "teck-obs-hub-prod-ecs-task-execution-role:teck-obs-hub-prod-ecs-task-execution-ssm-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_s3
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-ecs-task-s3-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_kms
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-ecs-task-kms-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_logs
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-ecs-task-logs-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_cloudwatch
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-ecs-task-cloudwatch-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_efs
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-ecs-task-efs-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_ssm
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-ecs-task-ssm-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_cross_account[0]
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-mcp-cross-account-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_hub_readonly
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-mcp-hub-readonly-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_bedrock[0]
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-ecs-task-bedrock-policy"
}
import {
  to = aws_iam_role_policy.ecs_task_skills_s3
  id = "teck-obs-hub-prod-ecs-task-role:teck-obs-hub-prod-ecs-task-skills-s3-policy"
}

# ---------- Secrets (SSM SecureString) — DES-ESCOPADOS do S2 ----------
# Os 9 SSM SecureString foram importados no Gate #1, mas DEPOIS de-escopados:
# são consumidos por ~17 task-defs do build + a master pw do RDS (random_password),
# então ficam sob gestão do BUILD e migram com seus serviços na S5.
# Os `removed` blocks abaixo soltam (forget, destroy=false) os 9 do state do ws
# security SEM destruir o recurso real — o build segue sendo o dono.
removed {
  from = aws_ssm_parameter.observability_db_password
  lifecycle { destroy = false }
}
removed {
  from = aws_ssm_parameter.grafana_admin_password
  lifecycle { destroy = false }
}
removed {
  from = aws_ssm_parameter.anthropic_api_key
  lifecycle { destroy = false }
}
removed {
  from = aws_ssm_parameter.gemini_api_key
  lifecycle { destroy = false }
}
removed {
  from = aws_ssm_parameter.deepseek_api_key
  lifecycle { destroy = false }
}
removed {
  from = aws_ssm_parameter.grafana_sa_token
  lifecycle { destroy = false }
}
removed {
  from = aws_ssm_parameter.anthropic_api_key_agent
  lifecycle { destroy = false }
}
removed {
  from = aws_ssm_parameter.tfc_api_token
  lifecycle { destroy = false }
}
removed {
  from = aws_ssm_parameter.github_token
  lifecycle { destroy = false }
}

# -----------------------------------------------------------------------------
# AG-5 Agent Skills — bucket dedicado
#
# Ver docs/plans/2026-06-10-ag5-agent-skills-design.md.
# Bucket DEDICADO (não reusa module.s3_bucket) de propósito: aquele bucket tem
# uma lifecycle rule default (prefix="") que expira QUALQUER objeto em 30 dias —
# deletaria os runbooks. Aqui lifecycle_rule_enabled=false → conteúdo durável.
#
# DECOMPOSICAO (strangler): SO o bucket (module.skills_bucket) migra para o
# workspace hub-foundation-data. O upload dos SKILL.md (aws_s3_object.superpowers
# / aws_s3_object.runbooks) PERMANECE no build — sao conteudo/CI que dependem de
# filemd5() sobre a arvore de arquivos do repo (.claude/skills/** e
# docker/chainlit-chat/skills_runbooks/**, paths relativos ../../../ ao build) e
# referenciam o bucket via o output deste workspace. A policy IAM
# (aws_iam_role_policy.ecs_task_skills_s3) ja migrou para hub-foundation-security
# na S2 (ecs_task role transversal).
# -----------------------------------------------------------------------------

module "skills_bucket" {
  source = "git@github.com:YourOrg/terraform-aws-modules.git//modules/storage/s3-bucket?ref=v20260123110212-6e54d81"

  bucket_name            = "${local.name_prefix}-skills"
  versioning_enabled     = true
  force_ssl              = true
  lifecycle_rule_enabled = false # conteúdo durável — NÃO expira

  tags = local.tags
}

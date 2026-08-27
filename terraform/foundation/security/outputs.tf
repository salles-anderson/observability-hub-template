# =============================================================================
# Outputs do cimento — consumidos pelos demais workspaces via terraform_remote_state.
# =============================================================================
output "kms_key_arn" { value = module.kms.key_arn }
output "kms_key_id" { value = module.kms.key_id }
output "alb_sg_id" { value = module.alb_sg.id }
output "ecs_tasks_sg_id" { value = module.ecs_tasks_sg.id }
output "efs_sg_id" { value = try(module.efs_sg[0].id, null) }
output "rds_sg_id" { value = module.rds_sg.id }
output "redis_sg_id" { value = try(module.redis_sg[0].id, null) }
output "ecs_task_execution_role_arn" { value = aws_iam_role.ecs_task_execution.arn }
output "ecs_task_role_arn" { value = aws_iam_role.ecs_task.arn }

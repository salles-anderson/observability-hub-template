# -----------------------------------------------------------------------------
# Application Load Balancer
# -----------------------------------------------------------------------------
module "alb" {
  source = "git@github.com:YOUR_ORG/terraform-aws-modules.git//modules/networking/alb?ref=v20260123110212-6e54d81"

  project_name       = var.project
  name               = "${local.name_prefix}-${var.alb_name}"
  internal           = var.alb_internal
  vpc_id             = local.vpc_id
  subnet_ids         = var.alb_internal ? local.private_subnet_ids : local.public_subnet_ids
  security_group_ids = [module.alb_sg.id]

  target_groups = {}

  listeners = {}

  access_logs = {
    enabled = false
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# ALB Listener - HTTP (Redirect para HTTPS)
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "http" {
  load_balancer_arn = module.alb.lb_arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.tags
}

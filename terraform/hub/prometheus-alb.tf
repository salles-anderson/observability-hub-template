# -----------------------------------------------------------------------------
# Prometheus ALB Configuration
# -----------------------------------------------------------------------------
# Expoe Prometheus via HTTPS para integracao com Kinesis Firehose
# Necessario para CloudWatch Metric Streams
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Target Group - Prometheus
# -----------------------------------------------------------------------------
resource "aws_lb_target_group" "prometheus" {
  count = var.enable_metric_streams ? 1 : 0

  name        = "${local.name_prefix}-prometheus-tg"
  port        = 9090
  protocol    = "HTTP"
  vpc_id      = local.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/-/healthy"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-prometheus-tg"
  })
}

# -----------------------------------------------------------------------------
# ALB Listener Rule - Prometheus
# -----------------------------------------------------------------------------
resource "aws_lb_listener_rule" "prometheus" {
  count = var.enable_metric_streams ? 1 : 0

  listener_arn = aws_lb_listener.https.arn
  priority     = 110

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.prometheus[0].arn
  }

  condition {
    host_header {
      values = ["prometheus.${var.domain_name}"]
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-prometheus-rule"
  })
}

# -----------------------------------------------------------------------------
# Route53 Record - Prometheus
# -----------------------------------------------------------------------------
resource "aws_route53_record" "prometheus" {
  count = var.enable_metric_streams ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = "prometheus.${var.domain_name}"
  type    = "A"

  alias {
    name                   = module.alb.lb_dns_name
    zone_id                = module.alb.lb_zone_id
    evaluate_target_health = true
  }
}

# -----------------------------------------------------------------------------
# Update ECS Service - Add Load Balancer
# -----------------------------------------------------------------------------
# NOTA: Esta configuracao requer atualizar o aws_ecs_service.prometheus
# para incluir o load_balancer block. Ver prometheus.tf
# -----------------------------------------------------------------------------

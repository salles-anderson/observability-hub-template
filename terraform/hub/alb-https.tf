# -----------------------------------------------------------------------------
# ALB Listener - HTTPS
# -----------------------------------------------------------------------------
resource "aws_lb_listener" "https" {
  load_balancer_arn = module.alb.lb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = module.acm.arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  tags = local.tags

  # Aguarda a validação do certificado antes de criar o listener
  depends_on = [module.acm]
}

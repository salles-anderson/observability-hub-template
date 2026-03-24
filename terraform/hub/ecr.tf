# -----------------------------------------------------------------------------
# ECR Repositories - Observability Hub Images
# -----------------------------------------------------------------------------
# Imagens copiadas do Docker Hub para ECR, eliminando rate limits e
# garantindo disponibilidade independente do Docker Hub.
# Para atualizar versao: docker pull <image>:<tag> && docker tag && docker push
# -----------------------------------------------------------------------------
locals {
  ecr_repos = toset([
    "obs-hub/grafana",
    "obs-hub/prometheus",
    "obs-hub/loki",
    "obs-hub/tempo",
    "obs-hub/alloy",
    "obs-hub/alertmanager",
    "obs-hub/k6",
    "obs-hub/litellm",
    "obs-hub/mcp-grafana",
    "obs-hub/aiops-agent",
    "obs-hub/fluent-bit",
    "obs-hub/busybox",
    "obs-hub/chainlit-chat",
    "obs-hub/qdrant",
    "obs-hub/mcp-aws",
    "obs-hub/mcp-github",
    "obs-hub/mcp-tfc",
    "obs-hub/mcp-qdrant",
    "obs-hub/mcp-confluence",
    "obs-hub/mcp-eraser",
  ])
}

resource "aws_ecr_repository" "obs_hub" {
  for_each = local.ecr_repos

  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-${replace(each.value, "obs-hub/", "")}"
  })
}

resource "aws_ecr_lifecycle_policy" "obs_hub" {
  for_each = local.ecr_repos

  repository = aws_ecr_repository.obs_hub[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# ECR Repository - Grafana Customizado Your Company
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "grafana_teck" {
  name                 = "grafana-teck"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-grafana-teck"
  })
}

# Lifecycle policy - manter apenas as últimas 5 imagens
resource "aws_ecr_lifecycle_policy" "grafana_teck" {
  repository = aws_ecr_repository.grafana_teck.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 5 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Output para facilitar o uso
output "grafana_ecr_repository_url" {
  description = "URL do repositório ECR do Grafana customizado"
  value       = aws_ecr_repository.grafana_teck.repository_url
}

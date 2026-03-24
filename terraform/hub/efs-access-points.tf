# -----------------------------------------------------------------------------
# EFS Access Points  Pontos de acesso para persistência de dados dos serviços de observabilidade  Nota: O access point do Grafana está definido em grafana.tf
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Access Point - Prometheus UID/GID 65534 (nobody) é o usuário padrão do container Prometheus
# -----------------------------------------------------------------------------
resource "aws_efs_access_point" "prometheus" {
  count = var.efs_enabled ? 1 : 0

  file_system_id = aws_efs_file_system.this[0].id

  # Configuração do diretório raiz para o Prometheus
  root_directory {
    path = "/prometheus"

    creation_info {
      owner_uid   = 65534
      owner_gid   = 65534
      permissions = "0755"
    }
  }

  # Identidade POSIX para o container
  posix_user {
    uid = 65534
    gid = 65534
  }

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}-efs-ap-prometheus"
    Service = "prometheus"
  })
}

# -----------------------------------------------------------------------------
# Access Point - AlertManager UID/GID 65534 (nobody) é o usuário padrão do container AlertManager
# -----------------------------------------------------------------------------
resource "aws_efs_access_point" "alertmanager" {
  count = var.efs_enabled ? 1 : 0

  file_system_id = aws_efs_file_system.this[0].id

  # Configuração do diretório raiz para o AlertManager
  root_directory {
    path = "/alertmanager"

    creation_info {
      owner_uid   = 65534
      owner_gid   = 65534
      permissions = "0755"
    }
  }

  # Identidade POSIX para o container
  posix_user {
    uid = 65534
    gid = 65534
  }

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}-efs-ap-alertmanager"
    Service = "alertmanager"
  })
}

# -----------------------------------------------------------------------------
# Access Point - Qdrant UID/GID 1000
# qdrant/qdrant container roda como user 1000 por padrao
# -----------------------------------------------------------------------------
resource "aws_efs_access_point" "qdrant" {
  count = var.enable_qdrant ? 1 : 0

  file_system_id = aws_efs_file_system.this[0].id

  root_directory {
    path = "/qdrant"

    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  posix_user {
    uid = 1000
    gid = 1000
  }

  tags = merge(local.tags, {
    Name    = "${local.name_prefix}-efs-ap-qdrant"
    Service = "qdrant"
  })
}

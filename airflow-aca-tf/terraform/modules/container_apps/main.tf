locals {
  scheduler_cpu = var.deployment_mode == "production" ? 1.0 : 0.5
  scheduler_mem = var.deployment_mode == "production" ? "2Gi" : "1Gi"
  scheduler_min = var.deployment_mode == "production" ? 2 : 1

  webserver_cpu = var.deployment_mode == "production" ? 0.5 : 0.25
  webserver_mem = var.deployment_mode == "production" ? "1Gi" : "0.5Gi"
  webserver_min = var.deployment_mode == "production" ? 1 : 0

  worker_cpu = var.deployment_mode == "production" ? 1.0 : 0.5
  worker_mem = var.deployment_mode == "production" ? "2Gi" : "1Gi"

  pg_conn_str = "postgresql://airflow:${var.postgres_password}@${var.postgres_host}/airflow?sslmode=require"
  redis_url   = "rediss://:${var.redis_primary_key}@${var.redis_host}:6380/0"

  common_env = [
    { name = "AIRFLOW__CORE__EXECUTOR", value = "CeleryExecutor" },
    { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = local.pg_conn_str },
    { name = "AIRFLOW__CELERY__BROKER_URL", value = local.redis_url },
    { name = "AIRFLOW__CELERY__RESULT_BACKEND", value = "db+${local.pg_conn_str}" },
    { name = "AIRFLOW__CORE__FERNET_KEY", value = var.airflow_fernet_key },
    { name = "AIRFLOW__WEBSERVER__SECRET_KEY", value = var.airflow_webserver_secret_key },
    { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "True" },
    { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "wasb://airflow-logs@${var.storage_account_name}.blob.core.windows.net" },
    { name = "AIRFLOW__LOGGING__REMOTE_LOG_CONN_ID", value = "azure_blob_logs" },
    { name = "AIRFLOW__CORE__DAGS_FOLDER", value = "/opt/airflow/dags" },
    { name = "AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK", value = "True" },
  ]
}

# NOTE: Role assignments removed from Terraform
# They must be assigned manually after deployment
# See RBAC_SETUP.md for instructions

# Scheduler Container App
resource "azurerm_container_app" "scheduler" {
  name                         = "${var.env_name}-scheduler"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.aca_environment_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.scheduler_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.scheduler_identity_id
  }

  template {
    min_replicas = local.scheduler_min
    max_replicas = local.scheduler_min

    container {
      name    = "scheduler"
      image   = var.airflow_image
      cpu     = local.scheduler_cpu
      memory  = local.scheduler_mem
      command = ["airflow", "scheduler"]

      dynamic "env" {
        for_each = local.common_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      volume_mounts {
        name = "dags"
        path = "/opt/airflow/dags"
      }

      liveness_probe {
        transport = "HTTP"
        port      = 8974
        path      = "/health"
      }
    }

    volume {
      name         = "dags"
      storage_type = "AzureFile"
      storage_name = var.aca_storage_name
    }
  }

  tags = var.tags
}

# Triggerer Container App
resource "azurerm_container_app" "triggerer" {
  name                         = "${var.env_name}-triggerer"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.aca_environment_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.triggerer_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.triggerer_identity_id
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name    = "triggerer"
      image   = var.airflow_image
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["airflow", "triggerer"]

      dynamic "env" {
        for_each = local.common_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      volume_mounts {
        name = "dags"
        path = "/opt/airflow/dags"
      }
    }

    volume {
      name         = "dags"
      storage_type = "AzureFile"
      storage_name = var.aca_storage_name
    }
  }

  tags = var.tags
}

# Webserver Container App
resource "azurerm_container_app" "webserver" {
  name                         = "${var.env_name}-webserver"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.aca_environment_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.webserver_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.webserver_identity_id
  }

  ingress {
    external_enabled = false
    target_port      = 8080
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = local.webserver_min
    max_replicas = 1

    container {
      name    = "webserver"
      image   = var.airflow_image
      cpu     = local.webserver_cpu
      memory  = local.webserver_mem
      command = ["airflow", "webserver"]

      dynamic "env" {
        for_each = local.common_env
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      volume_mounts {
        name = "dags"
        path = "/opt/airflow/dags"
      }

      readiness_probe {
        transport = "HTTP"
        port      = 8080
        path      = "/health"
      }
    }

    volume {
      name         = "dags"
      storage_type = "AzureFile"
      storage_name = var.aca_storage_name
    }
  }

  tags = var.tags
}

# Worker Container App
resource "azurerm_container_app" "worker" {
  name                         = "${var.env_name}-worker"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.aca_environment_id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [var.worker_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.worker_identity_id
  }

  template {
    min_replicas = 0
    max_replicas = 10

    container {
      name    = "worker"
      image   = var.airflow_image
      cpu     = local.worker_cpu
      memory  = local.worker_mem
      command = ["airflow", "celery", "worker"]

      dynamic "env" {
        for_each = concat(local.common_env, [
          { name = "AIRFLOW__CELERY__WORKER_CONCURRENCY", value = "4" }
        ])
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      volume_mounts {
        name = "dags"
        path = "/opt/airflow/dags"
      }
    }

    volume {
      name         = "dags"
      storage_type = "AzureFile"
      storage_name = var.aca_storage_name
    }
  }

  tags = var.tags
}

# ETL Runner Job (optional)
resource "azurerm_container_app_job" "etl_runner" {
  count = var.enable_etl_job ? 1 : 0

  name                         = "${var.env_name}-etl-runner"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = var.aca_environment_id

  identity {
    type         = "UserAssigned"
    identity_ids = [var.worker_identity_id]
  }

  registry {
    server   = var.acr_login_server
    identity = var.worker_identity_id
  }

  replica_timeout_in_seconds = 14400
  replica_retry_limit        = 2

  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "etl-runner"
      image  = var.etl_runner_image
      cpu    = 1.0
      memory = "2Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = var.worker_principal_id
      }
    }
  }

  tags = var.tags
}

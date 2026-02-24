resource "azurerm_container_app" "web" {
  name                        = "${var.prefix}-web"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name         = azurerm_resource_group.rg.name
  revision_mode               = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.airflow.id]
  }

  template {
    container {
      name   = "webserver"
      image  = var.airflow_image
      cpu    = 0.25
      memory = "0.5Gi"

      command = ["bash", "-lc"]
      args = [
        # PoC init: migrate DB + create admin (idempotent-ish) + start webserver
        "airflow db migrate && airflow users create --role Admin --username ${var.airflow_admin_user} --password ${var.airflow_admin_pass} --firstname Admin --lastname User --email admin@local || true; airflow webserver"
      ]

      dynamic "env" {
        for_each = local.airflow_base_env
        content {
          name  = env.key
          value = env.value
        }
      }

      volume_mounts {
        name       = "dags"
        mount_path = "/opt/airflow/dags"
      }
    }

    min_replicas = 0
    max_replicas = 1

    volume {
      name         = "dags"
      storage_type = "AzureFile"
      storage_name = azurerm_storage_account.sa.name
      share_name   = azurerm_storage_share.dags.name
      access_key   = azurerm_storage_account.sa.primary_access_key
    }
  }

  ingress {
    external_enabled = false
    target_port      = 8080
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }
}
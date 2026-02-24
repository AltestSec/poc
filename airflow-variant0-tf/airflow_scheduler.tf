resource "azurerm_container_app" "scheduler" {
  name                        = "${var.prefix}-sch"
  container_app_environment_id = azurerm_container_app_environment.cae.id
  resource_group_name         = azurerm_resource_group.rg.name
  revision_mode               = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.airflow.id]
  }

  template {
    container {
      name   = "scheduler"
      image  = var.airflow_image
      cpu    = 0.5
      memory = "1Gi"

      command = ["bash", "-lc"]
      args    = ["airflow db migrate && airflow scheduler"]

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

    # Scheduler MUST be always-on (no ingress => don't set to 0)
    min_replicas = 1
    max_replicas = 1

    volume {
      name         = "dags"
      storage_type = "AzureFile"
      storage_name = azurerm_storage_account.sa.name
      share_name   = azurerm_storage_share.dags.name
      access_key   = azurerm_storage_account.sa.primary_access_key
    }
  }
}
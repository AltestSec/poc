resource "azurerm_container_app_job" "etl" {
  name                        = "${var.prefix}-etl"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  container_app_environment_id = azurerm_container_app_environment.cae.id

  replica_timeout_in_seconds = 3600
  replica_retry_limit        = 1

  manual_trigger_config {
    parallelism              = 10
    replica_completion_count = 1
  }

  template {
    container {
      name   = "main"
      image  = var.etl_image
      cpu    = 0.5
      memory = "1Gi"
      # command/args/env можно override при start (см. DAG)
    }
  }
}
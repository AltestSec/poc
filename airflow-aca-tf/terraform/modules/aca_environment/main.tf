resource "azurerm_container_app_environment" "env" {
  name                       = var.name
  resource_group_name        = var.resource_group_name
  location                   = var.location
  log_analytics_workspace_id = var.log_analytics_workspace_id
  infrastructure_subnet_id   = var.infrastructure_subnet_id
  internal_load_balancer_enabled = true
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  tags = var.tags
}

resource "azurerm_container_app_environment_storage" "dags" {
  name                         = "airflow-dags-storage"
  container_app_environment_id = azurerm_container_app_environment.env.id
  account_name                 = var.storage_account_name
  share_name                   = var.file_share_name
  access_key                   = var.storage_account_key
  access_mode                  = "ReadOnly"
}

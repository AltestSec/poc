resource "azurerm_storage_account" "storage" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  large_file_share_enabled        = true

  tags = var.tags
}

resource "azurerm_storage_share" "dags" {
  name                 = "airflow-dags"
  storage_account_name = azurerm_storage_account.storage.name
  quota                = 5
  access_tier          = "Hot"
}

resource "azurerm_storage_container" "logs" {
  name                  = "airflow-logs"
  storage_account_name  = azurerm_storage_account.storage.name
  container_access_type = "private"
}

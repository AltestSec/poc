resource "azurerm_postgresql_flexible_server" "postgres" {
  name                = "${var.name}-pg-server"
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = "16"

  administrator_login    = "airflow"
  administrator_password = var.admin_password

  sku_name   = var.sku_name
  storage_mb = 32768

  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  dynamic "high_availability" {
    for_each = var.deployment_mode == "production" ? [1] : []
    content {
      mode = "ZoneRedundant"
    }
  }

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "airflow" {
  name      = "airflow"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

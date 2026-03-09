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
  
  delegated_subnet_id = var.delegated_subnet_id
  private_dns_zone_id = var.private_dns_zone_id
  
  public_network_access_enabled = false

  lifecycle {
    ignore_changes = [zone]
  }

  tags = var.tags
}

resource "azurerm_postgresql_flexible_server_database" "airflow" {
  name      = "airflow"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

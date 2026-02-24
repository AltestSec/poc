resource "azurerm_postgresql_flexible_server" "pg" {
  name                   = "${var.prefix}-pg"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "15"
  administrator_login    = var.pg_admin_user
  administrator_password = var.pg_admin_pass

  sku_name   = "B_Standard_B1ms" # PoC bursted
  storage_mb = 32768

  backup_retention_days = 7
}

# PoC: allow Azure services (public access). For strict internal: use private access + private DNS.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.pg.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_database" "airflow" {
  name      = "airflow"
  server_id = azurerm_postgresql_flexible_server.pg.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}
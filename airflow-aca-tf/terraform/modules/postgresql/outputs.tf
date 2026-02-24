output "id" {
  description = "PostgreSQL server ID"
  value       = azurerm_postgresql_flexible_server.postgres.id
}

output "fqdn" {
  description = "PostgreSQL server FQDN"
  value       = azurerm_postgresql_flexible_server.postgres.fqdn
}

output "database_name" {
  description = "Airflow database name"
  value       = azurerm_postgresql_flexible_server_database.airflow.name
}

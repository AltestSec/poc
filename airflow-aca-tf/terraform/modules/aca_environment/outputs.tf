output "environment_id" {
  description = "ACA environment ID"
  value       = azurerm_container_app_environment.env.id
}

output "default_domain" {
  description = "ACA environment default domain"
  value       = azurerm_container_app_environment.env.default_domain
}

output "storage_name" {
  description = "ACA environment storage name"
  value       = azurerm_container_app_environment_storage.dags.name
}

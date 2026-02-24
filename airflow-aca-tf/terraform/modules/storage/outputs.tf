output "storage_account_id" {
  description = "Storage account ID"
  value       = azurerm_storage_account.storage.id
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.storage.name
}

output "storage_account_key" {
  description = "Storage account primary key"
  value       = azurerm_storage_account.storage.primary_access_key
  sensitive   = true
}

output "dags_share_name" {
  description = "DAGs file share name"
  value       = azurerm_storage_share.dags.name
}

output "logs_container_name" {
  description = "Logs container name"
  value       = azurerm_storage_container.logs.name
}

output "workspace_id" {
  description = "Log Analytics workspace ID"
  value       = azurerm_log_analytics_workspace.logs.id
}

output "workspace_customer_id" {
  description = "Log Analytics workspace customer ID"
  value       = azurerm_log_analytics_workspace.logs.workspace_id
}

output "primary_shared_key" {
  description = "Log Analytics primary shared key"
  value       = azurerm_log_analytics_workspace.logs.primary_shared_key
  sensitive   = true
}

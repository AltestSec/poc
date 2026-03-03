output "scheduler_identity_id" {
  description = "Scheduler managed identity ID"
  value       = azurerm_user_assigned_identity.scheduler.id
}

output "scheduler_principal_id" {
  description = "Scheduler principal ID"
  value       = azurerm_user_assigned_identity.scheduler.principal_id
}

output "scheduler_client_id" {
  description = "Scheduler client ID"
  value       = azurerm_user_assigned_identity.scheduler.client_id
}

output "worker_identity_id" {
  description = "Worker managed identity ID"
  value       = azurerm_user_assigned_identity.worker.id
}

output "worker_principal_id" {
  description = "Worker principal ID"
  value       = azurerm_user_assigned_identity.worker.principal_id
}

output "worker_client_id" {
  description = "Worker client ID"
  value       = azurerm_user_assigned_identity.worker.client_id
}

output "webserver_identity_id" {
  description = "Webserver managed identity ID"
  value       = azurerm_user_assigned_identity.webserver.id
}

output "webserver_principal_id" {
  description = "Webserver principal ID"
  value       = azurerm_user_assigned_identity.webserver.principal_id
}

output "triggerer_identity_id" {
  description = "Triggerer managed identity ID"
  value       = azurerm_user_assigned_identity.triggerer.id
}

output "triggerer_principal_id" {
  description = "Triggerer principal ID"
  value       = azurerm_user_assigned_identity.triggerer.principal_id
}

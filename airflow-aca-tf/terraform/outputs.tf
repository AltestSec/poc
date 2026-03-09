output "acr_login_server" {
  description = "ACR login server URL"
  value       = module.acr.login_server
}

output "acr_admin_username" {
  description = "ACR admin username"
  value       = module.acr.admin_username
  sensitive   = true
}

output "resource_group_name" {
  description = "Resource group name"
  value       = data.azurerm_resource_group.main.name
}

output "aca_environment_id" {
  description = "ACA Environment ID"
  value       = module.aca_environment.environment_id
}

output "webserver_fqdn" {
  description = "Airflow webserver FQDN"
  value       = module.container_apps.webserver_fqdn
}

output "etl_runner_job_id" {
  description = "ETL runner job ID"
  value       = module.container_apps.etl_runner_job_id
}

output "worker_principal_id" {
  description = "Worker managed identity principal ID"
  value       = module.managed_identity.worker_principal_id
}

output "postgres_host" {
  description = "PostgreSQL host"
  value       = module.postgresql.fqdn
}

output "redis_host" {
  description = "Redis host"
  value       = module.redis.hostname
}

output "storage_account_name" {
  description = "Storage account name"
  value       = module.storage.storage_account_name
}

output "key_vault_uri" {
  description = "Key Vault URI"
  value       = module.key_vault.vault_uri
}

output "vm_public_ip" {
  description = "Windows VM public IP for RDP (if enabled)"
  value       = var.enable_windows_vm ? module.windows_vm[0].public_ip : null
}

output "vm_rdp_command" {
  description = "RDP connection command (if VM enabled)"
  value       = var.enable_windows_vm ? module.windows_vm[0].rdp_connection_string : null
}

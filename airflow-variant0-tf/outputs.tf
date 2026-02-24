############################################
# Core infra
############################################

output "resource_group" {
  description = "Resource Group name"
  value       = azurerm_resource_group.rg.name
}

output "location" {
  description = "Deployment location"
  value       = azurerm_resource_group.rg.location
}

############################################
# Container Apps
############################################

output "containerapps_environment_name" {
  description = "Container Apps Environment name"
  value       = azurerm_container_app_environment.cae.name
}

output "airflow_web_app_name" {
  description = "Airflow Webserver Container App name"
  value       = azurerm_container_app.web.name
}

output "airflow_scheduler_app_name" {
  description = "Airflow Scheduler Container App name"
  value       = azurerm_container_app.scheduler.name
}

output "airflow_worker_app_name" {
  description = "Airflow Worker Container App name"
  value       = azapi_resource.worker.name
}

output "airflow_web_internal_fqdn" {
  description = "Internal FQDN of Airflow Webserver (requires private access)"
  value       = try(azurerm_container_app.web.ingress[0].fqdn, null)
}

############################################
# ACA Job
############################################

output "etl_job_name" {
  description = "Container Apps Job name"
  value       = azurerm_container_app_job.etl.name
}

############################################
# Data services
############################################

output "postgres_fqdn" {
  description = "PostgreSQL Flexible Server FQDN"
  value       = azurerm_postgresql_flexible_server.pg.fqdn
}

output "postgres_database_name" {
  description = "Airflow metadata database name"
  value       = azurerm_postgresql_flexible_server_database.airflow.name
}

output "redis_hostname" {
  description = "Redis hostname"
  value       = azurerm_redis_cache.redis.hostname
}

############################################
# Storage (DAGs)
############################################

output "storage_account_name" {
  description = "Storage Account name for DAGs (Azure Files)"
  value       = azurerm_storage_account.sa.name
}

output "storage_share_name" {
  description = "Azure Files share name for DAGs"
  value       = azurerm_storage_share.dags.name
}

############################################
# Identity / RBAC
############################################

output "airflow_uami_name" {
  description = "User Assigned Managed Identity name"
  value       = azurerm_user_assigned_identity.airflow.name
}

output "airflow_uami_principal_id" {
  description = "Principal ID of Airflow UAMI"
  value       = azurerm_user_assigned_identity.airflow.principal_id
}

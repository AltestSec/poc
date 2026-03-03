output "scheduler_id" {
  description = "Scheduler container app ID"
  value       = azurerm_container_app.scheduler.id
}

output "webserver_id" {
  description = "Webserver container app ID"
  value       = azurerm_container_app.webserver.id
}

output "webserver_fqdn" {
  description = "Webserver FQDN"
  value       = azurerm_container_app.webserver.ingress[0].fqdn
}

output "worker_id" {
  description = "Worker container app ID"
  value       = azurerm_container_app.worker.id
}

output "triggerer_id" {
  description = "Triggerer container app ID"
  value       = azurerm_container_app.triggerer.id
}

output "etl_runner_job_id" {
  description = "ETL runner job ID"
  value       = var.enable_etl_job ? azurerm_container_app_job.etl_runner[0].id : null
}

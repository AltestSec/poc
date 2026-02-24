variable "env_name" {
  description = "Environment name"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "aca_environment_id" {
  description = "ACA environment ID"
  type        = string
}

variable "aca_storage_name" {
  description = "ACA storage name"
  type        = string
}

variable "acr_login_server" {
  description = "ACR login server"
  type        = string
}

variable "airflow_image" {
  description = "Airflow container image"
  type        = string
}

variable "etl_runner_image" {
  description = "ETL runner container image"
  type        = string
}

variable "airflow_fernet_key" {
  description = "Airflow fernet key"
  type        = string
  sensitive   = true
}

variable "airflow_webserver_secret_key" {
  description = "Airflow webserver secret key"
  type        = string
  sensitive   = true
}

variable "postgres_host" {
  description = "PostgreSQL host"
  type        = string
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "redis_host" {
  description = "Redis host"
  type        = string
}

variable "redis_primary_key" {
  description = "Redis primary key"
  type        = string
  sensitive   = true
}

variable "storage_account_name" {
  description = "Storage account name"
  type        = string
}

variable "storage_account_id" {
  description = "Storage account ID"
  type        = string
}

variable "deployment_mode" {
  description = "Deployment mode: poc or production"
  type        = string
}

variable "scheduler_identity_id" {
  description = "Scheduler managed identity ID"
  type        = string
}

variable "worker_identity_id" {
  description = "Worker managed identity ID"
  type        = string
}

variable "webserver_identity_id" {
  description = "Webserver managed identity ID"
  type        = string
}

variable "triggerer_identity_id" {
  description = "Triggerer managed identity ID"
  type        = string
}

variable "scheduler_principal_id" {
  description = "Scheduler principal ID"
  type        = string
}

variable "worker_principal_id" {
  description = "Worker principal ID"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

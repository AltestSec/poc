variable "env_name" {
  description = "Environment name prefix (e.g. airflow-poc, airflow-prod)"
  type        = string
}

variable "prefix" {
  description = "Optional prefix for unique resource naming. Will be combined with env_name: {prefix}-{env_name}-{resource}. If not provided, only env_name will be used."
  type        = string
  default     = ""
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
}

variable "deployment_mode" {
  description = "Deployment mode: poc or production"
  type        = string
  default     = "poc"
  validation {
    condition     = contains(["poc", "production"], var.deployment_mode)
    error_message = "deployment_mode must be either 'poc' or 'production'"
  }
}

variable "enable_etl_job" {
  description = "Enable ETL runner job (set to false if you don't have etl-runner image yet)"
  type        = bool
  default     = true
}

variable "airflow_image" {
  description = "Container image for Airflow components"
  type        = string
  default     = "apache/airflow:2.9.3"
}

variable "etl_runner_image" {
  description = "ETL runner image (DBT or custom)"
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart-jobs:latest"
}

variable "airflow_fernet_key" {
  description = "Airflow fernet key for encryption"
  type        = string
  sensitive   = true
}

variable "airflow_webserver_secret_key" {
  description = "Airflow webserver secret key"
  type        = string
  sensitive   = true
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}

variable "postgres_sku_name" {
  description = "PostgreSQL SKU name"
  type        = string
  default     = "Standard_B1ms"
}

variable "redis_sku_name" {
  description = "Redis SKU name"
  type        = string
  default     = "Standard"
}

variable "redis_family" {
  description = "Redis family"
  type        = string
  default     = "C"
}

variable "redis_capacity" {
  description = "Redis capacity"
  type        = number
  default     = 1
}

variable "acr_sku" {
  description = "ACR SKU"
  type        = string
  default     = "Basic"
}

variable "owner" {
  description = "Owner email for tagging"
  type        = string
}

variable "duedate" {
  description = "Due date for tagging"
  type        = string
}

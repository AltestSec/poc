variable "prefix" {
  type    = string
  default = "poc-airflow"
}

variable "location" {
  type    = string
  default = "eastus"
}

# Airflow image (for real usage: build your own with providers + DAGs)
variable "airflow_image" {
  type    = string
  default = "apache/airflow:2.9.3"
}

# ETL job container image
variable "etl_image" {
  type    = string
  default = "mcr.microsoft.com/k8se/quickstart-jobs:latest"
}

# Postgres admin
variable "pg_admin_user" {
  type    = string
  default = "airflowadmin"
}

variable "pg_admin_pass" {
  type      = string
  sensitive = true
}

# Airflow admin user (PoC only)
variable "airflow_admin_user" {
  type    = string
  default = "admin"
}
variable "airflow_admin_pass" {
  type      = string
  default   = "admin"
  sensitive = true
}
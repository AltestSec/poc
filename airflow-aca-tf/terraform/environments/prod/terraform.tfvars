env_name            = "airflow-prod"
location            = "westeurope"
resource_group_name = "merzlikin-tf-state-rg"
deployment_mode     = "production"

# Prefix for globally unique resource names (ACR, Storage, Key Vault)
prefix = "merzlikin"

airflow_image    = "apache/airflow:2.9.3"
etl_runner_image = "ghcr.io/your-org/etl-runner:latest"

postgres_sku_name = "GP_Standard_D2ds_v4"
redis_sku_name    = "Premium"
redis_family      = "P"
redis_capacity    = 1
acr_sku           = "Standard"

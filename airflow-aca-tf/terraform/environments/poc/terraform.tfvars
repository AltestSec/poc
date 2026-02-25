env_name            = "airflow-poc"
location            = "westeurope"
resource_group_name = "merzlikin-tf-state-rg"
deployment_mode     = "poc"

# Prefix for globally unique resource names (ACR, Storage, Key Vault)
prefix = "merzlikin"

airflow_image    = "apache/airflow:2.9.3"
etl_runner_image = "ghcr.io/your-org/etl-runner:latest"

postgres_sku_name = "B_Standard_B1ms"
redis_sku_name    = "Standard"
redis_family      = "C"
redis_capacity    = 1
acr_sku           = "Basic"

env_name            = "airflow-poc"
location            = "westeurope"
resource_group_name = "merzlikin-tf-state-rg"
deployment_mode     = "poc"

# Prefix for globally unique resource names (ACR, Storage, Key Vault)
prefix = "merzlikin"

# Enable ETL job (your custom DBT runner)
# Set to false until images are built and pushed to ACR
enable_etl_job = true

# Use images from your ACR (built by pipeline or locally)
# Format: <acr-name>.azurecr.io/<image>:<tag>
# Note: Build and push images first before enabling ETL job
airflow_image    = "merzlikinairflowpocacr.azurecr.io/airflow:latest"
etl_runner_image = "merzlikinairflowpocacr.azurecr.io/etl-runner:latest"

postgres_sku_name = "B_Standard_B1ms"
redis_sku_name    = "Standard"
redis_family      = "C"
redis_capacity    = 1
acr_sku           = "Basic"

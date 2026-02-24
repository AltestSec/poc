env_name            = "airflow-poc"
location            = "westeurope"
resource_group_name = "airflow-poc-rg"
deployment_mode     = "poc"

airflow_image    = "apache/airflow:2.9.3"
etl_runner_image = "ghcr.io/your-org/etl-runner:latest"

postgres_sku_name = "B_Standard_B1ms"
redis_sku_name    = "Standard"
redis_family      = "C"
redis_capacity    = 1
acr_sku           = "Basic"

owner   = "user@gmail.com"
duedate = "6march"

resource "random_password" "web_secret_key" {
  length  = 32
  special = false
}

resource "random_password" "fernet_key" {
  length  = 32
  special = false
}

locals {
  # Postgres connection for Airflow metadata
  pg_host = azurerm_postgresql_flexible_server.pg.fqdn
  pg_db   = azurerm_postgresql_flexible_server_database.airflow.name

  airflow_sqlalchemy_conn = "postgresql+psycopg2://${var.pg_admin_user}:${var.pg_admin_pass}@${local.pg_host}:5432/${local.pg_db}"

  # Redis broker URL for CeleryExecutor
  redis_host = azurerm_redis_cache.redis.hostname
  redis_port = azurerm_redis_cache.redis.port
  redis_key  = azurerm_redis_cache.redis.primary_access_key

  airflow_celery_broker = "redis://:${local.redis_key}@${local.redis_host}:${local.redis_port}/0"
  airflow_result_backend = "db+${local.airflow_sqlalchemy_conn}"

  # Concurrency defaults for your case (~10 parallel job)
  airflow_concurrency_env = {
    "AIRFLOW__CORE__PARALLELISM"              = "32"
    "AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG" = "16"
    "AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG"  = "10"
    "AIRFLOW__CELERY__WORKER_CONCURRENCY"     = "2"
  }

  airflow_base_env = merge(
    {
      "AIRFLOW__CORE__EXECUTOR"             = "CeleryExecutor"
      "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN" = local.airflow_sqlalchemy_conn
      "AIRFLOW__CELERY__BROKER_URL"         = local.airflow_celery_broker
      "AIRFLOW__CELERY__RESULT_BACKEND"     = local.airflow_result_backend

      "AIRFLOW__CORE__FERNET_KEY"       = random_password.fernet_key.result
      "AIRFLOW__WEBSERVER__SECRET_KEY"  = random_password.web_secret_key.result
      "AIRFLOW__CORE__LOAD_EXAMPLES"    = "False"
      "AIRFLOW__LOGGING__LOGGING_LEVEL" = "INFO"

      # Used by DAG to call ARM API for job start
      "AZ_SUBSCRIPTION_ID" = data.azurerm_client_config.current.subscription_id
      "AZ_RESOURCE_GROUP"  = azurerm_resource_group.rg.name
      "ACA_JOB_NAME"       = azurerm_container_app_job.etl.name
    },
    local.airflow_concurrency_env
  )
}

data "azurerm_client_config" "current" {}
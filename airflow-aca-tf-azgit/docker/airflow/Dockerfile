# ============================================================
# Custom Airflow image — adds Azure provider + DBT + MSI auth
# Base: apache/airflow:2.9.3
# ============================================================
ARG AIRFLOW_VERSION=2.9.3
FROM apache/airflow:${AIRFLOW_VERSION}

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Azure provider (includes ACA Jobs operator, Blob, Key Vault hooks)
# dbt-core for local lightweight transforms (workers run full ETL via etl-runner job)
# azure-identity for Managed Identity / DefaultAzureCredential support
RUN pip install --no-cache-dir \
    apache-airflow-providers-microsoft-azure==8.5.0 \
    azure-identity==1.16.0 \
    azure-mgmt-appcontainers==3.1.0 \
    dbt-core==1.7.2 \
    dbt-sqlserver==1.7.4

# Copy custom plugins (ACA Job operator, etc.)
COPY --chown=airflow:root plugins/ /opt/airflow/plugins/

# Copy webserver_config for RBAC/auth customization
COPY --chown=airflow:root config/webserver_config.py /opt/airflow/webserver_config.py

EXPOSE 8080

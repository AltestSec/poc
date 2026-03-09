# ============================================================
# etl-runner/Dockerfile
# ACA Job container: runs DBT transforms
# Called by Airflow Worker via ACAJobRunOperator
# ============================================================
FROM python:3.11-slim

WORKDIR /app

# Install system deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install DBT + Azure provider + MSSQL adapter
# Adjust dbt-sqlserver / dbt-postgres depending on your target DB
RUN pip install --no-cache-dir \
    dbt-core==1.7.2 \
    dbt-sqlserver==1.7.4 \
    azure-identity==1.16.0 \
    azure-keyvault-secrets==4.7.0

# Copy DBT project and profiles
COPY dbt_project/ /app/dbt_project/
COPY profiles.yml  /app/profiles.yml

# Copy test script
COPY test_etl.py /app/test_etl.py
RUN chmod +x /app/test_etl.py

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]

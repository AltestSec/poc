#!/bin/bash
# ============================================================
# entrypoint.sh — etl-runner ACA Job
# Runs DBT with parameters passed from Airflow via env vars
# Supports test mode for network security validation
# ============================================================
set -euo pipefail

# Check if running in test mode
if [[ "${RUN_MODE:-}" == "test" ]]; then
  echo "═══════════════════════════════════════════════"
  echo " Running in TEST MODE"
  echo " Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "═══════════════════════════════════════════════"
  python3 /app/test_etl.py
  exit $?
fi

DBT_TARGET="${DBT_TARGET:-prod}"
DBT_MODELS="${DBT_MODELS:-}"
AIRFLOW_RUN_ID="${AIRFLOW_RUN_ID:-unknown}"

echo "═══════════════════════════════════════════════"
echo " etl-runner starting"
echo " Target:    $DBT_TARGET"
echo " Models:    ${DBT_MODELS:-<all>}"
echo " Run ID:    $AIRFLOW_RUN_ID"
echo " Started:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "═══════════════════════════════════════════════"

cd /app/dbt_project

# Fetch DB credentials from Key Vault via Managed Identity
# DefaultAzureCredential picks up the ACA Managed Identity automatically
if [[ -n "${AZURE_KEY_VAULT_URI:-}" ]]; then
  echo "▶ Fetching secrets from Key Vault..."
  export DBT_DB_PASSWORD=$(python3 -c "
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import os
client = SecretClient(vault_url=os.environ['AZURE_KEY_VAULT_URI'], credential=DefaultAzureCredential())
print(client.get_secret('airflow-db-password').value)
")
fi

# Run DBT
DBT_CMD="dbt run --target $DBT_TARGET --profiles-dir /app"
if [[ -n "$DBT_MODELS" ]]; then
  DBT_CMD="$DBT_CMD --select $DBT_MODELS"
fi

echo "▶ Running: $DBT_CMD"
eval "$DBT_CMD"

echo ""
echo "▶ Running DBT tests..."
DBT_TEST_CMD="dbt test --target $DBT_TARGET --profiles-dir /app"
if [[ -n "$DBT_MODELS" ]]; then
  DBT_TEST_CMD="$DBT_TEST_CMD --select $DBT_MODELS"
fi
eval "$DBT_TEST_CMD"

echo ""
echo "═══════════════════════════════════════════════"
echo " etl-runner completed successfully"
echo " Finished: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "═══════════════════════════════════════════════"

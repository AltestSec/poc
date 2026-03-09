#!/bin/bash
# ============================================================
# Upload DAGs to Storage File Share
# ============================================================
set -euo pipefail

RESOURCE_GROUP="${1:-}"
ENV_NAME="${2:-}"
DAGS_PATH="${3:-./dags}"

if [[ -z "$RESOURCE_GROUP" ]] || [[ -z "$ENV_NAME" ]]; then
  echo "Usage: $0 <resource-group> <env-name> [dags-path]"
  echo "Example: $0 merzlikin-tf-state-rg airflow-poc ./dags"
  exit 1
fi

STORAGE_NAME=$(echo "${ENV_NAME}stor" | tr -d '-')

echo "═══════════════════════════════════════════════════════════"
echo " Uploading DAGs to Storage"
echo " Resource Group: $RESOURCE_GROUP"
echo " Storage:        $STORAGE_NAME"
echo " DAGs Path:      $DAGS_PATH"
echo "═══════════════════════════════════════════════════════════"

# Check if storage exists
if ! az storage account show --name "$STORAGE_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "✗ Storage account not found: $STORAGE_NAME"
  exit 1
fi

# Check if DAGs directory exists
if [[ ! -d "$DAGS_PATH" ]]; then
  echo "✗ DAGs directory not found: $DAGS_PATH"
  exit 1
fi

# Count DAG files
DAG_COUNT=$(find "$DAGS_PATH" -name "*.py" | wc -l)
echo ""
echo "Found $DAG_COUNT DAG files"

if [[ $DAG_COUNT -eq 0 ]]; then
  echo "⚠ Warning: No Python files found in $DAGS_PATH"
  exit 1
fi

# Upload DAGs
echo ""
echo "▶ Uploading DAGs..."

az storage file upload-batch \
  --account-name "$STORAGE_NAME" \
  --destination airflow-dags \
  --source "$DAGS_PATH" \
  --auth-mode login \
  --output table

echo ""
echo "✓ DAGs uploaded successfully"
echo ""
echo "Next steps:"
echo "1. Wait 1-2 minutes for Airflow to detect new DAGs"
echo "2. Access webserver: ./scripts/access-webserver.sh $RESOURCE_GROUP $ENV_NAME"
echo "3. Check DAGs in Airflow UI"

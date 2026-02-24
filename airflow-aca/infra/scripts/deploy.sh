#!/usr/bin/env bash
# =============================================================
# deploy.sh — full PoC or production deploy
#
# Usage:
#   ./deploy.sh poc westeurope my-resource-group
#   ./deploy.sh production westeurope my-resource-group
# =============================================================

set -euo pipefail

MODE="${1:-poc}"
LOCATION="${2:-westeurope}"
RG="${3:?Usage: $0 <poc|production> <location> <resource-group>}"
DEPLOY_NAME="airflow-deploy-$(date +%Y%m%d%H%M%S)"

echo "═══════════════════════════════════════════════"
echo " Airflow on ACA — deploy ($MODE)"
echo "═══════════════════════════════════════════════"

# ── Pre-flight ─────────────────────────────────────
command -v az       >/dev/null || { echo "ERROR: az CLI not found"; exit 1; }
command -v python3  >/dev/null || { echo "ERROR: python3 not found"; exit 1; }

# ── Generate secrets if not set ────────────────────
if [[ -z "${AIRFLOW_FERNET_KEY:-}" ]]; then
  echo "▶ Generating Fernet key..."
  export AIRFLOW_FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
  echo "  AIRFLOW_FERNET_KEY=$AIRFLOW_FERNET_KEY"
  echo "  ⚠  Save this key — you'll need it if you redeploy!"
fi

if [[ -z "${AIRFLOW_SECRET_KEY:-}" ]]; then
  echo "▶ Generating webserver secret key..."
  export AIRFLOW_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
fi

# ── Resource group ────────────────────────────────
az group create --name "$RG" --location "$LOCATION" --output none
echo "Resource group: $RG"

# ── Bicep deploy ──────────────────────────────────
PARAM_FILE="./bicep/main.${MODE}.bicepparam"
echo "▶ Running Bicep deploy ($PARAM_FILE)..."
az deployment group create \
  --name "$DEPLOY_NAME" \
  --resource-group "$RG" \
  --template-file "./bicep/main.bicep" \
  --parameters "$PARAM_FILE" \
  --output table

echo "Bicep deploy complete"

# ── Capture outputs ──────────────────────────────
WORKER_PRINCIPAL_ID=$(az deployment group show \
  -g "$RG" -n "$DEPLOY_NAME" \
  --query properties.outputs.workerPrincipalId.value -o tsv)

ETL_JOB_ID=$(az deployment group show \
  -g "$RG" -n "$DEPLOY_NAME" \
  --query properties.outputs.etlRunnerJobId.value -o tsv)

STORAGE_ACCOUNT=$(az deployment group show \
  -g "$RG" -n "$DEPLOY_NAME" \
  --query properties.outputs.storageAccountName.value -o tsv)

WEBSERVER_FQDN=$(az deployment group show \
  -g "$RG" -n "$DEPLOY_NAME" \
  --query properties.outputs.webserverFqdn.value -o tsv)

# ── Assign Worker → etl-runner role ──────────────
echo "▶ Assigning Container Apps Jobs Executor role..."
./scripts/assign-roles.sh "$RG" "$WORKER_PRINCIPAL_ID" "$ETL_JOB_ID"

# ── Initialize Airflow DB ─────────────────────────
ENV_NAME="airflow-${MODE}-env"
echo "▶ Running airflow db migrate (one-off job)..."
az containerapp job start \
  --name "airflow-${MODE}-scheduler" \
  --resource-group "$RG" \
  --command "airflow db migrate" 2>/dev/null || \
  echo "  (DB migrate runs automatically on scheduler startup)"

# ── Create Airflow admin user ─────────────────────
echo ""
echo "▶ To create admin user, run:"
echo "  az containerapp exec -n airflow-${MODE}-scheduler -g $RG \\"
echo "    --command \"airflow users create --username admin --firstname Admin \\"
echo "      --lastname User --role Admin --email admin@example.com --password YOURPASSWORD\""

# ── Summary ───────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════"
echo " Deploy complete!"
echo "═══════════════════════════════════════════════"
echo " Webserver (internal):  https://$WEBSERVER_FQDN"
echo " Storage account:       $STORAGE_ACCOUNT"
echo " ETL Runner Job ID:     $ETL_JOB_ID"
echo ""
echo " DAGs: upload to Azure Files share 'airflow-dags'"
echo "   az storage file upload-batch \\"
echo "     --account-name $STORAGE_ACCOUNT \\"
echo "     --destination airflow-dags \\"
echo "     --source ./dags"
echo ""
echo " Webserver port-forward (for local access):"
echo "   az containerapp tunnel --name airflow-${MODE}-webserver \\"
echo "     --resource-group $RG --port 8080:8080"
echo "═══════════════════════════════════════════════"

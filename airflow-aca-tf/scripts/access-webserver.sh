#!/bin/bash
# ============================================================
# Access Airflow Webserver
# Creates tunnel to internal webserver
# ============================================================
set -euo pipefail

RESOURCE_GROUP="${1:-}"
ENV_NAME="${2:-}"

if [[ -z "$RESOURCE_GROUP" ]] || [[ -z "$ENV_NAME" ]]; then
  echo "Usage: $0 <resource-group> <env-name>"
  echo "Example: $0 merzlikin-tf-state-rg airflow-poc"
  exit 1
fi

WEBSERVER_NAME="${ENV_NAME}-webserver"

echo "═══════════════════════════════════════════════════════════"
echo " Accessing Airflow Webserver"
echo " Resource Group: $RESOURCE_GROUP"
echo " Webserver:      $WEBSERVER_NAME"
echo "═══════════════════════════════════════════════════════════"

# Check if webserver exists
if ! az containerapp show --name "$WEBSERVER_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  echo "✗ Webserver not found: $WEBSERVER_NAME"
  exit 1
fi

# Get webserver status
STATUS=$(az containerapp show --name "$WEBSERVER_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.runningStatus" -o tsv)
echo ""
echo "Webserver Status: $STATUS"

if [[ "$STATUS" != "Running" ]]; then
  echo "⚠ Warning: Webserver is not running"
  echo ""
  echo "Check logs:"
  echo "  az containerapp logs show --name $WEBSERVER_NAME --resource-group $RESOURCE_GROUP --follow"
  exit 1
fi

# Get FQDN
FQDN=$(az containerapp show --name "$WEBSERVER_NAME" --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv)
echo "Internal FQDN: $FQDN"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Creating tunnel to webserver..."
echo " Local URL: http://localhost:8080"
echo " Press Ctrl+C to stop the tunnel"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Create tunnel
az containerapp tunnel \
  --name "$WEBSERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --port 8080:8080

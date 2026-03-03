#!/bin/bash
# assign-roles.sh - Assign RBAC roles to managed identities after Terraform deployment

set -e

# Configuration
RESOURCE_GROUP="${1:-merzlikin-tf-state-rg}"
ENV_NAME="${2:-airflow-poc}"

echo "=========================================="
echo "RBAC Role Assignment Script"
echo "=========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Environment: $ENV_NAME"
echo "=========================================="

# Get subscription ID
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

echo ""
echo "Step 1: Getting Managed Identity Principal IDs..."

SCHEDULER_PRINCIPAL_ID=$(az identity show \
  --name ${ENV_NAME}-scheduler-mi \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv 2>/dev/null || echo "")

WORKER_PRINCIPAL_ID=$(az identity show \
  --name ${ENV_NAME}-worker-mi \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv 2>/dev/null || echo "")

WEBSERVER_PRINCIPAL_ID=$(az identity show \
  --name ${ENV_NAME}-webserver-mi \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv 2>/dev/null || echo "")

TRIGGERER_PRINCIPAL_ID=$(az identity show \
  --name ${ENV_NAME}-triggerer-mi \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv 2>/dev/null || echo "")

# Check if identities exist
if [ -z "$SCHEDULER_PRINCIPAL_ID" ] || [ -z "$WORKER_PRINCIPAL_ID" ] || [ -z "$WEBSERVER_PRINCIPAL_ID" ] || [ -z "$TRIGGERER_PRINCIPAL_ID" ]; then
  echo "❌ Error: Could not find all managed identities."
  echo "   Make sure Terraform has been applied successfully."
  echo ""
  echo "   Looking for:"
  echo "   - ${ENV_NAME}-scheduler-mi"
  echo "   - ${ENV_NAME}-worker-mi"
  echo "   - ${ENV_NAME}-webserver-mi"
  echo "   - ${ENV_NAME}-triggerer-mi"
  exit 1
fi

echo "✅ Found all managed identities:"
echo "   Scheduler: $SCHEDULER_PRINCIPAL_ID"
echo "   Worker: $WORKER_PRINCIPAL_ID"
echo "   Webserver: $WEBSERVER_PRINCIPAL_ID"
echo "   Triggerer: $TRIGGERER_PRINCIPAL_ID"

echo ""
echo "Step 2: Assigning Contributor role on Resource Group..."
echo "   Scope: $RG_SCOPE"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do
  IDENTITY_NAME=$(az identity list --resource-group $RESOURCE_GROUP --query "[?principalId=='$PRINCIPAL'].name" -o tsv)
  echo "   Assigning to: $IDENTITY_NAME ($PRINCIPAL)..."
  
  if az role assignment create \
    --assignee $PRINCIPAL \
    --role "Contributor" \
    --scope $RG_SCOPE \
    --output none 2>/dev/null; then
    echo "   ✅ Success"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  else
    # Check if already assigned
    EXISTING=$(az role assignment list \
      --assignee $PRINCIPAL \
      --scope $RG_SCOPE \
      --query "[?roleDefinitionName=='Contributor']" \
      --output tsv 2>/dev/null)
    
    if [ -n "$EXISTING" ]; then
      echo "   ℹ️  Already assigned"
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
      echo "   ❌ Failed"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi
done

echo ""
echo "=========================================="
echo "Summary:"
echo "   Successful: $SUCCESS_COUNT"
echo "   Failed: $FAIL_COUNT"
echo "=========================================="

if [ $FAIL_COUNT -eq 0 ]; then
  echo "✅ All roles assigned successfully!"
  echo ""
  echo "Next steps:"
  echo "1. Verify Container Apps can pull images from ACR"
  echo "2. Upload DAGs to storage account"
  echo "3. Access Airflow webserver"
  exit 0
else
  echo "⚠️  Some role assignments failed."
  echo "   Check your permissions and try again."
  exit 1
fi

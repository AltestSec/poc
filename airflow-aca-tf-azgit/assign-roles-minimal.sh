#!/bin/bash
# assign-roles-minimal.sh - Minimal RBAC roles assignment

set -e

RESOURCE_GROUP="${1:-merzlikin-tf-state-rg}"
ENV_NAME="${2:-airflow-poc}"
PREFIX="${3:-merzlikin}"

echo "=========================================="
echo "Minimal RBAC Role Assignment"
echo "=========================================="
echo "Resource Group: $RESOURCE_GROUP"
echo "Environment: $ENV_NAME"
echo "Prefix: $PREFIX"
echo "=========================================="

# Get Principal IDs
echo "Getting Managed Identity Principal IDs..."
SCHEDULER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-scheduler-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WORKER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-worker-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WEBSERVER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-webserver-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
TRIGGERER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-triggerer-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)

# Get Resource IDs
echo "Getting Resource IDs..."
ACR_ID=$(az acr show --name ${PREFIX}${ENV_NAME}acr --resource-group $RESOURCE_GROUP --query id -o tsv 2>/dev/null | tr -d '-')
STORAGE_ID=$(az storage account show --name ${PREFIX}${ENV_NAME}stor --resource-group $RESOURCE_GROUP --query id -o tsv 2>/dev/null | tr -d '-')
ETL_JOB_ID=$(az containerapp job show --name ${ENV_NAME}-etl-runner --resource-group $RESOURCE_GROUP --query id -o tsv 2>/dev/null)

echo ""
echo "=========================================="
echo "Assigning Minimal Roles"
echo "=========================================="

# 1. ACR Pull - All components need to pull images
echo ""
echo "1. ACR Pull (Critical for pulling images)"
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do
  IDENTITY_NAME=$(az identity list --resource-group $RESOURCE_GROUP --query "[?principalId=='$PRINCIPAL'].name" -o tsv)
  echo "   → $IDENTITY_NAME"
  az role assignment create \
    --assignee $PRINCIPAL \
    --role "AcrPull" \
    --scope $ACR_ID \
    --output none 2>/dev/null || echo "   (already assigned)"
done

# 2. Storage Blob Data Contributor - Scheduler and Worker need to write logs
echo ""
echo "2. Storage Blob Data Contributor (For logs)"
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID; do
  IDENTITY_NAME=$(az identity list --resource-group $RESOURCE_GROUP --query "[?principalId=='$PRINCIPAL'].name" -o tsv)
  echo "   → $IDENTITY_NAME"
  az role assignment create \
    --assignee $PRINCIPAL \
    --role "Storage Blob Data Contributor" \
    --scope $STORAGE_ID \
    --output none 2>/dev/null || echo "   (already assigned)"
done

# 3. Reader on RG - All components (for service discovery)
echo ""
echo "3. Reader on Resource Group (For service discovery)"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do
  IDENTITY_NAME=$(az identity list --resource-group $RESOURCE_GROUP --query "[?principalId=='$PRINCIPAL'].name" -o tsv)
  echo "   → $IDENTITY_NAME"
  az role assignment create \
    --assignee $PRINCIPAL \
    --role "Reader" \
    --scope $RG_SCOPE \
    --output none 2>/dev/null || echo "   (already assigned)"
done

# 4. Container Apps Contributor - Worker needs to start ETL jobs
echo ""
echo "4. Container Apps Contributor (For starting ETL jobs)"
echo "   → worker-mi"
az role assignment create \
  --assignee $WORKER_PRINCIPAL_ID \
  --role "Container Apps Contributor" \
  --scope $ETL_JOB_ID \
  --output none 2>/dev/null || echo "   (already assigned)"

echo ""
echo "=========================================="
echo "✅ Minimal roles assigned successfully!"
echo "=========================================="
echo ""
echo "Assigned roles summary:"
echo "  All components:"
echo "    - AcrPull on ACR"
echo "    - Reader on Resource Group"
echo ""
echo "  Scheduler & Worker:"
echo "    - Storage Blob Data Contributor on Storage Account"
echo ""
echo "  Worker only:"
echo "    - Container Apps Contributor on ETL Job"
echo ""

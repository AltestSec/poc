#!/bin/bash
# ============================================================
# debug-scheduler.sh - Debug scheduler issues
# ============================================================
set -e

RG_NAME="${1:-merzlikin-tf-state-rg}"
ENV_NAME="${2:-airflow-poc}"

echo "=========================================="
echo "Debugging Scheduler"
echo "=========================================="
echo ""

# Get detailed revision info
echo "=== Revision Details ==="
az containerapp revision list \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "[].{Name:name, Active:properties.active, ProvisioningState:properties.provisioningState, HealthState:properties.healthState, Replicas:properties.replicas, RunningState:properties.runningState}" \
  -o table

echo ""
echo "=== Latest Revision Full Details ==="
LATEST_REVISION=$(az containerapp revision list \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "[0].name" -o tsv)

az containerapp revision show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --revision $LATEST_REVISION \
  --query "{Name:name, ProvisioningState:properties.provisioningState, HealthState:properties.healthState, Replicas:properties.replicas, Template:properties.template.containers[0]}" \
  -o json

echo ""
echo "=== Container App System Logs ==="
az containerapp logs show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --type system \
  --tail 100 \
  --format text

echo ""
echo "=== Container App Console Logs ==="
az containerapp logs show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --type console \
  --tail 100 \
  --format text

echo ""
echo "=== Replica Details ==="
az containerapp replica list \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --revision $LATEST_REVISION \
  --query "[].{Name:name, CreatedTime:properties.createdTime, RunningState:properties.runningState, Containers:properties.containers[].name}" \
  -o table 2>/dev/null || echo "No replicas found or command not available"

echo ""
echo "=== Environment Variables Check ==="
az containerapp show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "properties.template.containers[0].env[?name=='AIRFLOW__DATABASE__SQL_ALCHEMY_CONN' || name=='AIRFLOW__CORE__EXECUTOR']" \
  -o table

echo ""
echo "=========================================="
echo "Debug completed"
echo "=========================================="

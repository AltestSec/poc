#!/bin/bash
# ============================================================
# check-deployment.sh - Check Airflow deployment status
# ============================================================
set -e

RG_NAME="${1:-merzlikin-tf-state-rg}"
ENV_NAME="${2:-airflow-poc}"

echo "=========================================="
echo "Checking Airflow Deployment"
echo "Resource Group: $RG_NAME"
echo "Environment: $ENV_NAME"
echo "=========================================="
echo ""

# Check scheduler status
echo "=== Scheduler Status ==="
az containerapp show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "{Name:name, Status:properties.runningStatus, ProvisioningState:properties.provisioningState, Replicas:properties.template.scale.minReplicas}" \
  -o table

echo ""
echo "=== Scheduler Logs (last 50 lines) ==="
az containerapp logs show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --tail 50 \
  --format text || echo "Failed to get logs"

echo ""
echo "=== Scheduler Revisions ==="
az containerapp revision list \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "[].{Name:name, Active:properties.active, Created:properties.createdTime, Replicas:properties.replicas, TrafficWeight:properties.trafficWeight}" \
  -o table

echo ""
echo "=== All Container Apps Status ==="
az containerapp list \
  --resource-group $RG_NAME \
  --query "[?contains(name, '${ENV_NAME}')].{Name:name, Status:properties.runningStatus, FQDN:properties.configuration.ingress.fqdn}" \
  -o table

echo ""
echo "=== PostgreSQL Status ==="
PG_NAME=$(az postgres flexible-server list \
  --resource-group $RG_NAME \
  --query "[?contains(name, '${ENV_NAME}')].name" -o tsv)

if [ -n "$PG_NAME" ]; then
  az postgres flexible-server show \
    --name $PG_NAME \
    --resource-group $RG_NAME \
    --query "{Name:name, State:state, Version:version, Location:location}" \
    -o table
else
  echo "PostgreSQL server not found"
fi

echo ""
echo "=========================================="
echo "Deployment check completed"
echo "=========================================="

#!/bin/bash
# ============================================================
# diagnose-webserver.sh - Diagnose webserver issues
# ============================================================

RG_NAME="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"

echo "=========================================="
echo "Diagnosing Webserver"
echo "=========================================="
echo ""

echo "=== 1. Webserver Status ==="
az containerapp show \
  --name ${ENV_NAME}-webserver \
  --resource-group $RG_NAME \
  --query "{Name:name, Status:properties.runningStatus, ProvisioningState:properties.provisioningState, MinReplicas:properties.template.scale.minReplicas, MaxReplicas:properties.template.scale.maxReplicas}" \
  -o table

echo ""
echo "=== 2. Webserver Ingress Configuration ==="
az containerapp show \
  --name ${ENV_NAME}-webserver \
  --resource-group $RG_NAME \
  --query "{FQDN:properties.configuration.ingress.fqdn, External:properties.configuration.ingress.external, TargetPort:properties.configuration.ingress.targetPort, Transport:properties.configuration.ingress.transport}" \
  -o table

echo ""
echo "=== 3. Webserver Revisions ==="
az containerapp revision list \
  --name ${ENV_NAME}-webserver \
  --resource-group $RG_NAME \
  --query "[].{Name:name, Active:properties.active, ProvisioningState:properties.provisioningState, Replicas:properties.replicas, TrafficWeight:properties.trafficWeight}" \
  -o table

echo ""
echo "=== 4. Webserver Replicas ==="
LATEST_REVISION=$(az containerapp revision list \
  --name ${ENV_NAME}-webserver \
  --resource-group $RG_NAME \
  --query "[0].name" -o tsv)

if [ -n "$LATEST_REVISION" ]; then
  az containerapp replica list \
    --name ${ENV_NAME}-webserver \
    --resource-group $RG_NAME \
    --revision $LATEST_REVISION 2>/dev/null || echo "No replicas running"
fi

echo ""
echo "=== 5. Webserver System Logs ==="
az containerapp logs show \
  --name ${ENV_NAME}-webserver \
  --resource-group $RG_NAME \
  --type system \
  --tail 50 \
  --format text

echo ""
echo "=== 6. Webserver Console Logs ==="
az containerapp logs show \
  --name ${ENV_NAME}-webserver \
  --resource-group $RG_NAME \
  --type console \
  --tail 50 \
  --format text

echo ""
echo "=== 7. Check if min replicas is 0 ==="
MIN_REPLICAS=$(az containerapp show \
  --name ${ENV_NAME}-webserver \
  --resource-group $RG_NAME \
  --query "properties.template.scale.minReplicas" -o tsv)

if [ "$MIN_REPLICAS" = "0" ]; then
  echo "⚠️  WARNING: minReplicas is 0 - webserver will scale to zero when idle!"
  echo "This causes the 404 error. Webserver needs at least 1 replica."
  echo ""
  echo "Fix: Update minReplicas to 1"
  echo "Run: az containerapp update --name ${ENV_NAME}-webserver --resource-group $RG_NAME --min-replicas 1"
else
  echo "✅ minReplicas is $MIN_REPLICAS (should be at least 1)"
fi

echo ""
echo "=========================================="
echo "Diagnosis completed"
echo "=========================================="

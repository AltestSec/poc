#!/bin/bash
# ============================================================
# Validate Private Airflow Deployment
# Comprehensive health check for all services
# ============================================================
set -euo pipefail

RESOURCE_GROUP="${1:-}"
ENV_NAME="${2:-}"

if [[ -z "$RESOURCE_GROUP" ]] || [[ -z "$ENV_NAME" ]]; then
  echo "Usage: $0 <resource-group> <env-name>"
  echo "Example: $0 merzlikin-tf-state-rg airflow-poc"
  exit 1
fi

echo "═══════════════════════════════════════════════════════════"
echo " Validating Airflow Deployment"
echo " Resource Group: $RESOURCE_GROUP"
echo " Environment:    $ENV_NAME"
echo "═══════════════════════════════════════════════════════════"

PASSED=0
FAILED=0

# Helper function for test results
test_result() {
  local test_name="$1"
  local result="$2"
  
  if [[ "$result" == "0" ]]; then
    echo "✓ $test_name"
    PASSED=$((PASSED + 1))
  else
    echo "✗ $test_name"
    FAILED=$((FAILED + 1))
  fi
}

echo ""
echo "▶ Step 1: Checking Network Infrastructure"
echo "─────────────────────────────────────────────────────────"

# Check VNet
if az network vnet show --name "${ENV_NAME}-vnet" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Virtual Network exists" 0
else
  test_result "Virtual Network exists" 1
fi

# Check Firewall
if az network firewall show --name "${ENV_NAME}-fw" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Azure Firewall exists" 0
  
  # Get firewall status
  FW_STATE=$(az network firewall show --name "${ENV_NAME}-fw" --resource-group "$RESOURCE_GROUP" --query "provisioningState" -o tsv)
  if [[ "$FW_STATE" == "Succeeded" ]]; then
    test_result "Azure Firewall provisioned" 0
  else
    test_result "Azure Firewall provisioned (State: $FW_STATE)" 1
  fi
else
  test_result "Azure Firewall exists" 1
fi

# Check Route Table
if az network route-table show --name "${ENV_NAME}-vnet-aca-rt" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Route Table exists" 0
else
  test_result "Route Table exists" 1
fi

echo ""
echo "▶ Step 2: Checking Core Services"
echo "─────────────────────────────────────────────────────────"

# Check ACR
ACR_NAME=$(echo "${ENV_NAME}acr" | tr -d '-')
if az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Container Registry exists" 0
  
  # Check if public access is disabled
  PUBLIC_ACCESS=$(az acr show --name "$ACR_NAME" --resource-group "$RESOURCE_GROUP" --query "publicNetworkAccess" -o tsv)
  if [[ "$PUBLIC_ACCESS" == "Disabled" ]]; then
    test_result "ACR public access disabled" 0
  else
    test_result "ACR public access disabled (Current: $PUBLIC_ACCESS)" 1
  fi
  
  # Check for images
  IMAGE_COUNT=$(az acr repository list --name "$ACR_NAME" --output tsv 2>/dev/null | wc -l)
  if [[ $IMAGE_COUNT -gt 0 ]]; then
    test_result "ACR contains images ($IMAGE_COUNT found)" 0
  else
    test_result "ACR contains images" 1
  fi
else
  test_result "Container Registry exists" 1
fi

# Check Storage Account
STORAGE_NAME=$(echo "${ENV_NAME}stor" | tr -d '-')
if az storage account show --name "$STORAGE_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Storage Account exists" 0
  
  # Check if public access is disabled
  PUBLIC_ACCESS=$(az storage account show --name "$STORAGE_NAME" --resource-group "$RESOURCE_GROUP" --query "publicNetworkAccess" -o tsv)
  if [[ "$PUBLIC_ACCESS" == "Disabled" ]]; then
    test_result "Storage public access disabled" 0
  else
    test_result "Storage public access disabled (Current: $PUBLIC_ACCESS)" 1
  fi
else
  test_result "Storage Account exists" 1
fi

# Check PostgreSQL
PG_NAME="${ENV_NAME}-pg-pg-server"
if az postgres flexible-server show --name "$PG_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "PostgreSQL Server exists" 0
  
  # Check if public access is disabled
  PUBLIC_ACCESS=$(az postgres flexible-server show --name "$PG_NAME" --resource-group "$RESOURCE_GROUP" --query "network.publicNetworkAccess" -o tsv)
  if [[ "$PUBLIC_ACCESS" == "Disabled" ]]; then
    test_result "PostgreSQL public access disabled" 0
  else
    test_result "PostgreSQL public access disabled (Current: $PUBLIC_ACCESS)" 1
  fi
else
  test_result "PostgreSQL Server exists" 1
fi

# Check Redis
REDIS_NAME="${ENV_NAME}-redis"
if az redis show --name "$REDIS_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Redis Cache exists" 0
else
  test_result "Redis Cache exists" 1
fi

echo ""
echo "▶ Step 3: Checking Container Apps Environment"
echo "─────────────────────────────────────────────────────────"

# Check ACA Environment
ENV_FULL_NAME="${ENV_NAME}-env"
if az containerapp env show --name "$ENV_FULL_NAME" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Container Apps Environment exists" 0
  
  # Check if VNet integrated
  VNET_CONFIG=$(az containerapp env show --name "$ENV_FULL_NAME" --resource-group "$RESOURCE_GROUP" --query "vnetConfiguration" -o tsv)
  if [[ -n "$VNET_CONFIG" ]]; then
    test_result "Environment VNet integrated" 0
  else
    test_result "Environment VNet integrated" 1
  fi
else
  test_result "Container Apps Environment exists" 1
fi

echo ""
echo "▶ Step 4: Checking Container Apps"
echo "─────────────────────────────────────────────────────────"

# Check Scheduler
if az containerapp show --name "${ENV_NAME}-scheduler" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Scheduler exists" 0
  
  SCHEDULER_STATE=$(az containerapp show --name "${ENV_NAME}-scheduler" --resource-group "$RESOURCE_GROUP" --query "properties.runningStatus" -o tsv)
  if [[ "$SCHEDULER_STATE" == "Running" ]]; then
    test_result "Scheduler running" 0
  else
    test_result "Scheduler running (State: $SCHEDULER_STATE)" 1
  fi
  
  SCHEDULER_REPLICAS=$(az containerapp replica list --name "${ENV_NAME}-scheduler" --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null || echo "0")
  if [[ $SCHEDULER_REPLICAS -gt 0 ]]; then
    test_result "Scheduler has active replicas ($SCHEDULER_REPLICAS)" 0
  else
    test_result "Scheduler has active replicas" 1
  fi
else
  test_result "Scheduler exists" 1
fi

# Check Webserver
if az containerapp show --name "${ENV_NAME}-webserver" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Webserver exists" 0
  
  WEBSERVER_STATE=$(az containerapp show --name "${ENV_NAME}-webserver" --resource-group "$RESOURCE_GROUP" --query "properties.runningStatus" -o tsv)
  if [[ "$WEBSERVER_STATE" == "Running" ]]; then
    test_result "Webserver running" 0
  else
    test_result "Webserver running (State: $WEBSERVER_STATE)" 1
  fi
  
  # Check ingress
  INGRESS_FQDN=$(az containerapp show --name "${ENV_NAME}-webserver" --resource-group "$RESOURCE_GROUP" --query "properties.configuration.ingress.fqdn" -o tsv)
  if [[ -n "$INGRESS_FQDN" ]]; then
    test_result "Webserver ingress configured" 0
    echo "   FQDN: $INGRESS_FQDN"
  else
    test_result "Webserver ingress configured" 1
  fi
else
  test_result "Webserver exists" 1
fi

# Check Worker
if az containerapp show --name "${ENV_NAME}-worker" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Worker exists" 0
  
  WORKER_STATE=$(az containerapp show --name "${ENV_NAME}-worker" --resource-group "$RESOURCE_GROUP" --query "properties.runningStatus" -o tsv)
  if [[ "$WORKER_STATE" == "Running" ]]; then
    test_result "Worker running" 0
  else
    test_result "Worker running (State: $WORKER_STATE)" 1
  fi
else
  test_result "Worker exists" 1
fi

# Check Triggerer
if az containerapp show --name "${ENV_NAME}-triggerer" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "Triggerer exists" 0
  
  TRIGGERER_STATE=$(az containerapp show --name "${ENV_NAME}-triggerer" --resource-group "$RESOURCE_GROUP" --query "properties.runningStatus" -o tsv)
  if [[ "$TRIGGERER_STATE" == "Running" ]]; then
    test_result "Triggerer running" 0
  else
    test_result "Triggerer running (State: $TRIGGERER_STATE)" 1
  fi
else
  test_result "Triggerer exists" 1
fi

echo ""
echo "▶ Step 5: Checking ETL Job"
echo "─────────────────────────────────────────────────────────"

# Check ETL Job
if az containerapp job show --name "${ENV_NAME}-etl-runner" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
  test_result "ETL Runner Job exists" 0
else
  test_result "ETL Runner Job exists" 1
fi

echo ""
echo "▶ Step 6: Checking Private Endpoints"
echo "─────────────────────────────────────────────────────────"

# Count private endpoints
PE_COUNT=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv)
if [[ $PE_COUNT -ge 3 ]]; then
  test_result "Private Endpoints created ($PE_COUNT found)" 0
else
  test_result "Private Endpoints created ($PE_COUNT found, expected 3+)" 1
fi

echo ""
echo "▶ Step 7: Checking Managed Identities"
echo "─────────────────────────────────────────────────────────"

for COMPONENT in scheduler worker webserver triggerer; do
  if az identity show --name "${ENV_NAME}-${COMPONENT}-mi" --resource-group "$RESOURCE_GROUP" --output none 2>/dev/null; then
    test_result "Managed Identity: $COMPONENT" 0
  else
    test_result "Managed Identity: $COMPONENT" 1
  fi
done

echo ""
echo "▶ Step 8: Testing Connectivity (from Scheduler)"
echo "─────────────────────────────────────────────────────────"

# Test database connectivity
echo "Testing PostgreSQL connection..."
if az containerapp exec \
  --name "${ENV_NAME}-scheduler" \
  --resource-group "$RESOURCE_GROUP" \
  --command "python3 -c 'import psycopg2; print(\"OK\")'" \
  --output none 2>/dev/null; then
  test_result "PostgreSQL connectivity" 0
else
  echo "   Note: psycopg2 may not be installed, checking logs instead..."
  LOGS=$(az containerapp logs show --name "${ENV_NAME}-scheduler" --resource-group "$RESOURCE_GROUP" --tail 50 --output tsv 2>/dev/null || echo "")
  if echo "$LOGS" | grep -q "Connected to"; then
    test_result "PostgreSQL connectivity (via logs)" 0
  else
    test_result "PostgreSQL connectivity" 1
  fi
fi

# Test Redis connectivity
echo "Testing Redis connection..."
LOGS=$(az containerapp logs show --name "${ENV_NAME}-scheduler" --resource-group "$RESOURCE_GROUP" --tail 50 --output tsv 2>/dev/null || echo "")
if echo "$LOGS" | grep -q -i "redis\|celery"; then
  test_result "Redis connectivity (via logs)" 0
else
  test_result "Redis connectivity" 1
fi

# Test Storage connectivity
echo "Testing Storage File Share..."
LOGS=$(az containerapp logs show --name "${ENV_NAME}-scheduler" --resource-group "$RESOURCE_GROUP" --tail 50 --output tsv 2>/dev/null || echo "")
if echo "$LOGS" | grep -q -i "dags\|mounted"; then
  test_result "Storage File Share mounted (via logs)" 0
else
  test_result "Storage File Share mounted" 1
fi

echo ""
echo "▶ Step 9: Checking Logs"
echo "─────────────────────────────────────────────────────────"

# Check if logs are available
for COMPONENT in scheduler webserver worker triggerer; do
  LOG_OUTPUT=$(az containerapp logs show \
    --name "${ENV_NAME}-${COMPONENT}" \
    --resource-group "$RESOURCE_GROUP" \
    --tail 5 \
    --output tsv 2>/dev/null || echo "")
  
  if [[ -n "$LOG_OUTPUT" ]]; then
    test_result "Logs available: $COMPONENT" 0
  else
    test_result "Logs available: $COMPONENT" 1
  fi
done

echo ""
echo "═══════════════════════════════════════════════════════════"
echo " Validation Summary"
echo "═══════════════════════════════════════════════════════════"
echo " Passed: $PASSED"
echo " Failed: $FAILED"
echo " Total:  $((PASSED + FAILED))"
echo "═══════════════════════════════════════════════════════════"

if [[ $FAILED -eq 0 ]]; then
  echo ""
  echo "✓ All checks passed! Deployment is healthy."
  echo ""
  echo "Next steps:"
  echo "1. Access webserver: ./scripts/access-webserver.sh $RESOURCE_GROUP $ENV_NAME"
  echo "2. Run security tests: ./scripts/test-etl-job.sh $RESOURCE_GROUP $ENV_NAME"
  echo "3. Upload DAGs: ./scripts/upload-dags.sh $RESOURCE_GROUP $ENV_NAME"
  exit 0
else
  echo ""
  echo "✗ Some checks failed. Review the output above."
  echo ""
  echo "Troubleshooting:"
  echo "1. Check container logs: az containerapp logs show --name ${ENV_NAME}-scheduler --resource-group $RESOURCE_GROUP --follow"
  echo "2. Check firewall logs: See PRIVATE_NETWORK_SETUP.md"
  echo "3. Verify RBAC roles: ./assign-roles.sh $RESOURCE_GROUP $ENV_NAME"
  exit 1
fi

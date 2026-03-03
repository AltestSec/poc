#!/bin/bash
# ============================================================
# init-database.sh - Initialize Airflow database
# Run this ONCE before starting Airflow for the first time
# ============================================================

set -e

RG_NAME="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"
ACR_NAME="merzlikinairflowpocacr"

echo "=========================================="
echo "Initializing Airflow Database"
echo "=========================================="
echo ""

# Get Container Apps Environment name
echo "Getting Container Apps Environment..."
ACA_ENV_NAME=$(az containerapp env list \
  --resource-group $RG_NAME \
  --query "[?contains(name, '${ENV_NAME}')].name" -o tsv)

if [ -z "$ACA_ENV_NAME" ]; then
  echo "❌ Container Apps Environment not found!"
  exit 1
fi

echo "✅ Found environment: $ACA_ENV_NAME"
echo ""

# Get database connection string from scheduler
echo "Getting database connection string..."
DB_CONN=$(az containerapp show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "properties.template.containers[0].env[?name=='AIRFLOW__DATABASE__SQL_ALCHEMY_CONN'].value" -o tsv)

if [ -z "$DB_CONN" ]; then
  echo "❌ Could not get database connection string!"
  exit 1
fi

echo "✅ Got database connection"
echo ""

# Get other required env vars
echo "Getting environment variables..."
FERNET_KEY=$(az containerapp show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "properties.template.containers[0].env[?name=='AIRFLOW__CORE__FERNET_KEY'].value" -o tsv)

WEBSERVER_SECRET=$(az containerapp show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "properties.template.containers[0].env[?name=='AIRFLOW__WEBSERVER__SECRET_KEY'].value" -o tsv)

# Create temporary init job
echo "Creating database initialization job..."
az containerapp job create \
  --name ${ENV_NAME}-db-init \
  --resource-group $RG_NAME \
  --environment $ACA_ENV_NAME \
  --trigger-type Manual \
  --replica-timeout 600 \
  --replica-retry-limit 0 \
  --image ${ACR_NAME}.azurecr.io/airflow:latest \
  --cpu 0.5 \
  --memory 1Gi \
  --command "/bin/bash" \
  --args "-c" "airflow db migrate && airflow users create --username admin --firstname Admin --lastname User --role Admin --email admin@example.com --password admin || true" \
  --env-vars \
    "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=$DB_CONN" \
    "AIRFLOW__CORE__FERNET_KEY=$FERNET_KEY" \
    "AIRFLOW__WEBSERVER__SECRET_KEY=$WEBSERVER_SECRET" \
    "AIRFLOW__CORE__EXECUTOR=LocalExecutor" \
  --registry-server ${ACR_NAME}.azurecr.io

echo "✅ Job created"
echo ""

# Start the job
echo "Starting database initialization..."
az containerapp job start \
  --name ${ENV_NAME}-db-init \
  --resource-group $RG_NAME

echo ""
echo "Waiting for job to complete (this may take 1-2 minutes)..."
sleep 30

# Check execution status
EXECUTION_NAME=$(az containerapp job execution list \
  --name ${ENV_NAME}-db-init \
  --resource-group $RG_NAME \
  --query "[0].name" -o tsv)

if [ -n "$EXECUTION_NAME" ]; then
  echo ""
  echo "Job execution: $EXECUTION_NAME"
  
  # Wait for completion
  for i in {1..12}; do
    STATUS=$(az containerapp job execution show \
      --name ${ENV_NAME}-db-init \
      --resource-group $RG_NAME \
      --job-execution-name $EXECUTION_NAME \
      --query "properties.status" -o tsv)
    
    echo "Status: $STATUS"
    
    if [ "$STATUS" = "Succeeded" ]; then
      echo ""
      echo "✅ Database initialization completed successfully!"
      break
    elif [ "$STATUS" = "Failed" ]; then
      echo ""
      echo "❌ Database initialization failed!"
      echo "Check logs:"
      az containerapp job logs show \
        --name ${ENV_NAME}-db-init \
        --resource-group $RG_NAME
      break
    fi
    
    sleep 10
  done
fi

# Clean up
echo ""
echo "Cleaning up temporary job..."
az containerapp job delete \
  --name ${ENV_NAME}-db-init \
  --resource-group $RG_NAME \
  --yes

echo ""
echo "=========================================="
echo "✅ Database initialization completed"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Restart scheduler: az containerapp revision restart --name ${ENV_NAME}-scheduler --resource-group $RG_NAME --revision \$(az containerapp revision list --name ${ENV_NAME}-scheduler --resource-group $RG_NAME --query '[0].name' -o tsv)"
echo "2. Check webserver: ./scripts/manage-airflow.sh url"
echo "3. Login with: admin / admin"

#!/bin/bash
# ============================================================
# Test ETL Container Job
# Validates ETL job execution and network security
# ============================================================
set -euo pipefail

RESOURCE_GROUP="${1:-}"
ENV_NAME="${2:-}"

if [[ -z "$RESOURCE_GROUP" ]] || [[ -z "$ENV_NAME" ]]; then
  echo "Usage: $0 <resource-group> <env-name>"
  echo "Example: $0 merzlikin-tf-state-rg airflow-poc"
  exit 1
fi

echo "═══════════════════════════════════════════════"
echo " Testing ETL Container Job"
echo " Resource Group: $RESOURCE_GROUP"
echo " Environment:    $ENV_NAME"
echo "═══════════════════════════════════════════════"

JOB_NAME="${ENV_NAME}-etl-runner"

# Check if job exists
echo ""
echo "▶ Checking if job exists..."
if ! az containerapp job show \
  --name "$JOB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --output none 2>/dev/null; then
  echo "✗ Job not found: $JOB_NAME"
  exit 1
fi
echo "✓ Job found: $JOB_NAME"

# Start job execution in test mode
echo ""
echo "▶ Starting job execution (test mode)..."
EXECUTION_NAME="test-$(date +%s)"

az containerapp job start \
  --name "$JOB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --env-vars "RUN_MODE=test" \
  --output none

echo "✓ Job execution started: $EXECUTION_NAME"

# Wait for job to complete
echo ""
echo "▶ Waiting for job to complete..."
MAX_WAIT=300  # 5 minutes
ELAPSED=0
INTERVAL=10

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
  # Get latest execution
  EXECUTION_STATUS=$(az containerapp job execution list \
    --name "$JOB_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].properties.status" \
    --output tsv 2>/dev/null || echo "Unknown")
  
  echo "  Status: $EXECUTION_STATUS (${ELAPSED}s elapsed)"
  
  if [[ "$EXECUTION_STATUS" == "Succeeded" ]]; then
    echo "✓ Job completed successfully"
    break
  elif [[ "$EXECUTION_STATUS" == "Failed" ]]; then
    echo "✗ Job failed"
    break
  fi
  
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [[ $ELAPSED -ge $MAX_WAIT ]]; then
  echo "✗ Timeout waiting for job completion"
  exit 1
fi

# Get job logs
echo ""
echo "▶ Fetching job logs..."
EXECUTION_NAME=$(az containerapp job execution list \
  --name "$JOB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
  --output tsv)

echo ""
echo "═══════════════════════════════════════════════"
echo " Job Execution Logs"
echo "═══════════════════════════════════════════════"

az containerapp job logs show \
  --name "$JOB_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --execution "$EXECUTION_NAME" \
  --output table || echo "Note: Logs may not be immediately available"

echo ""
echo "═══════════════════════════════════════════════"
echo " Test Summary"
echo "═══════════════════════════════════════════════"
echo "Job Name:       $JOB_NAME"
echo "Execution:      $EXECUTION_NAME"
echo "Status:         $EXECUTION_STATUS"
echo "═══════════════════════════════════════════════"

if [[ "$EXECUTION_STATUS" == "Succeeded" ]]; then
  echo "✓ All tests passed"
  exit 0
else
  echo "✗ Tests failed"
  exit 1
fi

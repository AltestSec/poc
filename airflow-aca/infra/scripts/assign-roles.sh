#!/usr/bin/env bash
# =============================================================
# assign-roles.sh
# Run AFTER bicep deploy to wire up the Worker → etl-runner
# Container Apps Jobs Executor RBAC role.
#
# Usage:
#   WORKER_PRINCIPAL_ID=$(az deployment group show \
#     -g $RG -n airflow-deploy \
#     --query properties.outputs.workerPrincipalId.value -o tsv)
#
#   ETL_JOB_ID=$(az deployment group show \
#     -g $RG -n airflow-deploy \
#     --query properties.outputs.etlRunnerJobId.value -o tsv)
#
#   ./assign-roles.sh $RG $WORKER_PRINCIPAL_ID $ETL_JOB_ID
# =============================================================

set -euo pipefail

RESOURCE_GROUP="${1:?Usage: $0 <resource-group> <worker-principal-id> <etl-job-resource-id>}"
WORKER_PRINCIPAL_ID="${2:?}"
ETL_JOB_ID="${3:?}"

# Role: Container Apps Jobs Executor
# Allows starting job executions via ARM API — no credentials needed
ROLE_DEF_ID="641b5ab3-b6cd-4e28-a76d-bba4e86b1e51"

echo "▶ Assigning 'Container Apps Jobs Executor' to worker MI..."
az role assignment create \
  --role "$ROLE_DEF_ID" \
  --assignee-object-id "$WORKER_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$ETL_JOB_ID"

echo "Done. Worker can now trigger etl-runner via ARM API using Managed Identity."
echo ""
echo "Verify with:"
echo "  az role assignment list --assignee $WORKER_PRINCIPAL_ID --scope $ETL_JOB_ID -o table"

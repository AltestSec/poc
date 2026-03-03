#!/bin/bash
# ============================================================
# manage-airflow.sh - Manage Airflow deployment
# ============================================================

RG_NAME="${RG_NAME:-merzlikin-tf-state-rg}"
ENV_NAME="${ENV_NAME:-airflow-poc}"

show_help() {
  cat << EOF
Airflow Management Script

Usage: ./manage-airflow.sh <command> [options]

Commands:
  status              Show status of all components
  logs <component>    Show logs (scheduler|webserver|worker|triggerer)
  restart <component> Restart a component
  scale <component> <min> <max>  Scale worker replicas
  url                 Get webserver URL
  db-check            Check database connection
  upload-dags <path>  Upload DAGs to storage
  list-dags           List all DAGs via API
  trigger-dag <name>  Trigger a DAG via API
  health              Full health check

Examples:
  ./manage-airflow.sh status
  ./manage-airflow.sh logs scheduler
  ./manage-airflow.sh restart worker
  ./manage-airflow.sh scale worker 2 10
  ./manage-airflow.sh upload-dags ./my-dags
  ./manage-airflow.sh trigger-dag my_dag_id

Environment Variables:
  RG_NAME   - Resource group (default: merzlikin-tf-state-rg)
  ENV_NAME  - Environment name (default: airflow-poc)
EOF
}

get_webserver_url() {
  az containerapp show \
    --name ${ENV_NAME}-webserver \
    --resource-group $RG_NAME \
    --query "properties.configuration.ingress.fqdn" -o tsv
}

case "${1:-help}" in
  status)
    echo "=== Airflow Components Status ==="
    az containerapp list \
      --resource-group $RG_NAME \
      --query "[?contains(name, '${ENV_NAME}')].{Name:name, Status:properties.runningStatus, Replicas:properties.template.scale.minReplicas, FQDN:properties.configuration.ingress.fqdn}" \
      -o table
    ;;
    
  logs)
    COMPONENT="${2:-scheduler}"
    echo "=== Logs for ${COMPONENT} (last 100 lines, following) ==="
    az containerapp logs show \
      --name ${ENV_NAME}-${COMPONENT} \
      --resource-group $RG_NAME \
      --tail 100 \
      --follow \
      --format text
    ;;
    
  restart)
    COMPONENT="${2:-scheduler}"
    echo "Restarting ${COMPONENT}..."
    az containerapp revision restart \
      --name ${ENV_NAME}-${COMPONENT} \
      --resource-group $RG_NAME \
      --revision $(az containerapp revision list \
        --name ${ENV_NAME}-${COMPONENT} \
        --resource-group $RG_NAME \
        --query "[0].name" -o tsv)
    echo "✅ ${COMPONENT} restarted"
    ;;
    
  scale)
    COMPONENT="${2:-worker}"
    MIN_REPLICAS="${3:-1}"
    MAX_REPLICAS="${4:-10}"
    echo "Scaling ${COMPONENT} to min=${MIN_REPLICAS}, max=${MAX_REPLICAS}..."
    az containerapp update \
      --name ${ENV_NAME}-${COMPONENT} \
      --resource-group $RG_NAME \
      --min-replicas $MIN_REPLICAS \
      --max-replicas $MAX_REPLICAS
    echo "✅ ${COMPONENT} scaled"
    ;;
    
  url)
    URL=$(get_webserver_url)
    echo "Airflow Webserver URL: https://${URL}"
    echo ""
    echo "Login with: admin / admin (change password immediately!)"
    ;;
    
  db-check)
    echo "Checking database connection..."
    az containerapp logs show \
      --name ${ENV_NAME}-scheduler \
      --resource-group $RG_NAME \
      --tail 50 \
      --format text | grep -i "database\|postgres\|error" || echo "No database errors found"
    ;;
    
  upload-dags)
    DAG_PATH="${2:-.}"
    STORAGE_NAME=$(echo "merzlikin${ENV_NAME}stor" | tr -d '-')
    echo "Uploading DAGs from ${DAG_PATH} to ${STORAGE_NAME}..."
    az storage file upload-batch \
      --account-name $STORAGE_NAME \
      --destination airflow-dags \
      --source "$DAG_PATH" \
      --pattern "*.py"
    echo "✅ DAGs uploaded"
    ;;
    
  list-dags)
    URL=$(get_webserver_url)
    echo "Fetching DAGs from Airflow API..."
    curl -s -u admin:admin "https://${URL}/api/v1/dags" | jq -r '.dags[] | "\(.dag_id) - \(.is_paused)"'
    ;;
    
  trigger-dag)
    DAG_ID="${2}"
    if [ -z "$DAG_ID" ]; then
      echo "Error: DAG ID required"
      echo "Usage: ./manage-airflow.sh trigger-dag <dag_id>"
      exit 1
    fi
    URL=$(get_webserver_url)
    echo "Triggering DAG: ${DAG_ID}..."
    curl -s -u admin:admin -X POST "https://${URL}/api/v1/dags/${DAG_ID}/dagRuns" \
      -H "Content-Type: application/json" \
      -d '{}' | jq
    ;;
    
  health)
    echo "=== Full Health Check ==="
    echo ""
    echo "1. Component Status:"
    $0 status
    echo ""
    echo "2. Webserver URL:"
    $0 url
    echo ""
    echo "3. Recent Scheduler Logs:"
    az containerapp logs show \
      --name ${ENV_NAME}-scheduler \
      --resource-group $RG_NAME \
      --tail 20 \
      --format text
    echo ""
    echo "4. PostgreSQL Status:"
    PG_NAME=$(az postgres flexible-server list \
      --resource-group $RG_NAME \
      --query "[?contains(name, '${ENV_NAME}')].name" -o tsv)
    az postgres flexible-server show \
      --name $PG_NAME \
      --resource-group $RG_NAME \
      --query "{Name:name, State:state, Version:version}" \
      -o table
    ;;
    
  help|*)
    show_help
    ;;
esac

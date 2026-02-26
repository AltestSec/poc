# Airflow Database Initialization

## Overview

Airflow requires the PostgreSQL database to be initialized with the Airflow schema before the scheduler and other components can start. This is a one-time operation.

## Automatic Initialization (Recommended)

The Airflow Docker image includes an entrypoint script that automatically handles database initialization when the scheduler starts.

**This is the preferred method** - no manual intervention needed!

### What it does:

1. **Checks database connection** - Waits up to 60 seconds for PostgreSQL to be ready
2. **Initializes database** - Runs `airflow db init` if database is not initialized
3. **Runs migrations** - Applies any pending database migrations
4. **Creates admin user** - Creates default admin user if it doesn't exist
   - Username: `admin`
   - Password: `admin` (⚠️ CHANGE THIS IMMEDIATELY!)
   - Email: `admin@example.com`
   - Role: Admin

### How to verify it's working:

```bash
# Check scheduler logs
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --tail 100 --follow
```

Look for these messages:
- ✅ "Checking database connection..."
- ✅ "Database is ready"
- ✅ "Starting scheduler..."

If you see errors, continue to manual initialization below.

## Manual Initialization (If Needed)

If automatic initialization fails or you need to manually initialize:

### Option 1: Check Logs First (Recommended)

Before attempting manual initialization, check if it's already happening automatically:

```bash
# Run the deployment check script
./scripts/check-deployment.sh

# Or manually check logs
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --tail 100 --follow
```

### Option 2: Via Container Exec (May Not Work)

**Note:** `az containerapp exec` often fails with WebSocket errors. If this doesn't work, use Option 3.

```bash
# Execute db init command in scheduler container
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --command "airflow db init"
```

If you get error: `ClusterExecEndpointWebSocketConnectionError`, this is a known Azure limitation. Use Option 3 instead.

### Option 3: Via Temporary Container App Job (Most Reliable)

This creates a one-time job that runs `airflow db init` and then cleans up:

```bash
# Set variables
RG_NAME="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"
ACR_NAME="merzlikinairflowpocacr"

# Get Container Apps Environment name
ACA_ENV_NAME=$(az containerapp env list \
  --resource-group $RG_NAME \
  --query "[?contains(name, '${ENV_NAME}')].name" -o tsv)

# Get all environment variables from scheduler (for database connection)
SCHEDULER_ENV=$(az containerapp show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "properties.template.containers[0].env" -o json)

# Create temporary init job
az containerapp job create \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME \
  --environment $ACA_ENV_NAME \
  --trigger-type Manual \
  --replica-timeout 600 \
  --replica-retry-limit 1 \
  --image ${ACR_NAME}.azurecr.io/airflow:latest \
  --cpu 0.5 \
  --memory 1Gi \
  --command "/bin/bash" "-c" "airflow db init && airflow users create --username admin --firstname Admin --lastname User --role Admin --email admin@example.com --password admin || true" \
  --registry-server ${ACR_NAME}.azurecr.io

# Copy environment variables from scheduler to job
echo "$SCHEDULER_ENV" | jq -r '.[] | "--set-env-vars \(.name)=\(.value // .secretRef)"' | while read -r env_var; do
  az containerapp job update \
    --name ${ENV_NAME}-db-init-temp \
    --resource-group $RG_NAME \
    $env_var 2>/dev/null || true
done

# Start the job
echo "Starting database initialization job..."
az containerapp job start \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME

# Wait and check status
echo "Waiting for job to complete (this may take 1-2 minutes)..."
sleep 30

# Check execution status
az containerapp job execution list \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME \
  --query "[0].{Name:name, Status:properties.status, StartTime:properties.startTime}" \
  -o table

# Get job logs
echo ""
echo "Job logs:"
EXECUTION_NAME=$(az containerapp job execution list \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME \
  --query "[0].name" -o tsv)

if [ -n "$EXECUTION_NAME" ]; then
  az containerapp job logs show \
    --name ${ENV_NAME}-db-init-temp \
    --resource-group $RG_NAME \
    --execution $EXECUTION_NAME || echo "Logs not available yet"
fi

# Clean up
echo ""
echo "Cleaning up temporary job..."
az containerapp job delete \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME \
  --yes

echo "✅ Database initialization completed"
```

### Option 4: Via Local Connection (If PostgreSQL is Accessible)

If you have network access to PostgreSQL:

```bash
# Install Airflow locally (same version as container)
pip install apache-airflow==2.9.3

# Set connection string
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql://airflow:<password>@<postgres-host>/airflow?sslmode=require"

# Initialize database
airflow db init

# Create admin user
airflow users create \
  --username admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com \
  --password <your-secure-password>
```

## Database Migrations

When upgrading Airflow versions, you may need to run migrations:

```bash
# Check migration status
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --command "airflow db check-migrations"

# Run migrations
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --command "airflow db migrate"
```

## Troubleshooting

### Error: "ClusterExecEndpointWebSocketConnectionError"

**Cause:** `az containerapp exec` command cannot establish WebSocket connection. This is a known limitation of Azure Container Apps.

**Solution:**
1. **Don't use `exec`** - It's unreliable for Container Apps
2. **Check logs instead**:
   ```bash
   az containerapp logs show \
     --name airflow-poc-scheduler \
     --resource-group merzlikin-tf-state-rg \
     --tail 100 --follow
   ```
3. **Use temporary job** for manual initialization (see Option 3 above)
4. **Let automatic initialization work** - The entrypoint script handles it

### Error: "You need to initialize the database"

**Cause:** Database is not initialized or scheduler can't connect to PostgreSQL.

**Solution:**
1. Check PostgreSQL is running:
   ```bash
   az postgres flexible-server show \
     --name merzlikin-airflow-poc-pg \
     --resource-group merzlikin-tf-state-rg
   ```

2. Check scheduler logs:
   ```bash
   az containerapp logs show \
     --name airflow-poc-scheduler \
     --resource-group merzlikin-tf-state-rg \
     --tail 100
   ```

3. Verify database connection string in scheduler environment variables

4. Run manual initialization (see above)

### Error: "Database connection failed"

**Cause:** PostgreSQL firewall rules or connection string incorrect.

**Solution:**
1. Check PostgreSQL firewall allows Azure services:
   ```bash
   az postgres flexible-server firewall-rule list \
     --name merzlikin-airflow-poc-pg \
     --resource-group merzlikin-tf-state-rg
   ```

2. Verify connection string format:
   ```
   postgresql://airflow:<password>@<host>/airflow?sslmode=require
   ```

3. Test connection from scheduler container:
   ```bash
   az containerapp exec \
     --name airflow-poc-scheduler \
     --resource-group merzlikin-tf-state-rg \
     --command "airflow db check"
   ```

### Error: "Timeout waiting for database"

**Cause:** PostgreSQL is not ready or network connectivity issues.

**Solution:**
1. Increase timeout in entrypoint script (currently 60 seconds)
2. Check PostgreSQL status and restart if needed
3. Verify Container Apps can reach PostgreSQL (check network configuration)

### Scheduler keeps restarting

**Cause:** Database initialization fails repeatedly.

**Solution:**
1. Check scheduler logs for specific error
2. Verify PostgreSQL password is correct
3. Ensure PostgreSQL has enough resources (CPU/memory)
4. Check PostgreSQL logs for connection errors

## Database Reset (Caution!)

To completely reset the Airflow database (⚠️ THIS DELETES ALL DATA):

```bash
# Drop and recreate database
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --command "airflow db reset --yes"

# Or manually via psql
psql "host=<postgres-host> port=5432 dbname=airflow user=airflow sslmode=require" \
  -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"

# Then reinitialize
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --command "airflow db init"
```

## Best Practices

1. **Let scheduler handle initialization** - The entrypoint script is designed to handle this automatically
2. **Don't run db init from multiple containers** - Only scheduler should initialize
3. **Backup before migrations** - Always backup PostgreSQL before running migrations
4. **Change default password** - Immediately change the default admin password after first login
5. **Monitor initialization** - Check scheduler logs during first deployment to ensure successful initialization

## Related Files

- `docker/airflow/scripts/entrypoint.sh` - Entrypoint script with initialization logic
- `docker/airflow/Dockerfile` - Airflow image with entrypoint
- `terraform/modules/container_apps/main.tf` - Container Apps configuration
- `terraform/modules/postgresql/main.tf` - PostgreSQL configuration

# Airflow Database Initialization

## Overview

Airflow requires the PostgreSQL database to be initialized with the Airflow schema before the scheduler and other components can start. This is a one-time operation.

## Automatic Initialization (Recommended)

The Airflow Docker image includes an entrypoint script that automatically handles database initialization when the scheduler starts.

### What it does:

1. **Checks database connection** - Waits up to 60 seconds for PostgreSQL to be ready
2. **Initializes database** - Runs `airflow db init` if database is not initialized
3. **Runs migrations** - Applies any pending database migrations
4. **Creates admin user** - Creates default admin user if it doesn't exist
   - Username: `admin`
   - Password: `admin` (⚠️ CHANGE THIS IMMEDIATELY!)
   - Email: `admin@example.com`
   - Role: Admin

### How it works:

The scheduler container uses a custom entrypoint script (`/entrypoint.sh`) that:
- Only runs initialization on the scheduler (not on webserver, worker, or triggerer)
- Is idempotent (safe to run multiple times)
- Handles database connection retries

## Manual Initialization (If Needed)

If automatic initialization fails or you need to manually initialize:

### Option 1: Via Container Exec

```bash
# Execute db init command in scheduler container
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --command "airflow db init"
```

### Option 2: Via Temporary Job

```bash
# Set variables
RG_NAME="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"
ACR_NAME="merzlikinairflowpocacr"

# Get environment ID
ENV_ID=$(az containerapp env list \
  --resource-group $RG_NAME \
  --query "[?contains(name, '${ENV_NAME}')].id" -o tsv)

# Get database connection string from scheduler
DB_CONN=$(az containerapp show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RG_NAME \
  --query "properties.template.containers[0].env[?name=='AIRFLOW__DATABASE__SQL_ALCHEMY_CONN'].value" -o tsv)

# Create one-time init job
az containerapp job create \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME \
  --environment $ENV_ID \
  --trigger-type Manual \
  --replica-timeout 300 \
  --replica-retry-limit 1 \
  --image ${ACR_NAME}.azurecr.io/airflow:latest \
  --cpu 0.5 \
  --memory 1Gi \
  --command "airflow" "db" "init" \
  --env-vars "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=$DB_CONN" \
  --registry-server ${ACR_NAME}.azurecr.io

# Start the job
az containerapp job start \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME

# Wait for completion (check status)
az containerapp job execution list \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME \
  -o table

# Clean up
az containerapp job delete \
  --name ${ENV_NAME}-db-init-temp \
  --resource-group $RG_NAME \
  --yes
```

### Option 3: Via Local Connection

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

# Docker Images

This directory contains Dockerfiles and related files for building custom container images used by the Airflow deployment on Azure Container Apps.

## Directory Structure

```
docker/
├── airflow/              # Airflow container image
│   ├── Dockerfile        # Main Airflow image with Azure providers
│   ├── config/           # Airflow configuration files
│   │   └── webserver_config.py
│   └── plugins/          # Custom Airflow plugins
│       └── aca_job_operator.py
│
└── etl-runner/           # ETL Job container image (DBT runner)
    ├── Dockerfile        # DBT runner image
    ├── entrypoint.sh     # Job entrypoint script
    ├── profiles.yml      # DBT connection profiles
    └── dbt_project/      # DBT project files
        ├── dbt_project.yml
        └── models/
            └── example_model.sql
```

## Images

### 1. Airflow Image

**Base:** `apache/airflow:2.9.3`

**Includes:**
- Azure provider for Airflow (Blob, Key Vault, Container Apps)
- DBT core and SQL Server adapter
- Azure Identity for Managed Identity authentication
- Custom ACA Job operator plugin
- Webserver configuration for RBAC/auth

**Used by:**
- Scheduler Container App
- Webserver Container App
- Worker Container App
- Triggerer Container App

### 2. ETL Runner Image

**Base:** `python:3.11-slim`

**Includes:**
- DBT core and SQL Server adapter
- Azure Identity and Key Vault SDK
- Sample DBT project structure
- Entrypoint script for running DBT with env vars

**Used by:**
- ETL Runner Container App Job (triggered by Airflow Worker)

## Building Images

### Local Build (for testing)

```bash
# Build Airflow image for amd64 (Azure Container Apps architecture)
cd docker/airflow
docker build --platform linux/amd64 -t airflow:local .

# Build ETL runner image
cd docker/etl-runner
docker build --platform linux/amd64 -t etl-runner:local .
```

### Build and Push to ACR

```bash
# Login to ACR
az acr login --name merzlikinairflowpocacr

# Build and push Airflow image
cd docker/airflow
docker build --platform linux/amd64 -t merzlikinairflowpocacr.azurecr.io/airflow:latest .
docker push merzlikinairflowpocacr.azurecr.io/airflow:latest

# Build and push ETL runner image
cd docker/etl-runner
docker build --platform linux/amd64 -t merzlikinairflowpocacr.azurecr.io/etl-runner:latest .
docker push merzlikinairflowpocacr.azurecr.io/etl-runner:latest
```

### Pipeline Build (recommended)

The Azure DevOps pipeline automatically builds and pushes images when `buildImages = true`:

```bash
# Set buildImages parameter to true in pipeline run
# Pipeline will:
# 1. Build both images with --platform linux/amd64
# 2. Tag with both Build.BuildId and 'latest'
# 3. Push to ACR
# 4. Update Container Apps to pull new images
# 5. Run smoke tests
```

## Customization

### Airflow Image

**Add Python packages:**
Edit `airflow/Dockerfile` and add to the `RUN pip install` section.

**Add custom plugins:**
Place Python files in `airflow/plugins/` directory.

**Configure authentication:**
Edit `airflow/config/webserver_config.py` for OAuth, LDAP, etc.

### ETL Runner Image

**Add DBT models:**
Place SQL files in `etl-runner/dbt_project/models/` directory.

**Configure database connections:**
Edit `etl-runner/profiles.yml` to add/modify connection profiles.

**Change database adapter:**
Edit `etl-runner/Dockerfile` to replace `dbt-sqlserver` with `dbt-postgres`, `dbt-snowflake`, etc.

## Environment Variables

### Airflow Container Apps

Set via Terraform in `modules/container_apps/main.tf`:
- `AIRFLOW__CORE__EXECUTOR` - CeleryExecutor
- `AIRFLOW__DATABASE__SQL_ALCHEMY_CONN` - PostgreSQL connection
- `AIRFLOW__CELERY__BROKER_URL` - Redis connection
- `AIRFLOW__CORE__FERNET_KEY` - Encryption key
- `AIRFLOW__WEBSERVER__SECRET_KEY` - Session secret

### ETL Runner Job

Set by Airflow Worker when triggering job:
- `DBT_TARGET` - Target environment (prod, staging, dev)
- `DBT_MODELS` - DBT model selector
- `AIRFLOW_RUN_ID` - Airflow run ID for traceability
- `DBT_DB_HOST` - Database host
- `DBT_DB_NAME` - Database name
- `AZURE_KEY_VAULT_URI` - Key Vault URI for secrets

## Architecture Notes

- Images are built for `linux/amd64` architecture (Azure Container Apps requirement)
- Managed Identity is used for authentication (no stored credentials)
- Both images use multi-stage builds for smaller size
- Entrypoint scripts handle environment variable injection
- DBT uses Managed Identity authentication for SQL Server

## Troubleshooting

**Image pull errors:**
- Verify Managed Identities have `AcrPull` role on ACR
- Check image exists: `az acr repository show-tags --name merzlikinairflowpocacr --repository airflow`

**DBT connection errors:**
- Verify Managed Identity has database access
- Check `profiles.yml` configuration
- Review environment variables in Container App Job

**Build failures:**
- Ensure building for `linux/amd64` platform
- Check Dockerfile syntax and COPY paths
- Verify all referenced files exist

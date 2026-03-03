# Deployment Checklist

Complete checklist for deploying Airflow on Azure Container Apps with Terraform.

## Prerequisites

- [ ] Azure subscription with appropriate permissions
- [ ] Azure CLI installed and logged in
- [ ] Terraform >= 1.5.0 installed
- [ ] Docker installed (for local image builds)
- [ ] Resource group `merzlikin-tf-state-rg` exists
- [ ] Azure DevOps project configured (for pipeline deployment)

## Required Azure Providers

Register these providers in your subscription (one-time operation):

```bash
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.Cache
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.ManagedIdentity
az provider register --namespace Microsoft.App
```

## Step 1: Validate Configuration

- [ ] Run validation script:
```bash
./scripts/validate.sh
```

- [ ] Verify all checks pass
- [ ] Review `terraform/environments/poc/terraform.tfvars`
- [ ] Ensure ACR image names match your configuration

## Step 2: Configure Pipeline Variables

In Azure DevOps, create variable groups:

### Variable Group: `ETL-TFSTATE-BACK`
- `backendResourceGroup` = Resource group for Terraform state
- `backendStorageAccount` = Storage account for Terraform state
- `backendContainer` = Container name for Terraform state

### Variable Group: `tags`
- `DUE_DATE` = Due date for resources (e.g., "6march")

### Variable Group: `DB-VARS` (mark as secret)
- `AIRFLOW_FERNET_KEY` = Generate with: `python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`
- `AIRFLOW_WEBSERVER_SECRET_KEY` = Generate with: `python3 -c "import secrets; print(secrets.token_urlsafe(32))"`
- `POSTGRES_ADMIN_PASSWORD` = Strong password for PostgreSQL

## Step 3: Build and Push Docker Images

### Option A: Local Build (for testing)

```bash
# Login to ACR
az acr login --name merzlikinairflowpocacr

# Build and push Airflow image
cd docker/airflow
docker build --platform linux/amd64 -t merzlikinairflowpocacr.azurecr.io/airflow:latest .
docker push merzlikinairflowpocacr.azurecr.io/airflow:latest

# Build and push ETL runner image
cd ../etl-runner
docker build --platform linux/amd64 -t merzlikinairflowpocacr.azurecr.io/etl-runner:latest .
docker push merzlikinairflowpocacr.azurecr.io/etl-runner:latest
```

### Option B: Pipeline Build (recommended)

- [ ] Push code to repository
- [ ] Run pipeline with parameters:
  - `environment` = poc
  - `action` = apply
  - `buildImages` = true

## Step 4: Deploy Infrastructure

### Option A: Via Pipeline (recommended)

- [ ] Run pipeline with:
  - `environment` = poc
  - `action` = plan
  - Review plan output
- [ ] Run pipeline with:
  - `environment` = poc
  - `action` = apply
  - `buildImages` = true (if images not built yet)

### Option B: Local Deployment

```bash
cd terraform

# Initialize
terraform init \
  -backend-config="resource_group_name=<backend-rg>" \
  -backend-config="storage_account_name=<backend-storage>" \
  -backend-config="container_name=<backend-container>" \
  -backend-config="key=airflow-poc.tfstate"

# Plan
terraform plan \
  -var-file=environments/poc/terraform.tfvars \
  -var="owner=your-email@example.com" \
  -var="duedate=6march" \
  -var="airflow_fernet_key=<key>" \
  -var="airflow_webserver_secret_key=<key>" \
  -var="postgres_admin_password=<password>"

# Apply
terraform apply \
  -var-file=environments/poc/terraform.tfvars \
  -var="owner=your-email@example.com" \
  -var="duedate=6march" \
  -var="airflow_fernet_key=<key>" \
  -var="airflow_webserver_secret_key=<key>" \
  -var="postgres_admin_password=<password>"
```

## Step 5: Assign RBAC Roles

After Terraform completes, assign required roles:

```bash
# Set variables
RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"
PREFIX="merzlikin"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Get Principal IDs
SCHEDULER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-scheduler-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WORKER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-worker-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WEBSERVER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-webserver-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
TRIGGERER_PRINCIPAL_ID=$(az identity show --name ${ENV_NAME}-triggerer-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)

# Get Resource IDs
ACR_NAME=$(echo "${PREFIX}${ENV_NAME}acr" | tr -d '-')
STORAGE_NAME=$(echo "${PREFIX}${ENV_NAME}stor" | tr -d '-')
ACR_ID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
STORAGE_ID=$(az storage account show --name $STORAGE_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

# Assign AcrPull (CRITICAL)
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $WEBSERVER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID
az role assignment create --assignee $TRIGGERER_PRINCIPAL_ID --role "AcrPull" --scope $ACR_ID

# Assign Storage Blob Data Contributor (CRITICAL)
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ID
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Storage Blob Data Contributor" --scope $STORAGE_ID

# Assign Reader (Recommended)
az role assignment create --assignee $SCHEDULER_PRINCIPAL_ID --role "Reader" --scope $RG_SCOPE
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Reader" --scope $RG_SCOPE
az role assignment create --assignee $WEBSERVER_PRINCIPAL_ID --role "Reader" --scope $RG_SCOPE
az role assignment create --assignee $TRIGGERER_PRINCIPAL_ID --role "Reader" --scope $RG_SCOPE

# Assign Container Apps Contributor for Worker (for ETL Job)
az role assignment create --assignee $WORKER_PRINCIPAL_ID --role "Container Apps Contributor" --scope $RG_SCOPE
```

See `RBAC_COMMANDS.md` for detailed instructions.

## Step 6: Verify Deployment

- [ ] Check Container Apps status:
```bash
az containerapp list --resource-group merzlikin-tf-state-rg -o table
```

- [ ] Check scheduler logs for database initialization:
```bash
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group merzlikin-tf-state-rg \
  --tail 100 --follow
```

Look for messages like:
- "Checking database connection..."
- "Database is ready"
- "Starting scheduler..."

If you see "You need to initialize the database", see `DATABASE_INIT.md` for troubleshooting.

- [ ] Get webserver URL:
```bash
terraform output -raw webserver_fqdn
```

- [ ] Access Airflow UI at `https://<webserver-fqdn>`
- [ ] Login with default credentials: admin/admin (⚠️ CHANGE IMMEDIATELY)

- [ ] Check all components are running:
```bash
# Check all container apps
for app in scheduler webserver worker triggerer; do
  echo "=== $app ==="
  az containerapp show \
    --name airflow-poc-$app \
    --resource-group merzlikin-tf-state-rg \
    --query "properties.runningStatus" -o tsv
done
```

## Step 7: Post-Deployment Configuration

- [ ] Upload DAGs to storage:
```bash
az storage file upload-batch \
  --account-name merzlikinairflowpocstor \
  --destination airflow-dags \
  --source ./dags
```

- [ ] Configure Airflow connections and variables via UI
- [ ] Test ETL job execution
- [ ] Set up monitoring and alerts

## Troubleshooting

### Container Apps not starting
- Check RBAC roles are assigned (especially AcrPull)
- Verify images exist in ACR
- Check logs for errors
- If scheduler shows "You need to initialize the database", see `DATABASE_INIT.md`

### Database initialization errors
- Scheduler automatically initializes database on first start
- Check scheduler logs: `az containerapp logs show --name airflow-poc-scheduler --resource-group merzlikin-tf-state-rg --tail 100`
- Verify PostgreSQL is running and accessible
- See `DATABASE_INIT.md` for manual initialization steps

### Image pull errors
- Ensure Managed Identities have AcrPull role
- Verify ACR name in tfvars matches actual ACR

### Database connection errors
- Check PostgreSQL firewall rules
- Verify connection string in Container App environment variables
- Test connection: `az containerapp exec --name airflow-poc-scheduler --resource-group merzlikin-tf-state-rg --command "airflow db check"`

### ETL Job not found
- Set `enable_etl_job = true` in tfvars
- Rebuild images and apply Terraform

## Cleanup

To destroy all resources:

```bash
# Via pipeline
# Set action = destroy

# Or locally
terraform destroy \
  -var-file=environments/poc/terraform.tfvars \
  -var="owner=your-email@example.com" \
  -var="duedate=6march" \
  -var="airflow_fernet_key=<key>" \
  -var="airflow_webserver_secret_key=<key>" \
  -var="postgres_admin_password=<password>"
```

## Production Deployment

For production environment:

1. Copy `terraform/environments/poc/terraform.tfvars` to `terraform/environments/prod/terraform.tfvars`
2. Update values:
   - `env_name = "airflow-prod"`
   - `deployment_mode = "production"`
   - Increase resource SKUs
3. Run pipeline with `environment = prod`
4. Assign RBAC roles for prod environment

## Support

- Pipeline issues: Check Azure DevOps pipeline logs
- Terraform issues: Review plan output and state
- Container Apps issues: Check logs and health status
- RBAC issues: Verify role assignments with `az role assignment list`

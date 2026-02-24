# Quick Reference Guide

## Common Commands

### Local Deployment

```bash
# Deploy PoC environment
./deploy.sh poc apply

# Deploy Production environment
./deploy.sh prod apply

# Plan only (no changes)
./deploy.sh poc plan

# Destroy infrastructure
./deploy.sh poc destroy
```

### Terraform Commands

```bash
cd terraform

# Initialize
terraform init \
  -backend-config="resource_group_name=terraform-state-rg" \
  -backend-config="storage_account_name=tfstateairflow" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=airflow-poc.tfstate"

# Plan
terraform plan -var-file=environments/poc/terraform.tfvars

# Apply
terraform apply -var-file=environments/poc/terraform.tfvars

# Destroy
terraform destroy -var-file=environments/poc/terraform.tfvars

# Show outputs
terraform output

# Show specific output
terraform output -raw acr_login_server
```

### ACR Commands

```bash
# Login to ACR
az acr login --name <acr-name>

# List images
az acr repository list --name <acr-name>

# List tags
az acr repository show-tags --name <acr-name> --repository airflow

# Build and push
docker build -t <acr-name>.azurecr.io/airflow:latest .
docker push <acr-name>.azurecr.io/airflow:latest
```

### Storage Commands

```bash
# Upload DAGs
az storage file upload-batch \
  --account-name <storage-account> \
  --destination airflow-dags \
  --source ./dags

# List DAGs
az storage file list \
  --account-name <storage-account> \
  --share-name airflow-dags

# Download DAG
az storage file download \
  --account-name <storage-account> \
  --share-name airflow-dags \
  --path my_dag.py \
  --dest ./my_dag.py
```

### Container App Commands

```bash
# List container apps
az containerapp list --resource-group airflow-poc-rg -o table

# Show container app details
az containerapp show \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg

# View logs
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg \
  --follow

# Restart container app
az containerapp revision restart \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg

# Access webserver (port forward)
az containerapp tunnel \
  --name airflow-poc-webserver \
  --resource-group airflow-poc-rg \
  --port 8080:8080

# Scale worker manually
az containerapp update \
  --name airflow-poc-worker \
  --resource-group airflow-poc-rg \
  --min-replicas 2 \
  --max-replicas 20
```

### Container App Job Commands

```bash
# List jobs
az containerapp job list --resource-group airflow-poc-rg -o table

# Show job details
az containerapp job show \
  --name airflow-poc-etl-runner \
  --resource-group airflow-poc-rg

# Start job manually
az containerapp job start \
  --name airflow-poc-etl-runner \
  --resource-group airflow-poc-rg

# List job executions
az containerapp job execution list \
  --name airflow-poc-etl-runner \
  --resource-group airflow-poc-rg

# View job logs
az containerapp job logs show \
  --name airflow-poc-etl-runner \
  --resource-group airflow-poc-rg
```

### PostgreSQL Commands

```bash
# Connect to PostgreSQL
psql "host=<postgres-host> port=5432 dbname=airflow user=airflow sslmode=require"

# Run query
az postgres flexible-server execute \
  --name airflow-poc-pg \
  --database-name airflow \
  --admin-user airflow \
  --admin-password <password> \
  --querytext "SELECT * FROM dag LIMIT 10;"

# Show server details
az postgres flexible-server show \
  --name airflow-poc-pg \
  --resource-group airflow-poc-rg
```

### Redis Commands

```bash
# Get Redis connection string
az redis show \
  --name airflow-poc-redis \
  --resource-group airflow-poc-rg \
  --query "hostName" -o tsv

# Get Redis keys
az redis list-keys \
  --name airflow-poc-redis \
  --resource-group airflow-poc-rg

# Connect with redis-cli
redis-cli -h <redis-host> -p 6380 -a <redis-key> --tls
```

## Environment Variables

### Required for Terraform

```bash
export TF_VAR_airflow_fernet_key="<fernet-key>"
export TF_VAR_airflow_webserver_secret_key="<secret-key>"
export TF_VAR_postgres_admin_password="<password>"
```

### Generate Secrets

```bash
# Fernet key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Secret key
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Password
openssl rand -base64 32
```

## Resource Naming Convention

| Resource Type | Naming Pattern | Example |
|---|---|---|
| Resource Group | `{env_name}-rg` | `airflow-poc-rg` |
| ACR | `{env_name}acr` | `airflowpocacr` |
| Storage Account | `{env_name}stor` | `airflowpocstor` |
| PostgreSQL | `{env_name}-pg` | `airflow-poc-pg` |
| Redis | `{env_name}-redis` | `airflow-poc-redis` |
| Key Vault | `{env_name}-kv` | `airflow-poc-kv` |
| Log Analytics | `{env_name}-logs` | `airflow-poc-logs` |
| ACA Environment | `{env_name}-env` | `airflow-poc-env` |
| Container App | `{env_name}-{component}` | `airflow-poc-scheduler` |
| Managed Identity | `{env_name}-{component}-mi` | `airflow-poc-worker-mi` |

## Default Tags

All resources are tagged with:

```hcl
tags = {
  owner       = "user@gmail.com"  # Configurable via parameter
  duedate     = "6march"          # Configurable via variable
  managedwith = "terraform"       # Fixed
}
```

## Resource Sizing

### PoC Environment

| Component | CPU | Memory | Min Replicas | Max Replicas |
|---|---|---|---|---|
| Scheduler | 0.5 | 1Gi | 1 | 1 |
| Webserver | 0.25 | 0.5Gi | 0 | 1 |
| Worker | 0.5 | 1Gi | 0 | 10 |
| Triggerer | 0.25 | 0.5Gi | 1 | 1 |
| ETL Runner | 1.0 | 2Gi | - | - |

### Production Environment

| Component | CPU | Memory | Min Replicas | Max Replicas |
|---|---|---|---|---|
| Scheduler | 1.0 | 2Gi | 2 | 2 |
| Webserver | 0.5 | 1Gi | 1 | 1 |
| Worker | 1.0 | 2Gi | 0 | 10 |
| Triggerer | 0.25 | 0.5Gi | 1 | 1 |
| ETL Runner | 1.0 | 2Gi | - | - |

## Terraform Outputs

```bash
# Get all outputs
terraform output

# Specific outputs
terraform output -raw acr_login_server
terraform output -raw webserver_fqdn
terraform output -raw storage_account_name
terraform output -raw postgres_host
terraform output -raw redis_host
terraform output -raw key_vault_uri
terraform output -raw etl_runner_job_id
terraform output -raw worker_principal_id
```

## Troubleshooting

### Check Container App Status

```bash
az containerapp show \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg \
  --query "properties.runningStatus"
```

### View Recent Logs

```bash
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg \
  --tail 100
```

### Check Revisions

```bash
az containerapp revision list \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg \
  -o table
```

### Test Database Connection

```bash
psql "host=<postgres-host> port=5432 dbname=airflow user=airflow sslmode=require" \
  -c "SELECT version();"
```

### Test Redis Connection

```bash
redis-cli -h <redis-host> -p 6380 -a <redis-key> --tls PING
```

## Useful Azure CLI Queries

```bash
# List all resources in resource group
az resource list --resource-group airflow-poc-rg -o table

# Get resource costs
az consumption usage list \
  --start-date 2024-03-01 \
  --end-date 2024-03-31 \
  --query "[?contains(instanceName, 'airflow-poc')]"

# Check managed identity assignments
az role assignment list \
  --assignee <principal-id> \
  -o table
```

## Pipeline Quick Actions

### Run Plan

```bash
# Via Azure CLI
az pipelines run \
  --name "Airflow-ACA-Terraform" \
  --parameters environment=poc action=plan owner=user@gmail.com
```

### Approve Production Deployment

1. Go to Pipelines → Environments → prod
2. Click on pending deployment
3. Review changes
4. Click Approve or Reject

## File Locations

```
airflow-aca-tf/
├── terraform/
│   ├── main.tf                          # Root module
│   ├── variables.tf                     # Input variables
│   ├── outputs.tf                       # Outputs
│   ├── modules/                         # Reusable modules
│   └── environments/
│       ├── poc/terraform.tfvars         # PoC config
│       └── prod/terraform.tfvars        # Prod config
├── pipelines/
│   └── azure-pipelines.yml              # CI/CD pipeline
├── deploy.sh                            # Local deployment script
├── README.md                            # Main documentation
├── PIPELINE_SETUP.md                    # Pipeline setup guide
└── QUICK_REFERENCE.md                   # This file
```

## Support

For issues or questions:
1. Check logs: `az containerapp logs show`
2. Review Terraform state: `terraform show`
3. Verify resources: `az resource list`
4. Check Azure Portal for resource status

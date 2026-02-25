# Airflow on Azure Container Apps - Terraform

Terraform infrastructure as code for deploying Apache Airflow with CeleryExecutor on Azure Container Apps.

## Architecture

This Terraform configuration deploys the same architecture as the Bicep version:

- Azure Container Registry (ACR) for storing container images
- Azure Container Apps Environment with Log Analytics
- Airflow components: Scheduler, Webserver, Worker, Triggerer
- ACA Job for ETL runner
- PostgreSQL Flexible Server for metadata database
- Azure Cache for Redis for Celery broker
- Azure Storage Account with File Share (DAGs) and Blob Container (logs)
- Azure Key Vault for secrets
- Managed Identities with RBAC assignments

## Prerequisites

- Azure CLI 2.57+
- Terraform 1.5.0+
- Azure subscription with appropriate permissions
- Azure DevOps project (for pipeline)

## Project Structure

```
airflow-aca-tf/
├── terraform/
│   ├── main.tf                    # Root module
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── modules/
│   │   ├── acr/                   # Azure Container Registry
│   │   ├── storage/               # Storage Account, File Share, Blob
│   │   ├── postgresql/            # PostgreSQL Flexible Server
│   │   ├── redis/                 # Azure Cache for Redis
│   │   ├── log_analytics/         # Log Analytics Workspace
│   │   ├── key_vault/             # Azure Key Vault
│   │   ├── managed_identity/      # User-assigned identities
│   │   ├── aca_environment/       # ACA Environment
│   │   └── container_apps/        # Container Apps & Jobs
│   └── environments/
│       ├── poc/
│       │   └── terraform.tfvars   # PoC environment variables
│       └── prod/
│           └── terraform.tfvars   # Production environment variables
└── pipelines/
    └── azure-pipelines.yml        # Azure DevOps pipeline
```

## Common Tags

All resources are tagged with:
- `owner`: Owner email (default: user@gmail.com, can be overridden via pipeline parameter)
- `duedate`: Due date (default: 6march)
- `managedwith`: terraform

## Quick Start - Local Deployment

### 1. Generate Secrets

```bash
# Generate Airflow Fernet key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Generate Airflow webserver secret key
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# Generate PostgreSQL password
openssl rand -base64 32
```

### 2. Set Environment Variables

```bash
export TF_VAR_airflow_fernet_key="<your-fernet-key>"
export TF_VAR_airflow_webserver_secret_key="<your-secret-key>"
export TF_VAR_postgres_admin_password="<your-postgres-password>"
```

### 3. Initialize Terraform Backend

First, create a storage account for Terraform state:

```bash
az group create --name terraform-state-rg --location westeurope

az storage account create \
  --name tfstateairflow \
  --resource-group terraform-state-rg \
  --location westeurope \
  --sku Standard_LRS

az storage container create \
  --name tfstate \
  --account-name tfstateairflow
```
az role assignment create \
  --assignee-object-id <SPid> \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Account Blob Contributor" \
  --scope /subscriptions/<sub_id>

az provider register -n Microsoft.CustomProviders
az provider register -n Microsoft.DocumentDB
az provider register -n Microsoft.ContainerInstance
az provider register -n Microsoft.Databricks
az provider register -n Microsoft.EventGrid
az provider register -n Microsoft.ManagedServices

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

az role assignment create \
  --assignee-object-id <SPid> \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope /subscriptions/<sub_id>


### 4. Deploy Infrastructure

```bash
cd terraform

# Initialize Terraform
terraform init \
  -backend-config="resource_group_name=terraform-state-rg" \
  -backend-config="storage_account_name=tfstateairflow" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=airflow-poc.tfstate"

# Plan deployment
terraform plan \
  -var-file=environments/poc/terraform.tfvars \
  -out=tfplan

# Apply deployment
terraform apply tfplan
```

### 5. Build and Push Images to ACR

```bash
# Get ACR name from Terraform output
ACR_NAME=$(terraform output -raw acr_login_server | cut -d'.' -f1)

# Login to ACR
az acr login --name $ACR_NAME

# Build and push Airflow image
cd ../airflow-aca/airflow
docker build -t $ACR_NAME.azurecr.io/airflow:latest .
docker push $ACR_NAME.azurecr.io/airflow:latest

# Build and push ETL runner image
cd etl-runner
docker build -t $ACR_NAME.azurecr.io/etl-runner:latest .
docker push $ACR_NAME.azurecr.io/etl-runner:latest
```

### 6. Upload DAGs

```bash
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)

az storage file upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --destination airflow-dags \
  --source ../dags
```

### 7. Access Webserver

```bash
WEBSERVER_NAME=$(terraform output -raw webserver_fqdn | cut -d'.' -f1)
RESOURCE_GROUP="airflow-poc-rg"

az containerapp tunnel \
  --name $WEBSERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --port 8080:8080
```

Open http://localhost:8080

## Azure DevOps Pipeline

### Setup

1. Create a service connection in Azure DevOps:
   - Project Settings → Service connections
   - New service connection → Azure Resource Manager
   - Name: `Azure-ServiceConnection`

2. Create pipeline variables (Library):
   - `AIRFLOW_FERNET_KEY` (secret)
   - `AIRFLOW_WEBSERVER_SECRET_KEY` (secret)
   - `POSTGRES_ADMIN_PASSWORD` (secret)

3. Create environments:
   - Pipelines → Environments
   - Create `poc` and `prod` environments
   - Add approvals for `prod` environment

### Run Pipeline

The pipeline supports three actions:
- `plan`: Validate and plan infrastructure changes
- `apply`: Apply infrastructure changes and build/push images
- `destroy`: Destroy infrastructure

Parameters:
- `environment`: poc or prod
- `action`: plan, apply, or destroy
- `owner`: Owner email for tagging (default: user@gmail.com)

### Pipeline Stages

1. **Validate**: Format check and validation
2. **Plan**: Generate execution plan
3. **Apply**: Deploy infrastructure and push images to ACR
4. **Destroy**: Remove all infrastructure

## Environment Configuration

### PoC Environment

- Deployment mode: poc
- PostgreSQL: Burstable B1ms
- Redis: Standard C1
- ACR: Basic
- Scheduler: 1 replica, 0.5 CPU, 1Gi RAM
- Webserver: 0-1 replicas, 0.25 CPU, 0.5Gi RAM
- Worker: 0-10 replicas, 0.5 CPU, 1Gi RAM

### Production Environment

- Deployment mode: production
- PostgreSQL: Standard_D2ds_v4 with Zone HA
- Redis: Premium P1
- ACR: Standard
- Scheduler: 2 replicas (HA), 1.0 CPU, 2Gi RAM
- Webserver: 1 replica, 0.5 CPU, 1Gi RAM
- Worker: 0-10 replicas, 1.0 CPU, 2Gi RAM

## Customization

### Override Tags

Via pipeline parameter:
```yaml
parameters:
  - name: owner
    value: 'custom@email.com'
```

Via Terraform CLI:
```bash
terraform apply \
  -var-file=environments/poc/terraform.tfvars \
  -var="owner=custom@email.com" \
  -var="duedate=15march"
```

### Change Container Images

Edit `terraform.tfvars`:
```hcl
airflow_image    = "your-acr.azurecr.io/airflow:v2.9.3"
etl_runner_image = "your-acr.azurecr.io/etl-runner:v1.0.0"
```

## Outputs

After deployment, Terraform outputs:

- `acr_login_server`: ACR URL
- `webserver_fqdn`: Airflow webserver URL
- `etl_runner_job_id`: ETL runner job resource ID
- `postgres_host`: PostgreSQL FQDN
- `redis_host`: Redis hostname
- `storage_account_name`: Storage account name
- `key_vault_uri`: Key Vault URI

## Cost Estimate

Same as Bicep deployment:

### PoC: ~$71-87/month
- Scheduler: ~$15-20
- Triggerer: ~$8-12
- Webserver: ~$3-8
- Workers: pay per task
- PostgreSQL: ~$15
- Redis: ~$25
- Storage: ~$2
- Log Analytics: ~$3-5

### Production: ~$200-300/month
- Higher SKUs for PostgreSQL and Redis
- More replicas for HA
- Additional monitoring costs

## Cleanup

```bash
# Via Terraform
terraform destroy \
  -var-file=environments/poc/terraform.tfvars

# Via Pipeline
# Set action parameter to 'destroy'
```

## Differences from Bicep

1. **ACR Added**: Terraform version includes Azure Container Registry for storing images
2. **Module Structure**: Infrastructure split into reusable modules
3. **Environment Files**: Separate tfvars files for poc/prod
4. **Pipeline Integration**: Azure DevOps pipeline with build/push steps
5. **Tags Centralized**: Common tags defined only in main.tf

## Troubleshooting

### Terraform State Lock

If state is locked:
```bash
terraform force-unlock <lock-id>
```

### ACR Authentication

If ACR push fails:
```bash
az acr login --name <acr-name>
```

### Container App Not Starting

Check logs:
```bash
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg \
  --follow
```

## References

- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)

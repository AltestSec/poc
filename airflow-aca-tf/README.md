# Airflow on Azure Container Apps - Terraform

Terraform infrastructure as code for deploying Apache Airflow with CeleryExecutor on Azure Container Apps with **enterprise-grade security and private networking**.

## 🚀 Quick Start

New to this deployment? Start here: **[QUICK_START.md](QUICK_START.md)**

For detailed validation: **[TESTING_GUIDE.md](TESTING_GUIDE.md)**

## Architecture

This Terraform configuration deploys a fully private and secure architecture:

- **Private Networking**: All services deployed in VNet with no public access
- **Azure Firewall**: Controls all egress traffic with application and network rules
- **Private Endpoints**: ACR, Storage (Blob & File) accessible only within VNet
- **Private PostgreSQL**: Deployed in delegated subnet with private DNS
- Azure Container Registry (ACR) for storing container images (Premium SKU)
- Azure Container Apps Environment with Log Analytics (VNet-integrated)
- Airflow components: Scheduler, Webserver, Worker, Triggerer
- ACA Job for ETL runner with network security tests
- PostgreSQL Flexible Server for metadata database (private)
- Azure Cache for Redis for Celery broker
- Azure Storage Account with File Share (DAGs) and Blob Container (logs) - private
- Azure Key Vault for secrets
- Managed Identities with RBAC assignments
- User Defined Routes (UDR) for traffic control

See [PRIVATE_NETWORK_SETUP.md](PRIVATE_NETWORK_SETUP.md) for detailed network architecture and security configuration.

## Prerequisites

- Azure CLI 2.57+
- Terraform 1.5.0+
- Azure subscription with appropriate permissions
- Azure DevOps project (for pipeline)
- **Pre-existing Resource Group** (not managed by Terraform)
- **Docker** (for building container images)

### Important: Network Security

This deployment creates a **fully private infrastructure** with:
- No public access to ACR, Storage, or PostgreSQL
- All egress traffic controlled by Azure Firewall
- Private endpoints for all Azure services
- User Defined Routes (UDR) for traffic routing

See [PRIVATE_NETWORK_SETUP.md](PRIVATE_NETWORK_SETUP.md) for complete details.

### Important: Resource Group

The resource group must be created manually before running Terraform. Terraform will use it as a data source but will not manage it.

```bash
# Create resource group (one-time operation)
az group create \
  --name merzlikin-tf-state-rg \
  --location westeurope
```

Update `terraform.tfvars` with your resource group name:
```hcl
resource_group_name = "merzlikin-tf-state-rg"
```

### Important: Provider Registration

This Terraform configuration uses `skip_provider_registration = true` to avoid requiring wide permissions on the Service Principal. Before running Terraform, ensure the following Azure resource providers are registered in your subscription:

```bash
# Register required resource providers (requires Subscription Contributor or Owner role)
az provider register --namespace Microsoft.App
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.DBforPostgreSQL
az provider register --namespace Microsoft.Cache
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.ManagedIdentity

# Check registration status
az provider show --namespace Microsoft.App --query "registrationState"
az provider show --namespace Microsoft.ContainerRegistry --query "registrationState"
```

**Note:** Provider registration is a one-time operation per subscription and requires elevated permissions. After registration, the Service Principal used by Terraform only needs Contributor role on the resource group.

## Project Structure

```
airflow-aca-tf/
├── terraform/
│   ├── main.tf                    # Root module
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   ├── modules/
│   │   ├── network/               # VNet, Firewall, Routes, Private DNS
│   │   ├── acr/                   # Azure Container Registry (Private)
│   │   ├── storage/               # Storage Account, File Share, Blob (Private)
│   │   ├── postgresql/            # PostgreSQL Flexible Server (Private)
│   │   ├── redis/                 # Azure Cache for Redis
│   │   ├── log_analytics/         # Log Analytics Workspace
│   │   ├── key_vault/             # Azure Key Vault
│   │   ├── managed_identity/      # User-assigned identities
│   │   ├── aca_environment/       # ACA Environment (VNet-integrated)
│   │   ├── container_apps/        # Container Apps & Jobs
│   │   └── windows_vm/            # Windows VM Jump Box (Optional)
│   └── environments/
│       ├── poc/
│       │   └── terraform.tfvars   # PoC environment variables
│       └── prod/
│           └── terraform.tfvars   # Production environment variables
├── docker/                        # Container images
├── dags/                          # Airflow DAGs
├── scripts/                       # Helper scripts
└── pipelines/                     # Azure DevOps pipeline
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

**Note:** If you get a 403 error about `Microsoft.Authorization/roleAssignments/write`, this is expected. Role assignments have been removed from Terraform and must be assigned manually (see step 4a).

### 4a. Assign RBAC Roles (Required!)

After Terraform completes, assign roles to managed identities:

```bash
cd ..
./assign-roles.sh merzlikin-tf-state-rg airflow-poc
```

Or manually:
```bash
RESOURCE_GROUP="merzlikin-tf-state-rg"
RG_SCOPE="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP"

# Get Principal IDs
SCHEDULER_PRINCIPAL_ID=$(az identity show --name airflow-poc-scheduler-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WORKER_PRINCIPAL_ID=$(az identity show --name airflow-poc-worker-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
WEBSERVER_PRINCIPAL_ID=$(az identity show --name airflow-poc-webserver-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)
TRIGGERER_PRINCIPAL_ID=$(az identity show --name airflow-poc-triggerer-mi --resource-group $RESOURCE_GROUP --query principalId -o tsv)

# Assign Contributor role on RG
for PRINCIPAL in $SCHEDULER_PRINCIPAL_ID $WORKER_PRINCIPAL_ID $WEBSERVER_PRINCIPAL_ID $TRIGGERER_PRINCIPAL_ID; do
  az role assignment create --assignee $PRINCIPAL --role "Contributor" --scope $RG_SCOPE
done
```

See [RBAC_SETUP.md](RBAC_SETUP.md) for detailed instructions.

### 5. Build and Push Images to ACR

Since ACR is private, build from within the VNet using a Windows VM:

**Option 1: Windows VM (Recommended for Development)**

```bash
# Enable VM in terraform.tfvars
enable_windows_vm     = true
vm_admin_password     = "YourComplexPassword123!"
allowed_rdp_source_ip = "$(curl -s ifconfig.me)/32"

# Deploy VM
terraform apply

# Get VM IP and connect
terraform output vm_public_ip
# RDP to VM, then build images there
```

See [WINDOWS_VM_GUIDE.md](WINDOWS_VM_GUIDE.md) for complete instructions.

**Option 2: Azure DevOps Pipeline**

Use the included pipeline which builds from Azure-hosted agents with VNet access.

### 6. Upload DAGs

```bash
STORAGE_ACCOUNT=$(terraform output -raw storage_account_name)

az storage file upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --destination airflow-dags \
  --source ../dags
```

### 7. Access Webserver

Since the webserver is internal-only, you need to use Azure Container Apps tunnel or deploy a jump box:

```bash
WEBSERVER_NAME=$(terraform output -raw webserver_fqdn | cut -d'.' -f1)
RESOURCE_GROUP="airflow-poc-rg"

az containerapp tunnel \
  --name $WEBSERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --port 8080:8080
```

Open http://localhost:8080

### 8. Test ETL Job and Network Security

Run the automated security tests:

```bash
./scripts/test-etl-job.sh <resource-group> <env-name>
```

This validates:
- ETL job execution
- Network egress restrictions
- Firewall rules effectiveness

See [PRIVATE_NETWORK_SETUP.md](PRIVATE_NETWORK_SETUP.md) for detailed testing procedures.

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

### Use Custom Prefix for Unique Resource Names

By default, resources are named using `env_name` only (e.g., `airflow-poc-pg`, `airflowpocacr`). To ensure globally unique names (especially for ACR, Storage, and Key Vault), you can provide a custom prefix that will be combined with the environment name:

**Naming Pattern:**
- **Without prefix:** `{env_name}-{resource}` → `airflow-poc-pg`
- **With prefix:** `{prefix}-{env_name}-{resource}` → `merzlikin-airflow-poc-pg`

Via Terraform CLI:
```bash
terraform apply \
  -var-file=environments/poc/terraform.tfvars \
  -var="prefix=merzlikin"
```

Via `terraform.tfvars`:
```hcl
prefix = "merzlikin"
```

This will create resources like:
- ACR: `merzlikinairflowpocacr` (hyphens removed)
- Storage: `merzlikinairflowpocstor` (hyphens removed)
- Key Vault: `merzlikin-airflow-poc-kv`
- PostgreSQL: `merzlikin-airflow-poc-pg`
- Redis: `merzlikin-airflow-poc-redis`
- Log Analytics: `merzlikin-airflow-poc-logs`

**Benefits:**
- Globally unique names across Azure
- Clear identification of ownership
- Environment name still visible in resource names
- Easy to filter resources by prefix in Azure Portal

**Note:** ACR and Storage names must be globally unique and cannot contain hyphens.

### Override Tags

Tags are configured via pipeline parameters and variables:

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

### PoC: ~$246-262/month
- Scheduler: ~$15-20
- Triggerer: ~$8-12
- Webserver: ~$3-8
- Workers: pay per task
- PostgreSQL: ~$15
- Redis: ~$25
- Storage: ~$2
- Log Analytics: ~$3-5
- **Azure Firewall (Basic): ~$146**
- **Private Endpoints (4): ~$29**
- ACR (Premium): ~$0

### Production: ~$1,141-1,241/month
- Higher SKUs for PostgreSQL and Redis
- More replicas for HA
- Additional monitoring costs
- **Azure Firewall (Standard): ~$912**
- **Private Endpoints (4): ~$29**
- ACR (Premium): ~$0

**Note:** Private networking adds ~$175/month (PoC) or ~$941/month (Production) for enhanced security.

See [PRIVATE_NETWORK_SETUP.md](PRIVATE_NETWORK_SETUP.md) for detailed cost breakdown.

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

### Network Connectivity Issues

If containers can't access resources:

```bash
# Test DNS resolution
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg \
  --command "nslookup <acr-name>.azurecr.io"

# Check firewall logs
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' | take 20"
```

See [PRIVATE_NETWORK_SETUP.md](PRIVATE_NETWORK_SETUP.md) for comprehensive troubleshooting.

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

- [Private Network Setup Guide](PRIVATE_NETWORK_SETUP.md)
- [Secure Deployment Checklist](SECURE_DEPLOYMENT_CHECKLIST.md)
- [Securing Network Egress in Azure Container Apps](https://techcommunity.microsoft.com/blog/azurepaasblog/securing-network-egress-in-azure-container-apps/3915548)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)
- [Azure Firewall Documentation](https://learn.microsoft.com/azure/firewall/)
- [Apache Airflow Documentation](https://airflow.apache.org/docs/)

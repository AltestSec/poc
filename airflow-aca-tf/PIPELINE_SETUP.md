# Azure DevOps Pipeline Setup Guide

This guide walks you through setting up the Azure DevOps pipeline for deploying Airflow on Azure Container Apps using Terraform.

## Prerequisites

- Azure DevOps organization and project
- Azure subscription with Owner or Contributor role
- Repository connected to Azure DevOps

## Step 1: Create Azure Service Connection

1. Navigate to your Azure DevOps project
2. Go to **Project Settings** (bottom left)
3. Under **Pipelines**, click **Service connections**
4. Click **New service connection**
5. Select **Azure Resource Manager**
6. Choose **Service principal (automatic)**
7. Configure:
   - Subscription: Select your Azure subscription
   - Resource group: Leave empty (subscription level)
   - Service connection name: `Azure-ServiceConnection`
   - Grant access permission to all pipelines: ✓
8. Click **Save**

## Step 2: Create Terraform State Storage

The pipeline requires a storage account for Terraform state. Create it manually:

```bash
# Login to Azure
az login

# Create resource group
az group create \
  --name terraform-state-rg \
  --location westeurope

# Create storage account
az storage account create \
  --name tfstateairflow \
  --resource-group terraform-state-rg \
  --location westeurope \
  --sku Standard_LRS \
  --encryption-services blob

# Create container
az storage container create \
  --name tfstate \
  --account-name tfstateairflow
```

## Step 3: Create Variable Library

1. In Azure DevOps, go to **Pipelines** → **Library**
2. Click **+ Variable group**
3. Name: `airflow-secrets`
4. Add the following variables:

### Required Secret Variables

| Variable Name | Value | Secret |
|---|---|---|
| `AIRFLOW_FERNET_KEY` | Generate with command below | ✓ |
| `AIRFLOW_WEBSERVER_SECRET_KEY` | Generate with command below | ✓ |
| `POSTGRES_ADMIN_PASSWORD` | Generate with command below | ✓ |

### Generate Secrets

```bash
# Airflow Fernet Key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

# Airflow Webserver Secret Key
python3 -c "import secrets; print(secrets.token_urlsafe(32))"

# PostgreSQL Admin Password
openssl rand -base64 32
```

5. Click the lock icon next to each variable to mark it as secret
6. Click **Save**

## Step 4: Create Environments

1. Go to **Pipelines** → **Environments**
2. Click **New environment**
3. Create two environments:

### POC Environment
- Name: `poc`
- Description: PoC environment for Airflow
- No approvals needed

### Production Environment
- Name: `prod`
- Description: Production environment for Airflow
- Add approvals:
  - Click on the environment
  - Click the three dots (⋮) → **Approvals and checks**
  - Add **Approvals**
  - Add approvers (team members who can approve production deployments)
  - Click **Create**

## Step 5: Create Pipeline

1. Go to **Pipelines** → **Pipelines**
2. Click **New pipeline**
3. Select your repository source (Azure Repos Git, GitHub, etc.)
4. Select your repository
5. Choose **Existing Azure Pipelines YAML file**
6. Path: `/airflow-aca-tf/pipelines/azure-pipelines.yml`
7. Click **Continue**
8. Review the pipeline YAML
9. Click **Save** (don't run yet)

## Step 6: Link Variable Library to Pipeline

1. Click **Edit** on your pipeline
2. Click the three dots (⋮) → **Triggers**
3. Go to **Variables** tab
4. Click **Variable groups**
5. Click **Link variable group**
6. Select `airflow-secrets`
7. Click **Link**
8. Click **Save**

## Step 7: Grant Pipeline Permissions

The pipeline needs permissions to access the service connection and environments:

1. Go to **Project Settings** → **Service connections**
2. Click on `Azure-ServiceConnection`
3. Click the three dots (⋮) → **Security**
4. Add your pipeline to the list of authorized pipelines

## Step 8: Run Pipeline

### First Run (Plan)

1. Go to **Pipelines** → **Pipelines**
2. Select your pipeline
3. Click **Run pipeline**
4. Configure parameters:
   - **environment**: `poc`
   - **action**: `plan`
   - **owner**: Your email (e.g., `user@gmail.com`)
5. Click **Run**
6. Monitor the pipeline execution
7. Review the Terraform plan in the logs

### Deploy Infrastructure (Apply)

1. Click **Run pipeline** again
2. Configure parameters:
   - **environment**: `poc`
   - **action**: `apply`
   - **owner**: Your email
3. Click **Run**
4. The pipeline will:
   - Validate Terraform code
   - Generate execution plan
   - Wait for approval (if configured)
   - Apply infrastructure
   - Build and push Docker images to ACR
5. Monitor the deployment

### Production Deployment

1. Click **Run pipeline**
2. Configure parameters:
   - **environment**: `prod`
   - **action**: `apply`
   - **owner**: Your email
3. Click **Run**
4. The pipeline will wait for approval before deploying to production
5. Approvers will receive a notification
6. After approval, deployment proceeds

## Pipeline Parameters

| Parameter | Description | Values | Default |
|---|---|---|---|
| `environment` | Target environment | `poc`, `prod` | `poc` |
| `action` | Action to perform | `plan`, `apply`, `destroy` | `plan` |
| `owner` | Owner email for tagging | Any email | `user@gmail.com` |

## Pipeline Stages

### 1. Validate
- Installs Terraform
- Runs `terraform init`
- Runs `terraform validate`
- Runs `terraform fmt -check`

### 2. Plan
- Generates Terraform execution plan
- Publishes plan as pipeline artifact
- Runs for all actions

### 3. Apply
- Downloads plan artifact
- Applies infrastructure changes
- Builds Docker images
- Pushes images to ACR
- Only runs when `action=apply`

### 4. Destroy
- Destroys all infrastructure
- Only runs when `action=destroy`
- Requires manual confirmation

## Customizing the Pipeline

### Change Backend Storage

Edit `azure-pipelines.yml`:

```yaml
variables:
  - name: backendResourceGroup
    value: 'your-terraform-state-rg'
  - name: backendStorageAccount
    value: 'yourtfstate'
  - name: backendContainer
    value: 'tfstate'
```

### Change Terraform Version

Edit `azure-pipelines.yml`:

```yaml
variables:
  - name: terraformVersion
    value: '1.6.0'  # Update to desired version
```

### Add Additional Environments

1. Create new environment in Azure DevOps
2. Create new tfvars file: `terraform/environments/staging/terraform.tfvars`
3. Add environment to pipeline parameters:

```yaml
parameters:
  - name: environment
    values:
      - poc
      - staging  # Add new environment
      - prod
```

## Monitoring Pipeline Execution

### View Logs

1. Click on a running or completed pipeline run
2. Click on a stage (Validate, Plan, Apply)
3. Click on a job
4. View detailed logs for each step

### Download Artifacts

1. Click on a completed pipeline run
2. Go to **Artifacts** tab
3. Download `tfplan-<environment>` to review the plan locally

### View Terraform Outputs

After successful Apply stage:

1. Go to the Apply job logs
2. Scroll to the "Terraform Apply" step
3. View outputs at the end:
   - ACR login server
   - Webserver FQDN
   - Storage account name
   - etc.

## Troubleshooting

### Service Connection Permission Denied

**Error**: `The pipeline is not valid. Job Apply: Step AzureCLI input ConnectedServiceNameARM references service connection Azure-ServiceConnection which could not be found.`

**Solution**: Grant pipeline access to service connection (Step 7)

### Terraform State Lock

**Error**: `Error acquiring the state lock`

**Solution**: 
1. Go to Azure Portal
2. Navigate to storage account `tfstateairflow`
3. Go to Containers → `tfstate`
4. Delete the `.terraform.tflock.info` blob
5. Re-run pipeline

### Secret Variables Not Found

**Error**: `TF_VAR_airflow_fernet_key is not set`

**Solution**: Link variable library to pipeline (Step 6)

### ACR Push Failed

**Error**: `unauthorized: authentication required`

**Solution**: 
1. Ensure service connection has Contributor role on subscription
2. Check ACR admin user is enabled (done by Terraform)
3. Verify managed identity has AcrPush role

### Container App Not Starting

**Solution**:
1. Check container app logs:
```bash
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group airflow-poc-rg \
  --follow
```
2. Verify environment variables are set correctly
3. Check if images exist in ACR

## Security Best Practices

1. **Never commit secrets** to repository
2. **Use variable groups** for sensitive data
3. **Enable approvals** for production environment
4. **Limit service connection** scope to specific resource groups (optional)
5. **Rotate secrets** regularly
6. **Use Azure Key Vault** for production secrets (optional enhancement)

## Next Steps

After successful deployment:

1. Upload DAGs to storage account
2. Access Airflow webserver
3. Configure Airflow connections and variables
4. Set up monitoring and alerts
5. Configure backup policies

## Additional Resources

- [Azure DevOps Pipelines Documentation](https://learn.microsoft.com/azure/devops/pipelines/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Container Apps Documentation](https://learn.microsoft.com/azure/container-apps/)

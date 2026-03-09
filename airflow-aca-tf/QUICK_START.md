# Quick Start Guide - Private Airflow on Azure Container Apps

Get your secure, private Airflow deployment running in minutes.

## Prerequisites

- Azure CLI 2.57+
- Terraform 1.5.0+
- Docker (for building images)
- Azure subscription with Contributor role
- Pre-created resource group

## 5-Minute Deployment

### Step 1: Generate Secrets (1 min)

```bash
# Airflow Fernet key
export TF_VAR_airflow_fernet_key=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

# Airflow webserver secret
export TF_VAR_airflow_webserver_secret_key=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")

# PostgreSQL password
export TF_VAR_postgres_admin_password=$(openssl rand -base64 32)
```

### Step 2: Configure Variables (1 min)

Edit `terraform/environments/poc/terraform.tfvars`:

```hcl
env_name            = "airflow-poc"
resource_group_name = "your-resource-group"
location            = "westeurope"
deployment_mode     = "poc"
owner               = "your-email@company.com"
duedate             = "31dec2024"

# Firewall (optional - see FIREWALL_DECISION_GUIDE.md)
enable_firewall     = false  # Set to true only if you need egress control

# Windows VM (optional - for building Docker images)
enable_windows_vm     = true   # Recommended for development
vm_admin_password     = "YourComplexPassword123!"  # Change this!
allowed_rdp_source_ip = "$(curl -s ifconfig.me)/32"  # Your IP only
```

**Note:** 
- Firewall adds $146-912/month - only for egress control
- Windows VM adds $30-40/month - useful for building images
- See [CONFIGURATION_OPTIONS.md](CONFIGURATION_OPTIONS.md) for guidance

### Step 3: Deploy Infrastructure (10-15 min)

```bash
cd terraform

# Initialize
terraform init \
  -backend-config="resource_group_name=terraform-state-rg" \
  -backend-config="storage_account_name=tfstateairflow" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=airflow-poc.tfstate"

# Deploy
terraform apply -var-file=environments/poc/terraform.tfvars
```

### Step 4: Assign RBAC Roles (2 min)

```bash
cd ..
./assign-roles.sh your-resource-group airflow-poc
```

### Step 5: Build & Push Images (5-10 min)

**Option A: Using Windows VM (Recommended)**

```bash
# Get VM IP
terraform output vm_public_ip

# Connect via RDP (Windows)
mstsc /v:<vm-ip>

# On VM (PowerShell):
# 1. Wait for Docker Desktop to install (first login)
# 2. Restart VM
# 3. Start Docker Desktop
# 4. Run:
az login
$ACR_NAME = "airflowpocacr"
az acr login --name $ACR_NAME
cd C:\Users\azureuser\Desktop
git clone <your-repo>
cd <your-repo>\docker\airflow
docker build -t ${ACR_NAME}.azurecr.io/airflow:latest .
docker push ${ACR_NAME}.azurecr.io/airflow:latest
```

See [WINDOWS_VM_GUIDE.md](WINDOWS_VM_GUIDE.md) for complete instructions.

**Option B: Using Azure DevOps Pipeline**

Use the included pipeline which builds from Azure-hosted agents.

### Step 6: Validate Deployment (2 min)

```bash
cd ../..
./scripts/validate-deployment.sh your-resource-group airflow-poc
```

### Step 7: Access Airflow (1 min)

```bash
./scripts/access-webserver.sh your-resource-group airflow-poc
```

Open http://localhost:8080 and login with `admin` / `admin`

## What You Get

### Infrastructure

- ✅ **Private VNet** (10.0.0.0/16) with multiple subnets
- ✅ **Private ACR** (Premium) with private endpoint - no public access
- ✅ **Private Storage** (Blob & File) with private endpoints - no public access
- ✅ **Private PostgreSQL** in delegated subnet - no public access
- ✅ **Redis Cache** for Celery broker
- ✅ **Container Apps** (Scheduler, Webserver, Worker, Triggerer)
- ✅ **ETL Job** for data processing
- ✅ **Managed Identities** for all components
- ✅ **Log Analytics** for monitoring
- ⚙️ **Azure Firewall** (optional) for egress control
- ⚙️ **Windows VM** (optional) for building images

### Security

- ✅ **Zero public access** to any service
- ✅ **VNet isolation** with private endpoints
- ✅ **Managed identity** authentication
- ✅ **Private DNS** resolution
- ⚙️ **Egress control** (optional, with firewall)
- ✅ **Automated security tests**

### Cost

**Without Firewall (Recommended):**
- **PoC**: ~$100/month
- **Production**: ~$200/month

**With Firewall (For Compliance):**
- **PoC**: ~$246/month (+$146)
- **Production**: ~$1,141/month (+$941)

See [FIREWALL_DECISION_GUIDE.md](FIREWALL_DECISION_GUIDE.md) to decide if you need the firewall.

## Quick Commands

### Validate Everything

```bash
./scripts/validate-deployment.sh <resource-group> <env-name>
```

### Access Webserver

```bash
./scripts/access-webserver.sh <resource-group> <env-name>
```

### Upload DAGs

```bash
./scripts/upload-dags.sh <resource-group> <env-name> ./dags
```

### Test Security

```bash
./scripts/test-etl-job.sh <resource-group> <env-name>
```

### Check Logs

```bash
# Scheduler
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group <resource-group> \
  --follow

# Webserver
az containerapp logs show \
  --name airflow-poc-webserver \
  --resource-group <resource-group> \
  --follow
```

### Check Status

```bash
az containerapp list \
  --resource-group <resource-group> \
  --query "[].{Name:name, Status:properties.runningStatus}" \
  --output table
```

## Common Tasks

### Upload a New DAG

```bash
# 1. Create DAG file in ./dags/
# 2. Upload
./scripts/upload-dags.sh <resource-group> <env-name> ./dags

# 3. Wait 1-2 minutes
# 4. Refresh Airflow UI
```

### Trigger a DAG

```bash
# Via UI
# 1. Access webserver
# 2. Click on DAG
# 3. Click "Trigger DAG"

# Via API
curl -u admin:admin -X POST http://localhost:8080/api/v1/dags/my_dag/dagRuns \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Scale Workers

Workers auto-scale based on task queue (0-10 replicas).

Watch scaling:
```bash
watch -n 5 "az containerapp replica list --name airflow-poc-worker --resource-group <resource-group> --query 'length(@)' -o tsv"
```

### View Firewall Logs

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group <resource-group> \
  --workspace-name airflow-poc-logs \
  --query id -o tsv)

az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' | where TimeGenerated > ago(1h) | take 20" \
  --output table
```

## Troubleshooting

### Container Apps Not Starting

```bash
# Check logs
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group <resource-group> \
  --tail 50

# Common issues:
# - Image pull failed → Check ACR private endpoint
# - Database connection failed → Check PostgreSQL private DNS
# - File share mount failed → Check storage private endpoint
```

### Can't Access Webserver

```bash
# Check status
az containerapp show \
  --name airflow-poc-webserver \
  --resource-group <resource-group> \
  --query "properties.runningStatus"

# Check logs
az containerapp logs show \
  --name airflow-poc-webserver \
  --resource-group <resource-group> \
  --follow
```

### Network Issues

```bash
# Test from container
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group <resource-group> \
  --command bash

# Inside container:
# Test DNS
nslookup airflowpocacr.azurecr.io

# Test allowed endpoint
curl https://pypi.org

# Test blocked endpoint (should fail)
curl https://www.google.com
```

## Next Steps

### 1. Change Default Password

In Airflow UI: Security → List Users → admin → Edit

### 2. Configure Connections

Admin → Connections → Add your data sources

### 3. Deploy Production DAGs

```bash
./scripts/upload-dags.sh <resource-group> <env-name> ./production-dags
```

### 4. Set Up Monitoring

- Configure alerts in Log Analytics
- Set up Azure Monitor dashboards
- Enable Application Insights (optional)

### 5. Review Security

```bash
# Run security tests
./scripts/test-etl-job.sh <resource-group> <env-name>

# Review firewall logs
# Check for denied traffic that should be allowed
```

## Documentation

- **[ACCESS_AIRFLOW.md](ACCESS_AIRFLOW.md)** - Detailed access guide
- **[TESTING_GUIDE.md](TESTING_GUIDE.md)** - Complete testing procedures
- **[PRIVATE_NETWORK_SETUP.md](PRIVATE_NETWORK_SETUP.md)** - Network architecture
- **[SECURE_DEPLOYMENT_CHECKLIST.md](SECURE_DEPLOYMENT_CHECKLIST.md)** - Deployment checklist
- **[SECURITY_ENHANCEMENTS.md](SECURITY_ENHANCEMENTS.md)** - Security features
- **[ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)** - Visual diagrams

## Support

### Check Deployment Health

```bash
./scripts/validate-deployment.sh <resource-group> <env-name>
```

### Get Help

1. Check logs for errors
2. Review troubleshooting sections in docs
3. Verify RBAC roles assigned
4. Check firewall logs for blocked traffic

### Clean Up

```bash
cd terraform
terraform destroy -var-file=environments/poc/terraform.tfvars
```

## Architecture Summary

```
Internet
   ↓
[Azure Firewall] ← Controls all egress
   ↓
[Private VNet]
   ├─ [ACR] ← Private Endpoint
   ├─ [Container Apps] ← VNet Integration
   │   ├─ Scheduler
   │   ├─ Webserver (internal)
   │   ├─ Worker (auto-scale)
   │   └─ Triggerer
   ├─ [Storage] ← Private Endpoints
   │   ├─ File Share (DAGs)
   │   └─ Blob (Logs)
   └─ [PostgreSQL] ← Delegated Subnet
```

## Key Features

- 🔒 **Zero Trust**: No public access to any service
- 🛡️ **Egress Control**: All traffic through Azure Firewall
- 🔐 **Managed Identity**: No stored credentials
- 📊 **Auto-Scaling**: Workers scale 0-10 based on load
- 📝 **Comprehensive Logging**: All traffic logged
- ✅ **Automated Testing**: Security validation built-in
- 💰 **Cost Optimized**: PoC tier for development

## Success Checklist

- [ ] All validation checks pass
- [ ] Webserver accessible at http://localhost:8080
- [ ] Can login with admin/admin
- [ ] DAGs visible in UI
- [ ] Can trigger and execute DAGs
- [ ] Workers scale on demand
- [ ] Security tests pass
- [ ] No public access to services
- [ ] Firewall logs showing traffic

## Production Readiness

Before going to production:

1. ✅ Change deployment_mode to "production" in tfvars
2. ✅ Use Standard Firewall tier
3. ✅ Enable PostgreSQL high availability
4. ✅ Use Premium Redis
5. ✅ Configure Azure AD authentication
6. ✅ Set up monitoring and alerts
7. ✅ Document runbooks
8. ✅ Train operations team
9. ✅ Perform security audit
10. ✅ Test backup and recovery

## Quick Reference

| Task | Command |
|------|---------|
| Validate | `./scripts/validate-deployment.sh <rg> <env>` |
| Access UI | `./scripts/access-webserver.sh <rg> <env>` |
| Upload DAGs | `./scripts/upload-dags.sh <rg> <env> ./dags` |
| Test Security | `./scripts/test-etl-job.sh <rg> <env>` |
| View Logs | `az containerapp logs show --name <app> --resource-group <rg> --follow` |
| Check Status | `az containerapp list --resource-group <rg> --output table` |

## Time to Value

- **Initial Setup**: 30 minutes
- **First DAG Running**: 45 minutes
- **Production Ready**: 2-4 hours (with testing and validation)

Start building your secure data pipelines now! 🚀

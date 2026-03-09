# Windows VM Jump Box Guide

Cheapest Windows VM for accessing your private network and building Docker images for ACR.

## Overview

The Windows VM provides:
- ✅ Desktop access to private network
- ✅ Docker Desktop for building images
- ✅ Azure CLI for managing resources
- ✅ Git for cloning repositories
- ✅ Managed identity for ACR authentication
- ✅ RDP access from your IP

**Cost:** ~$30-40/month (Standard_B2s)

## Deployment

### Step 1: Enable VM in Configuration

Edit `terraform/environments/poc/terraform.tfvars`:

```hcl
# Enable Windows VM
enable_windows_vm = true

# VM configuration
vm_size            = "Standard_B2s"  # Cheapest: ~$30/month
vm_admin_username  = "azureuser"
vm_admin_password  = "YourComplexPassword123!"  # Change this!

# Restrict RDP to your IP (recommended)
allowed_rdp_source_ip = "203.0.113.42/32"  # Your public IP
# Or allow from anywhere (not recommended):
# allowed_rdp_source_ip = "*"
```

**Get your public IP:**
```bash
curl ifconfig.me
```

### Step 2: Deploy

```bash
cd terraform

# Set VM password as environment variable
export TF_VAR_vm_admin_password="YourComplexPassword123!"

# Apply
terraform apply -var-file=environments/poc/terraform.tfvars
```

### Step 3: Get RDP Connection Info

```bash
# Get VM public IP
terraform output vm_public_ip

# Get RDP command
terraform output vm_rdp_command
```

## Connecting to VM

### From Windows

```bash
# Get connection command
mstsc /v:<vm-public-ip>
```

Or:
1. Press `Win + R`
2. Type: `mstsc`
3. Enter VM public IP
4. Click "Connect"
5. Enter username and password

### From macOS

```bash
# Install Microsoft Remote Desktop from App Store
# Then connect to VM public IP
```

### From Linux

```bash
# Install rdesktop or remmina
sudo apt install rdesktop

# Connect
rdesktop <vm-public-ip> -u azureuser
```

## First Login Setup

### 1. Wait for Setup to Complete

After first login, wait 5-10 minutes for:
- Docker Desktop installation
- Azure CLI installation
- Git installation

**Check installation status:**
- Open PowerShell as Administrator
- Run: `choco list --local-only`

### 2. Restart VM (Required)

Docker Desktop requires a restart:

```powershell
Restart-Computer
```

### 3. Start Docker Desktop

After restart:
1. Open Docker Desktop from Start menu
2. Accept license agreement
3. Wait for Docker to start (whale icon in system tray)

## Building and Pushing Images to Private ACR

### Step 1: Login to Azure

```powershell
# Open PowerShell
az login

# Verify you're logged in
az account show
```

### Step 2: Login to ACR (Using Managed Identity)

```powershell
# Get ACR name
$ACR_NAME = "<your-acr-name>"  # e.g., airflowpocacr

# Login using managed identity
az acr login --name $ACR_NAME
```

**Note:** The VM has a managed identity with AcrPush role, so no credentials needed!

### Step 3: Clone Your Repository

```powershell
# Clone your repo
cd C:\Users\azureuser\Desktop
git clone <your-repo-url>
cd <your-repo>
```

### Step 4: Build Airflow Image

```powershell
# Navigate to Airflow Dockerfile
cd docker\airflow

# Build image
docker build -t ${ACR_NAME}.azurecr.io/airflow:latest .

# Push to ACR
docker push ${ACR_NAME}.azurecr.io/airflow:latest
```

### Step 5: Build ETL Runner Image

```powershell
# Navigate to ETL runner Dockerfile
cd ..\etl-runner

# Build image
docker build -t ${ACR_NAME}.azurecr.io/etl-runner:latest .

# Push to ACR
docker push ${ACR_NAME}.azurecr.io/etl-runner:latest
```

### Step 6: Update Container Apps

```powershell
# Update scheduler with new image
az containerapp update `
  --name airflow-poc-scheduler `
  --resource-group <resource-group> `
  --image ${ACR_NAME}.azurecr.io/airflow:latest

# Update webserver
az containerapp update `
  --name airflow-poc-webserver `
  --resource-group <resource-group> `
  --image ${ACR_NAME}.azurecr.io/airflow:latest

# Update worker
az containerapp update `
  --name airflow-poc-worker `
  --resource-group <resource-group> `
  --image ${ACR_NAME}.azurecr.io/airflow:latest

# Update triggerer
az containerapp update `
  --name airflow-poc-triggerer `
  --resource-group <resource-group> `
  --image ${ACR_NAME}.azurecr.io/airflow:latest

# Update ETL job
az containerapp job update `
  --name airflow-poc-etl-runner `
  --resource-group <resource-group> `
  --image ${ACR_NAME}.azurecr.io/etl-runner:latest
```

## Accessing Private Services from VM

### Access Airflow Webserver

Since the VM is in the same VNet, you can access the internal webserver directly:

```powershell
# Get webserver internal FQDN
az containerapp show `
  --name airflow-poc-webserver `
  --resource-group <resource-group> `
  --query "properties.configuration.ingress.fqdn" -o tsv

# Open in browser
# http://<internal-fqdn>
```

### Access PostgreSQL

```powershell
# Install PostgreSQL client
choco install postgresql -y

# Connect
psql "postgresql://airflow:<password>@airflow-poc-pg-pg-server.postgres.database.azure.com/airflow?sslmode=require"
```

### Access Storage

```powershell
# List files in DAGs share
az storage file list `
  --account-name airflowpocstor `
  --share-name airflow-dags `
  --auth-mode login `
  --output table

# Upload DAG
az storage file upload `
  --account-name airflowpocstor `
  --share-name airflow-dags `
  --source .\my_dag.py `
  --path my_dag.py `
  --auth-mode login
```

## VM Maintenance

### Start/Stop VM to Save Costs

```bash
# Stop VM (saves compute costs)
az vm deallocate \
  --name airflow-poc-vm \
  --resource-group <resource-group>

# Start VM when needed
az vm start \
  --name airflow-poc-vm \
  --resource-group <resource-group>
```

**Cost Savings:**
- Running 24/7: ~$30-40/month
- Running 8 hours/day: ~$10-15/month
- Stopped: ~$2/month (storage only)

### Auto-Shutdown Schedule

Configure in Azure Portal:
1. Go to VM → Auto-shutdown
2. Enable auto-shutdown
3. Set time (e.g., 6 PM daily)
4. Set timezone
5. Save

### Update VM Software

```powershell
# Update Chocolatey packages
choco upgrade all -y

# Update Azure CLI
az upgrade

# Update Docker Desktop
# Check for updates in Docker Desktop UI
```

## Cost Optimization

### VM Size Options

| Size | vCPU | RAM | Cost/Month | Use Case |
|------|------|-----|------------|----------|
| Standard_B1s | 1 | 1 GB | ~$10 | Minimal (too slow for Docker) |
| **Standard_B2s** | 2 | 4 GB | **~$30** | **Recommended** |
| Standard_B2ms | 2 | 8 GB | ~$60 | Heavy builds |
| Standard_D2s_v3 | 2 | 8 GB | ~$70 | Production |

**Recommendation:** Standard_B2s (cheapest that works well with Docker)

### Cost Reduction Tips

1. **Stop when not in use:**
   ```bash
   az vm deallocate --name airflow-poc-vm --resource-group <rg>
   ```

2. **Use auto-shutdown:**
   - Configure in Azure Portal
   - Automatically stops VM at specified time

3. **Use spot instances (advanced):**
   - Up to 90% discount
   - Can be evicted
   - Good for non-critical builds

## Security

### Network Security

- ✅ VM in private VNet
- ✅ Can access all private services
- ✅ RDP restricted to your IP
- ✅ Managed identity for ACR
- ✅ No stored credentials

### Best Practices

1. **Restrict RDP access:**
   ```hcl
   allowed_rdp_source_ip = "your-ip/32"  # Not "*"
   ```

2. **Use strong password:**
   - 12+ characters
   - Upper and lowercase
   - Numbers and special characters

3. **Enable Windows Defender:**
   - Already enabled by default
   - Keep Windows updated

4. **Use managed identity:**
   - No need to store ACR credentials
   - Automatic authentication

## Troubleshooting

### Can't Connect via RDP

**Check VM is running:**
```bash
az vm get-instance-view \
  --name airflow-poc-vm \
  --resource-group <resource-group> \
  --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
```

**Check NSG rules:**
```bash
az network nsg rule list \
  --nsg-name airflow-poc-vm-nsg \
  --resource-group <resource-group> \
  --output table
```

**Verify your IP is allowed:**
```bash
# Get your current public IP
curl ifconfig.me

# Update NSG if needed
az network nsg rule update \
  --nsg-name airflow-poc-vm-nsg \
  --resource-group <resource-group> \
  --name AllowRDP \
  --source-address-prefixes "your-new-ip/32"
```

### Docker Not Working

**Restart Docker Desktop:**
1. Right-click Docker icon in system tray
2. Select "Restart"

**Check Docker status:**
```powershell
docker version
docker ps
```

**If Docker not installed:**
```powershell
choco install docker-desktop -y
Restart-Computer
```

### Can't Login to ACR

**Check managed identity:**
```bash
az vm identity show \
  --name airflow-poc-vm \
  --resource-group <resource-group>
```

**Login manually if needed:**
```powershell
# Get ACR credentials (fallback)
az acr credential show --name <acr-name>

# Login with username/password
docker login <acr-name>.azurecr.io -u <username> -p <password>
```

### Can't Access Private Services

**Check VM is in VNet:**
```bash
az vm show \
  --name airflow-poc-vm \
  --resource-group <resource-group> \
  --query "networkProfile.networkInterfaces[0].id" -o tsv
```

**Test DNS resolution:**
```powershell
# Should resolve to private IP (10.0.x.x)
nslookup airflowpocacr.azurecr.io
nslookup airflowpocstor.blob.core.windows.net
nslookup airflow-poc-pg-pg-server.postgres.database.azure.com
```

**Test connectivity:**
```powershell
# Test ACR
Test-NetConnection -ComputerName airflowpocacr.azurecr.io -Port 443

# Test Storage
Test-NetConnection -ComputerName airflowpocstor.blob.core.windows.net -Port 443

# Test PostgreSQL
Test-NetConnection -ComputerName airflow-poc-pg-pg-server.postgres.database.azure.com -Port 5432
```

## Alternative: Azure Bastion (More Secure)

If you want more security, consider Azure Bastion instead:

**Pros:**
- No public IP on VM
- Access via Azure Portal
- No RDP port exposed
- Better security

**Cons:**
- More expensive (~$140/month)
- Requires Bastion subnet
- Slightly more complex

**To use Bastion instead:**
1. Remove public IP from VM
2. Deploy Azure Bastion
3. Connect via Azure Portal

## Quick Reference

### Deploy VM

```hcl
# terraform.tfvars
enable_windows_vm     = true
vm_admin_password     = "YourComplexPassword123!"
allowed_rdp_source_ip = "your-ip/32"
```

```bash
terraform apply -var-file=environments/poc/terraform.tfvars
```

### Connect to VM

```bash
# Get IP
terraform output vm_public_ip

# Connect (Windows)
mstsc /v:<ip>

# Connect (macOS)
# Use Microsoft Remote Desktop app

# Connect (Linux)
rdesktop <ip> -u azureuser
```

### Build and Push Images

```powershell
# On VM:
az login
az acr login --name <acr-name>
cd C:\Users\azureuser\Desktop\<your-repo>
docker build -t <acr>.azurecr.io/airflow:latest .
docker push <acr>.azurecr.io/airflow:latest
```

### Stop VM to Save Money

```bash
az vm deallocate --name airflow-poc-vm --resource-group <rg>
```

### Start VM When Needed

```bash
az vm start --name airflow-poc-vm --resource-group <rg>
```

## Cost Summary

| Component | Cost/Month | When Charged |
|-----------|------------|--------------|
| VM (B2s) | ~$30 | When running |
| Public IP | ~$3 | Always |
| Disk (127 GB) | ~$5 | Always |
| **Total (Running)** | **~$38** | 24/7 |
| **Total (Stopped)** | **~$8** | Deallocated |

**Tip:** Stop VM when not building images to save ~$30/month!

## When to Use

### ✅ Use Windows VM If:

1. **Need desktop access** to private network
2. **Build Docker images** for private ACR
3. **Test private services** interactively
4. **Develop and debug** in private environment
5. **Prefer GUI tools** over CLI

### ❌ Don't Use Windows VM If:

1. **Only need CLI access** - Use Azure Cloud Shell or local CLI
2. **CI/CD pipeline builds images** - Use Azure DevOps agents
3. **Cost is critical** - Use Azure Container Apps tunnel instead
4. **Don't need to build images** - Access via tunnel is free

## Alternatives

### Option 1: Azure Cloud Shell (Free)

```bash
# Access from browser
# Already has Azure CLI
# Can access private services if VNet peered
```

**Pros:** Free, no maintenance
**Cons:** No Docker, no desktop, limited

### Option 2: Azure DevOps Self-Hosted Agent

```bash
# Deploy agent in VNet
# Build images in pipeline
# No desktop access
```

**Pros:** Automated, CI/CD integrated
**Cons:** More complex setup

### Option 3: Container Apps Tunnel (Free)

```bash
# Access webserver via tunnel
# No image building capability
```

**Pros:** Free, simple
**Cons:** No Docker, CLI only

### Option 4: Azure Bastion + VM

```bash
# More secure than public IP
# Access via Azure Portal
```

**Pros:** More secure, no public IP
**Cons:** Expensive (~$140/month for Bastion)

## Recommendation

**For your use case (building images for private ACR):**

1. **Development:** Enable Windows VM
   ```hcl
   enable_windows_vm = true
   ```

2. **Build images** on VM when needed

3. **Stop VM** when not in use
   ```bash
   az vm deallocate --name airflow-poc-vm --resource-group <rg>
   ```

4. **Later:** Move to CI/CD pipeline for automated builds

**Cost:** ~$8-38/month depending on usage

## Network Peering (Manual)

Since you'll peer networks manually, here's what you need:

### Get VNet Info

```bash
# Get VNet resource ID
az network vnet show \
  --name airflow-poc-vnet \
  --resource-group <resource-group> \
  --query id -o tsv
```

### Create Peering (From Other VNet)

```bash
# From your other VNet to Airflow VNet
az network vnet peering create \
  --name peer-to-airflow \
  --resource-group <other-rg> \
  --vnet-name <other-vnet> \
  --remote-vnet <airflow-vnet-id> \
  --allow-vnet-access

# From Airflow VNet to your other VNet
az network vnet peering create \
  --name peer-from-airflow \
  --resource-group <airflow-rg> \
  --vnet-name airflow-poc-vnet \
  --remote-vnet <other-vnet-id> \
  --allow-vnet-access
```

### Verify Peering

```bash
az network vnet peering list \
  --resource-group <resource-group> \
  --vnet-name airflow-poc-vnet \
  --output table
```

## Summary

The Windows VM provides a cheap (~$30-40/month) desktop environment for:
- Building Docker images for private ACR
- Accessing private services with GUI tools
- Testing and debugging in private network
- Interactive development

**Stop the VM when not in use to save costs!**

## Quick Commands

```bash
# Deploy VM
terraform apply -var="enable_windows_vm=true"

# Get connection info
terraform output vm_public_ip

# Connect
mstsc /v:<ip>

# Stop VM (save money)
az vm deallocate --name airflow-poc-vm --resource-group <rg>

# Start VM (when needed)
az vm start --name airflow-poc-vm --resource-group <rg>

# Remove VM (if not needed)
terraform apply -var="enable_windows_vm=false"
```

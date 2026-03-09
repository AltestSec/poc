# Private Network Setup Guide

This guide explains the private network architecture and security configuration for the Airflow on Azure Container Apps deployment.

## Architecture Overview

The infrastructure is fully private with network egress control via Azure Firewall:

```
┌─────────────────────────────────────────────────────────────────┐
│ Virtual Network (10.0.0.0/16)                                   │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Azure Firewall (10.0.0.0/24)                             │  │
│  │ - Controls all egress traffic                            │  │
│  │ - DNS proxy enabled                                      │  │
│  │ - Application & Network rules                            │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Container Apps Subnet (10.0.2.0/23)                      │  │
│  │ - Airflow Scheduler, Webserver, Worker, Triggerer        │  │
│  │ - ETL Runner Jobs                                         │  │
│  │ - All traffic routed through Firewall                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Private Endpoints Subnet (10.0.4.0/24)                   │  │
│  │ - ACR Private Endpoint                                    │  │
│  │ - Storage (Blob & File) Private Endpoints                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ PostgreSQL Subnet (10.0.5.0/24)                          │  │
│  │ - PostgreSQL Flexible Server (delegated subnet)          │  │
│  │ - Private DNS integration                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Key Security Features

### 1. Private Container Registry (ACR)

- **Public access disabled**: `public_network_access_enabled = false`
- **Private endpoint**: Accessible only within VNet
- **Premium SKU required**: For private endpoint support
- **Managed identity authentication**: No admin credentials

```hcl
resource "azurerm_container_registry" "acr" {
  public_network_access_enabled = false
  admin_enabled                 = false
  network_rule_bypass_option    = "AzureServices"
}
```

### 2. Private Storage Account

- **Public access disabled**: All access via private endpoints
- **Blob & File private endpoints**: Separate endpoints for each service
- **Network rules**: Default deny with Azure Services bypass

```hcl
resource "azurerm_storage_account" "storage" {
  public_network_access_enabled = false
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}
```

### 3. Private PostgreSQL

- **VNet integration**: Delegated subnet for PostgreSQL
- **Private DNS zone**: `privatelink.postgres.database.azure.com`
- **No public access**: `public_network_access_enabled = false`
- **No firewall rules**: All access via private network

### 4. Azure Firewall Egress Control

Based on [Microsoft's guidance](https://techcommunity.microsoft.com/blog/azurepaasblog/securing-network-egress-in-azure-container-apps/3915548), all outbound traffic is controlled:

#### Allowed Destinations

**Azure Services:**
- `*.azurecr.io` - Container Registry
- `*.blob.core.windows.net` - Storage
- `mcr.microsoft.com` - Microsoft Container Registry
- `*.azure.com`, `*.microsoft.com`, `*.windows.net` - Azure APIs

**Package Managers:**
- `pypi.org`, `*.pypi.org`, `files.pythonhosted.org` - Python packages
- `*.ubuntu.com`, `*.debian.org` - OS packages

**DNS:**
- UDP port 53 to any destination

#### Blocked Destinations

All other internet destinations are blocked by default, including:
- Social media sites
- Public cloud services (non-Azure)
- Arbitrary internet endpoints

### 5. User Defined Routes (UDR)

All Container Apps traffic is routed through Azure Firewall:

```hcl
# Default route to Firewall
resource "azurerm_route" "firewall_route" {
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = azurerm_firewall.main.ip_configuration[0].private_ip_address
}

# Internet route for Firewall public IP
resource "azurerm_route" "internet_route" {
  address_prefix = "${azurerm_public_ip.firewall.ip_address}/32"
  next_hop_type  = "Internet"
}
```

### 6. Private DNS Zones

Private DNS zones ensure name resolution within the VNet:

- `privatelink.azurecr.io` - ACR
- `privatelink.blob.core.windows.net` - Blob Storage
- `privatelink.file.core.windows.net` - File Storage
- `privatelink.postgres.database.azure.com` - PostgreSQL

## Deployment Steps

### 1. Prerequisites

Ensure you have:
- Azure CLI 2.57+
- Terraform 1.5.0+
- Contributor role on resource group
- Registered resource providers (see main README)

### 2. Update Variables

Edit `terraform/environments/poc/terraform.tfvars`:

```hcl
# Network configuration
firewall_sku_tier = "Basic"  # or "Standard" for production

# ACR must be Premium for private endpoints
acr_sku = "Premium"
```

### 3. Deploy Infrastructure

```bash
cd terraform

# Initialize with backend
terraform init \
  -backend-config="resource_group_name=terraform-state-rg" \
  -backend-config="storage_account_name=tfstateairflow" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=airflow-poc.tfstate"

# Plan
terraform plan \
  -var-file=environments/poc/terraform.tfvars \
  -out=tfplan

# Apply
terraform apply tfplan
```

### 4. Assign RBAC Roles

```bash
cd ..
./assign-roles.sh <resource-group> <env-name>
```

### 5. Build and Push Images

Since ACR is private, you need to build from within the VNet or use Azure DevOps pipeline:

```bash
# Get ACR name
ACR_NAME=$(terraform output -raw acr_login_server | cut -d'.' -f1)

# Login via managed identity or service principal
az acr login --name $ACR_NAME

# Build and push
cd docker/airflow
docker build -t $ACR_NAME.azurecr.io/airflow:latest .
docker push $ACR_NAME.azurecr.io/airflow:latest

cd ../etl-runner
docker build -t $ACR_NAME.azurecr.io/etl-runner:latest .
docker push $ACR_NAME.azurecr.io/etl-runner:latest
```

## Testing Network Security

### Test ETL Job Network Restrictions

Run the automated test script:

```bash
./scripts/test-etl-job.sh <resource-group> <env-name>
```

This will:
1. Start the ETL job in test mode
2. Validate allowed endpoints are accessible
3. Verify blocked endpoints are denied
4. Display test results

### Manual Testing

Connect to a container and test manually:

```bash
# Connect to scheduler
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group <resource-group> \
  --command bash

# Test allowed endpoint (should succeed)
curl https://pypi.org

# Test blocked endpoint (should fail)
curl https://www.google.com
```

### View Firewall Logs

Check Azure Firewall logs in Log Analytics:

```kusto
AzureDiagnostics
| where Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s
| order by TimeGenerated desc
```

## Cost Considerations

### Azure Firewall Costs

**Basic Tier:**
- Fixed: ~$0.20/hour (~$146/month)
- Data processed: $0.015/GB

**Standard Tier:**
- Fixed: ~$1.25/hour (~$912/month)
- Data processed: $0.016/GB

**Recommendation:**
- Use Basic tier for PoC/Dev
- Use Standard tier for Production
- Consider Azure Firewall Manager for multi-region

### Private Endpoint Costs

- ~$0.01/hour per endpoint (~$7.30/month)
- Data processed: $0.01/GB

### Total Additional Costs

**PoC Environment:**
- Firewall: ~$146/month
- Private Endpoints (4): ~$29/month
- **Total: ~$175/month additional**

**Production Environment:**
- Firewall: ~$912/month (Standard)
- Private Endpoints (4): ~$29/month
- **Total: ~$941/month additional**

## Troubleshooting

### Container Apps Can't Pull Images

**Symptom:** Container apps fail to start with image pull errors

**Solution:**
1. Verify ACR private endpoint is created
2. Check private DNS zone is linked to VNet
3. Verify firewall rules allow `*.azurecr.io`
4. Check managed identity has AcrPull role

```bash
# Test DNS resolution
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group <resource-group> \
  --command "nslookup <acr-name>.azurecr.io"
```

### Storage Access Denied

**Symptom:** Can't access file share or blob storage

**Solution:**
1. Verify storage private endpoints exist
2. Check private DNS zones are configured
3. Verify firewall allows `*.blob.core.windows.net`
4. Check managed identity has Storage Blob Data Contributor role

### PostgreSQL Connection Timeout

**Symptom:** Can't connect to PostgreSQL

**Solution:**
1. Verify PostgreSQL is in delegated subnet
2. Check private DNS zone configuration
3. Ensure no firewall rules exist (should use private network only)
4. Verify connection string uses private FQDN

### Firewall Blocking Required Traffic

**Symptom:** Legitimate requests are blocked

**Solution:**
1. Check firewall logs to identify blocked FQDNs
2. Add required FQDNs to application rules
3. Update firewall policy and wait for propagation

```bash
# Add new FQDN to firewall rules
az network firewall application-rule create \
  --resource-group <resource-group> \
  --firewall-name <firewall-name> \
  --collection-name "allowed-external" \
  --name "new-endpoint" \
  --source-addresses '10.0.2.0/23' \
  --protocols "https=443" \
  --target-fqdns "example.com" \
  --action allow \
  --priority 202
```

## Security Best Practices

1. **Minimize Firewall Rules**: Only allow required destinations
2. **Use Managed Identities**: Avoid storing credentials
3. **Enable Diagnostic Logs**: Monitor all firewall traffic
4. **Regular Security Reviews**: Audit firewall rules quarterly
5. **Network Segmentation**: Keep different workloads in separate subnets
6. **Private DNS**: Always use private DNS zones for Azure services
7. **Disable Public Access**: Ensure all services have public access disabled

## Compliance

This architecture supports:
- **PCI DSS**: Network segmentation and egress control
- **HIPAA**: Private networking and encryption in transit
- **SOC 2**: Logging and monitoring of network traffic
- **ISO 27001**: Network security controls

## References

- [Securing Network Egress in Azure Container Apps](https://techcommunity.microsoft.com/blog/azurepaasblog/securing-network-egress-in-azure-container-apps/3915548)
- [Azure Container Apps Networking](https://learn.microsoft.com/azure/container-apps/networking)
- [Azure Firewall Documentation](https://learn.microsoft.com/azure/firewall/)
- [Private Endpoints](https://learn.microsoft.com/azure/private-link/private-endpoint-overview)

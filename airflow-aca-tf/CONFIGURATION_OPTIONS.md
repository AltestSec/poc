# Configuration Options - Quick Reference

Choose the right configuration for your needs.

## Configuration Matrix

| Feature | Cost/Month | When to Enable | How to Enable |
|---------|------------|----------------|---------------|
| **Base Infrastructure** | ~$71 | Always | Required |
| **Private Networking** | ~$29 | Always (included) | Automatic |
| **Azure Firewall** | +$146-912 | Compliance/Egress control | `enable_firewall = true` |
| **Windows VM** | +$30-40 | Build images locally | `enable_windows_vm = true` |

## Recommended Configurations

### 1. Development (Cheapest)

**Cost:** ~$130/month

```hcl
# terraform.tfvars
deployment_mode   = "poc"
enable_firewall   = false  # Save $146/month
enable_windows_vm = true   # Build images locally
acr_sku           = "Premium"  # Required for private endpoints
```

**What you get:**
- ✅ All services private
- ✅ Windows VM for building images
- ✅ Desktop access to private network
- ❌ No egress control

**Use for:**
- Development and testing
- Learning and experimentation
- Cost-sensitive projects

### 2. Production (Balanced)

**Cost:** ~$200/month

```hcl
# terraform.tfvars
deployment_mode   = "production"
enable_firewall   = false  # Save $912/month
enable_windows_vm = false  # Use CI/CD pipeline
acr_sku           = "Premium"
```

**What you get:**
- ✅ All services private
- ✅ Production-grade resources
- ✅ High availability
- ❌ No egress control
- ❌ No VM (use pipeline)

**Use for:**
- Production workloads
- Internal tools
- Trusted code

### 3. Production (High Security)

**Cost:** ~$1,141/month

```hcl
# terraform.tfvars
deployment_mode   = "production"
enable_firewall   = true   # Egress control
firewall_sku_tier = "Standard"
enable_windows_vm = false  # Use CI/CD pipeline
acr_sku           = "Premium"
```

**What you get:**
- ✅ All services private
- ✅ Production-grade resources
- ✅ Complete egress control
- ✅ Compliance ready
- ❌ No VM (use pipeline)

**Use for:**
- Regulated industries
- Sensitive data
- Compliance requirements

### 4. Development with Security Testing

**Cost:** ~$276/month

```hcl
# terraform.tfvars
deployment_mode   = "poc"
enable_firewall   = true   # Test security controls
firewall_sku_tier = "Basic"
enable_windows_vm = true   # Build images locally
acr_sku           = "Premium"
```

**What you get:**
- ✅ All services private
- ✅ Egress control for testing
- ✅ Windows VM for development
- ✅ Full security stack

**Use for:**
- Security testing
- Compliance validation
- Pre-production testing

## Feature Details

### Base Infrastructure (~$71/month)

**Always included:**
- Container Apps (Scheduler, Webserver, Worker, Triggerer)
- PostgreSQL Flexible Server
- Redis Cache
- Storage Account
- Log Analytics
- Key Vault
- Managed Identities

### Private Networking (~$29/month)

**Always included:**
- Virtual Network
- Private Endpoints (ACR, Storage Blob, Storage File)
- Private DNS Zones
- Subnet delegation for PostgreSQL

**What it does:**
- No public access to any service
- All communication via private network
- DNS resolution to private IPs

### Azure Firewall ($146-912/month)

**Optional - Enable with:**
```hcl
enable_firewall   = true
firewall_sku_tier = "Basic"  # or "Standard" or "Premium"
```

**What it does:**
- Controls outbound traffic from containers
- Blocks unauthorized external APIs
- Logs all egress traffic
- Compliance with security policies

**Tiers:**
- **Basic:** $146/month - Good for PoC
- **Standard:** $912/month - Production
- **Premium:** $1,825/month - Maximum security

### Windows VM ($30-40/month)

**Optional - Enable with:**
```hcl
enable_windows_vm     = true
vm_admin_password     = "YourComplexPassword123!"
allowed_rdp_source_ip = "your-ip/32"
```

**What it does:**
- Desktop access to private network
- Build Docker images for private ACR
- Test private services with GUI tools
- Interactive development

**VM Sizes:**
- **B2s:** $30/month - Recommended (2 vCPU, 4 GB RAM)
- **B2ms:** $60/month - Heavy builds (2 vCPU, 8 GB RAM)
- **B1s:** $10/month - Too slow for Docker

**Cost Optimization:**
- Stop when not in use: `az vm deallocate`
- Use auto-shutdown schedule
- Only pay for running time

## Configuration Examples

### Example 1: Minimal Development

```hcl
# terraform.tfvars
env_name              = "airflow-dev"
deployment_mode       = "poc"
enable_firewall       = false
enable_windows_vm     = true
vm_admin_password     = "DevPassword123!"
allowed_rdp_source_ip = "203.0.113.42/32"
```

**Cost:** ~$130/month
**Use:** Local development, building images

### Example 2: Production without Compliance

```hcl
# terraform.tfvars
env_name          = "airflow-prod"
deployment_mode   = "production"
enable_firewall   = false
enable_windows_vm = false
```

**Cost:** ~$200/month
**Use:** Production internal tools, trusted workloads

### Example 3: Production with Compliance

```hcl
# terraform.tfvars
env_name          = "airflow-prod"
deployment_mode   = "production"
enable_firewall   = true
firewall_sku_tier = "Standard"
enable_windows_vm = false
```

**Cost:** ~$1,141/month
**Use:** Regulated industries, sensitive data

### Example 4: Full Stack Development

```hcl
# terraform.tfvars
env_name          = "airflow-dev"
deployment_mode   = "poc"
enable_firewall   = true
firewall_sku_tier = "Basic"
enable_windows_vm = true
vm_admin_password = "DevPassword123!"
```

**Cost:** ~$276/month
**Use:** Testing full security stack, pre-production validation

## Decision Guide

### Do you need to build Docker images locally?

**YES** → `enable_windows_vm = true` (+$30/month)
**NO** → `enable_windows_vm = false` (use CI/CD pipeline)

### Do you need to control which websites containers can access?

**YES** → `enable_firewall = true` (+$146-912/month)
**NO** → `enable_firewall = false` (services already private)

### What deployment mode?

**Development/Testing** → `deployment_mode = "poc"` (smaller resources)
**Production** → `deployment_mode = "production"` (HA, larger resources)

## Quick Start Configurations

### For Your Use Case (Building Images)

```hcl
# terraform.tfvars
env_name              = "airflow-poc"
resource_group_name   = "your-rg"
deployment_mode       = "poc"
enable_firewall       = false  # Save $146/month
enable_windows_vm     = true   # Build images on VM
vm_admin_password     = "YourPassword123!"
allowed_rdp_source_ip = "your-ip/32"
acr_sku               = "Premium"
```

**Total Cost:** ~$130/month

**Workflow:**
1. Deploy infrastructure
2. RDP to Windows VM
3. Build and push images to private ACR
4. Images automatically pulled by Container Apps
5. Stop VM when not building to save money

## Cost Breakdown

### PoC Environment

| Component | Without FW, Without VM | With VM | With FW | With Both |
|-----------|------------------------|---------|---------|-----------|
| Base Infrastructure | $71 | $71 | $71 | $71 |
| Private Endpoints | $29 | $29 | $29 | $29 |
| Windows VM | - | $38 | - | $38 |
| Azure Firewall | - | - | $146 | $146 |
| **TOTAL** | **$100** | **$138** | **$246** | **$284** |

### Production Environment

| Component | Without FW, Without VM | With VM | With FW | With Both |
|-----------|------------------------|---------|---------|-----------|
| Base Infrastructure | $171 | $171 | $171 | $171 |
| Private Endpoints | $29 | $29 | $29 | $29 |
| Windows VM | - | $38 | - | $38 |
| Azure Firewall | - | - | $912 | $912 |
| **TOTAL** | **$200** | **$238** | **$1,112** | **$1,150** |

## Variables Reference

### Required Variables

```hcl
env_name                     = "airflow-poc"
resource_group_name          = "your-rg"
location                     = "westeurope"
deployment_mode              = "poc"
owner                        = "your-email@company.com"
duedate                      = "31dec2024"
airflow_fernet_key           = "..."  # Via TF_VAR env variable
airflow_webserver_secret_key = "..."  # Via TF_VAR env variable
postgres_admin_password      = "..."  # Via TF_VAR env variable
```

### Optional Variables

```hcl
# Firewall
enable_firewall   = false
firewall_sku_tier = "Basic"

# Windows VM
enable_windows_vm     = false
vm_size               = "Standard_B2s"
vm_admin_username     = "azureuser"
vm_admin_password     = "..."  # Via TF_VAR env variable
allowed_rdp_source_ip = "*"

# Resource sizing
postgres_sku_name = "B_Standard_B1ms"
redis_sku_name    = "Standard"
acr_sku           = "Premium"
```

## Summary

**My recommendation for you:**

```hcl
enable_firewall   = false  # Save $146/month, services already private
enable_windows_vm = true   # Build images locally, only $30/month
```

**Total cost:** ~$130/month

**Benefits:**
- All services private and secure
- Can build images on Windows desktop
- Can access private ACR
- Can peer with other VNets manually
- Significant cost savings vs firewall

See:
- [WINDOWS_VM_GUIDE.md](WINDOWS_VM_GUIDE.md) - VM setup and usage
- [FIREWALL_DECISION_GUIDE.md](FIREWALL_DECISION_GUIDE.md) - Firewall decision guide
- [QUICK_START.md](QUICK_START.md) - Getting started

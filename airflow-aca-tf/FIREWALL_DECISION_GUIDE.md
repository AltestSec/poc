# Azure Firewall Decision Guide

Should you enable Azure Firewall for your Airflow deployment? This guide helps you decide.

## TL;DR

**Without Firewall (Recommended for most cases):**
- ✅ All services are private (ACR, Storage, PostgreSQL)
- ✅ No public internet access to your services
- ✅ VNet isolation
- ✅ Private endpoints
- ✅ **Saves $146-912/month**
- ⚠️ Containers CAN access any internet endpoint

**With Firewall (For strict compliance):**
- ✅ Everything above, PLUS:
- ✅ Control which internet sites containers can access
- ✅ Block data exfiltration attempts
- ✅ Log all outbound traffic
- ✅ Compliance with strict security policies
- ❌ **Costs $146-912/month extra**

## What You Already Have (Without Firewall)

Your current private network setup provides:

### 1. Private Services
- **ACR**: No public access, only accessible via private endpoint
- **Storage**: No public access, only accessible via private endpoints
- **PostgreSQL**: No public access, only accessible within VNet
- **Container Apps**: Internal load balancer only

### 2. Network Isolation
- All services in VNet
- Private DNS resolution
- No public IPs (except for management)

### 3. Access Control
- Managed identity authentication
- RBAC for all resources
- No stored credentials

### What's Missing Without Firewall

- ❌ Can't restrict which external websites containers access
- ❌ Can't block containers from calling arbitrary APIs
- ❌ Can't log all outbound traffic
- ❌ Can't prevent data exfiltration to external services

## Decision Matrix

| Requirement | Without Firewall | With Firewall |
|-------------|------------------|---------------|
| Private ACR | ✅ Yes | ✅ Yes |
| Private Storage | ✅ Yes | ✅ Yes |
| Private PostgreSQL | ✅ Yes | ✅ Yes |
| VNet Isolation | ✅ Yes | ✅ Yes |
| Block public access to services | ✅ Yes | ✅ Yes |
| Control container egress | ❌ No | ✅ Yes |
| Block unauthorized APIs | ❌ No | ✅ Yes |
| Log all outbound traffic | ❌ No | ✅ Yes |
| Prevent data exfiltration | ⚠️ Partial | ✅ Yes |
| Monthly cost (PoC) | ~$71 | ~$217 |
| Monthly cost (Prod) | ~$200 | ~$1,141 |

## Use Cases

### ✅ You DON'T Need Firewall If:

1. **Development/Testing Environment**
   - Just need private services
   - Trust your code and developers
   - Cost is a concern

2. **Internal Tools**
   - Processing internal data only
   - No external API calls
   - Low security requirements

3. **Trusted Workloads**
   - Well-reviewed code
   - No sensitive data
   - Limited internet access needed

4. **Cost-Sensitive Projects**
   - Budget constraints
   - Private services sufficient
   - Can accept some risk

### ✅ You NEED Firewall If:

1. **Compliance Requirements**
   - PCI DSS Level 1
   - HIPAA with PHI
   - SOC 2 Type II
   - ISO 27001

2. **Sensitive Data**
   - Financial data
   - Healthcare records
   - Personal identifiable information (PII)
   - Trade secrets

3. **Zero-Trust Architecture**
   - Explicit allow-list required
   - Deny-by-default policy
   - Complete audit trail needed

4. **Untrusted Code**
   - Third-party DAGs
   - User-submitted code
   - External integrations
   - Unknown dependencies

5. **Data Exfiltration Prevention**
   - Need to block unauthorized uploads
   - Prevent data leaks
   - Control all external communication

## Configuration Options

### Option 1: No Firewall (Default - Recommended)

**In `terraform.tfvars`:**
```hcl
enable_firewall = false
```

**What you get:**
- Private ACR, Storage, PostgreSQL
- VNet isolation
- Private endpoints
- No egress control
- **Cost: ~$71/month (PoC) or ~$200/month (Prod)**

**Best for:**
- Development environments
- Internal tools
- Cost-sensitive projects
- Trusted workloads

### Option 2: Basic Firewall (Budget-Friendly)

**In `terraform.tfvars`:**
```hcl
enable_firewall   = true
firewall_sku_tier = "Basic"
```

**What you get:**
- Everything from Option 1, PLUS:
- Egress traffic control
- Application and network rules
- Basic logging
- **Cost: ~$217/month (PoC)**

**Best for:**
- PoC with compliance requirements
- Testing security controls
- Budget-conscious production

### Option 3: Standard Firewall (Production)

**In `terraform.tfvars`:**
```hcl
enable_firewall   = true
firewall_sku_tier = "Standard"
```

**What you get:**
- Everything from Option 2, PLUS:
- Threat intelligence
- Better performance
- Advanced logging
- **Cost: ~$1,141/month (Prod)**

**Best for:**
- Production with compliance
- Sensitive data workloads
- Enterprise deployments

### Option 4: Premium Firewall (Maximum Security)

**In `terraform.tfvars`:**
```hcl
enable_firewall   = true
firewall_sku_tier = "Premium"
```

**What you get:**
- Everything from Option 3, PLUS:
- TLS inspection
- IDPS (Intrusion Detection/Prevention)
- URL filtering
- **Cost: ~$2,000+/month**

**Best for:**
- Highly regulated industries
- Maximum security requirements
- Large enterprise deployments

## Recommendation by Environment

### Development/Testing
```hcl
enable_firewall = false
```
**Rationale:** Private services sufficient, save costs

### PoC/Demo
```hcl
enable_firewall = false
# OR if compliance needed:
enable_firewall   = true
firewall_sku_tier = "Basic"
```
**Rationale:** Demonstrate security without high costs

### Production (Low Security)
```hcl
enable_firewall = false
```
**Rationale:** Private services + RBAC sufficient for internal tools

### Production (High Security)
```hcl
enable_firewall   = true
firewall_sku_tier = "Standard"
```
**Rationale:** Compliance requirements, sensitive data

### Production (Maximum Security)
```hcl
enable_firewall   = true
firewall_sku_tier = "Premium"
```
**Rationale:** Regulated industries, critical data

## Migration Path

### Start Without Firewall

```hcl
# terraform.tfvars
enable_firewall = false
```

Deploy and validate:
```bash
terraform apply
./scripts/validate-deployment.sh <rg> <env>
```

### Add Firewall Later (If Needed)

```hcl
# terraform.tfvars
enable_firewall   = true
firewall_sku_tier = "Basic"
```

Apply changes:
```bash
terraform apply
```

**Note:** Adding firewall later is seamless - no downtime required.

## Cost Comparison

### Monthly Costs

| Component | No Firewall | Basic FW | Standard FW | Premium FW |
|-----------|-------------|----------|-------------|------------|
| Container Apps | $26 | $26 | $26 | $26 |
| PostgreSQL | $15 | $15 | $15 | $15 |
| Redis | $25 | $25 | $25 | $25 |
| Storage | $2 | $2 | $2 | $2 |
| Log Analytics | $3 | $3 | $3 | $3 |
| Private Endpoints | $29 | $29 | $29 | $29 |
| **Firewall** | **$0** | **$146** | **$912** | **$1,825** |
| **TOTAL (PoC)** | **$100** | **$246** | **$1,012** | **$1,925** |

### Annual Costs

| Configuration | Monthly | Annual | Savings vs Standard FW |
|---------------|---------|--------|------------------------|
| No Firewall | $100 | $1,200 | **$10,944** |
| Basic Firewall | $246 | $2,952 | **$9,192** |
| Standard Firewall | $1,012 | $12,144 | $0 |
| Premium Firewall | $1,925 | $23,100 | -$10,956 |

## Real-World Scenarios

### Scenario 1: Internal Analytics Platform

**Requirements:**
- Process internal company data
- No external API calls
- Development team trusted
- Cost-conscious

**Recommendation:** **No Firewall**
```hcl
enable_firewall = false
```

**Rationale:** Private services provide sufficient security. Containers only access internal Azure services via private endpoints.

### Scenario 2: Customer Data Processing

**Requirements:**
- Process customer PII
- Call external APIs (payment, email)
- Compliance required (SOC 2)
- Production workload

**Recommendation:** **Standard Firewall**
```hcl
enable_firewall   = true
firewall_sku_tier = "Standard"
```

**Rationale:** Need to control and log which external APIs are accessed. Compliance requires egress control.

### Scenario 3: Healthcare Data Pipeline

**Requirements:**
- Process PHI (Protected Health Information)
- HIPAA compliance required
- Maximum security
- Budget available

**Recommendation:** **Premium Firewall**
```hcl
enable_firewall   = true
firewall_sku_tier = "Premium"
```

**Rationale:** HIPAA requires strict controls. Premium provides TLS inspection and IDPS.

### Scenario 4: Startup MVP

**Requirements:**
- Proof of concept
- Limited budget
- Need to show investors
- Will scale later

**Recommendation:** **No Firewall**
```hcl
enable_firewall = false
```

**Rationale:** Private services sufficient for MVP. Add firewall when scaling to production.

## Security Without Firewall

Even without firewall, you still have strong security:

### 1. Network Isolation
```
✓ All services in private VNet
✓ No public IPs on services
✓ Private DNS resolution
✓ Subnet segmentation
```

### 2. Access Control
```
✓ Managed identity authentication
✓ RBAC on all resources
✓ No stored credentials
✓ Key Vault for secrets
```

### 3. Data Protection
```
✓ Encryption in transit (TLS 1.2+)
✓ Encryption at rest
✓ Private endpoints
✓ No public access
```

### 4. Monitoring
```
✓ Log Analytics
✓ Container logs
✓ Diagnostic settings
✓ Alerts
```

### What's Missing
```
✗ Can't restrict which websites containers access
✗ Can't block specific external APIs
✗ Can't log all outbound traffic
✗ Can't prevent data upload to unauthorized sites
```

## Making the Decision

### Ask Yourself:

1. **Do you have compliance requirements for egress control?**
   - Yes → Enable firewall
   - No → Skip firewall

2. **Do you process sensitive data (PII, PHI, financial)?**
   - Yes → Enable firewall
   - No → Skip firewall

3. **Do you need to restrict which external APIs containers can call?**
   - Yes → Enable firewall
   - No → Skip firewall

4. **Do you need to log all outbound traffic for audit?**
   - Yes → Enable firewall
   - No → Skip firewall

5. **Is your budget flexible?**
   - Yes → Can enable firewall
   - No → Skip firewall

### Decision Tree

```
Do you have compliance requirements (PCI DSS, HIPAA, SOC 2)?
├─ YES → Enable Firewall (Standard or Premium)
└─ NO
    └─ Do you process sensitive data?
        ├─ YES → Enable Firewall (Basic or Standard)
        └─ NO
            └─ Do you need to restrict external API access?
                ├─ YES → Enable Firewall (Basic)
                └─ NO → Skip Firewall (Save $146-912/month)
```

## Configuration Examples

### Example 1: Development (No Firewall)

```hcl
# terraform.tfvars
env_name            = "airflow-dev"
deployment_mode     = "poc"
enable_firewall     = false
acr_sku             = "Premium"  # Still need Premium for private endpoints
```

**Result:** Private services, no egress control, ~$100/month

### Example 2: Production with Compliance (Standard Firewall)

```hcl
# terraform.tfvars
env_name            = "airflow-prod"
deployment_mode     = "production"
enable_firewall     = true
firewall_sku_tier   = "Standard"
acr_sku             = "Premium"
```

**Result:** Full security with egress control, ~$1,141/month

### Example 3: Budget PoC with Security (Basic Firewall)

```hcl
# terraform.tfvars
env_name            = "airflow-poc"
deployment_mode     = "poc"
enable_firewall     = true
firewall_sku_tier   = "Basic"
acr_sku             = "Premium"
```

**Result:** Security demonstration, ~$246/month

## Switching Between Configurations

### Disable Firewall (Save Costs)

```bash
# Edit terraform.tfvars
enable_firewall = false

# Apply changes
terraform apply -var-file=environments/poc/terraform.tfvars
```

**Impact:**
- Firewall and routes removed
- Containers can access any internet endpoint
- Private services remain private
- **Saves $146-912/month**

### Enable Firewall (Add Security)

```bash
# Edit terraform.tfvars
enable_firewall   = true
firewall_sku_tier = "Basic"

# Apply changes
terraform apply -var-file=environments/poc/terraform.tfvars
```

**Impact:**
- Firewall deployed
- Routes configured
- Egress traffic controlled
- **Costs $146-912/month extra**

## My Recommendation

### For Your Use Case

Based on your architecture diagram showing Airflow orchestrating DBT jobs:

**Start WITHOUT Firewall:**

```hcl
enable_firewall = false
```

**Why:**
1. Your services are already private (ACR, Storage, PostgreSQL)
2. Airflow + DBT typically only access Azure services
3. You can add firewall later if needed
4. Saves significant costs during development

**Add Firewall Later If:**
- You need to call external APIs (payment, email, etc.)
- Compliance audit requires egress control
- You process sensitive customer data
- Security team mandates it

## Quick Comparison

### Architecture Without Firewall

```
Container Apps (in VNet)
  ↓
Private Endpoints
  ↓
Azure Services (ACR, Storage, PostgreSQL)
  ↓
Internet (unrestricted egress)
```

**Security Level:** High (private services, no public access)
**Cost:** Low (~$100/month)
**Complexity:** Low

### Architecture With Firewall

```
Container Apps (in VNet)
  ↓
User Defined Routes
  ↓
Azure Firewall (allow-list)
  ↓
Private Endpoints
  ↓
Azure Services (ACR, Storage, PostgreSQL)
  ↓
Internet (restricted egress)
```

**Security Level:** Maximum (egress control + private services)
**Cost:** High (~$246-1,141/month)
**Complexity:** Medium

## Testing Both Configurations

### Test Without Firewall

```bash
# Deploy without firewall
enable_firewall = false
terraform apply

# Test - containers can access any site
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group <rg> \
  --command "curl https://www.google.com"
# Should succeed
```

### Test With Firewall

```bash
# Deploy with firewall
enable_firewall = true
terraform apply

# Test - containers can only access allowed sites
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group <rg> \
  --command "curl https://www.google.com"
# Should fail (blocked by firewall)

az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group <rg> \
  --command "curl https://pypi.org"
# Should succeed (allowed by firewall)
```

## Summary

### Without Firewall (Recommended to Start)

**Pros:**
- ✅ All services private
- ✅ No public access
- ✅ VNet isolation
- ✅ Low cost
- ✅ Simple architecture

**Cons:**
- ❌ No egress control
- ❌ Can't restrict external APIs
- ❌ No outbound traffic logging

**Cost:** ~$100/month (PoC), ~$200/month (Prod)

### With Firewall (For Compliance)

**Pros:**
- ✅ Everything above, PLUS:
- ✅ Complete egress control
- ✅ Block unauthorized traffic
- ✅ Full audit trail
- ✅ Compliance ready

**Cons:**
- ❌ Higher cost
- ❌ More complex
- ❌ Requires firewall rule management

**Cost:** ~$246/month (PoC), ~$1,141/month (Prod)

## My Specific Recommendation for You

**Start with `enable_firewall = false`**

You already have:
- ✅ Private ACR (no public access)
- ✅ Private Storage (no public access)
- ✅ Private PostgreSQL (no public access)
- ✅ VNet isolation
- ✅ Managed identities

This is **secure enough for most use cases** and saves you $146-912/month.

**Add firewall only if:**
- Compliance audit requires it
- You need to call external APIs and want to restrict them
- Security team mandates egress control
- You're processing highly sensitive data

You can always add it later with a simple `terraform apply` - no data loss, minimal downtime.

## Quick Start Commands

### Deploy Without Firewall (Recommended)

```bash
# terraform.tfvars
enable_firewall = false

# Deploy
terraform apply -var-file=environments/poc/terraform.tfvars

# Validate
./scripts/validate-deployment.sh <rg> <env>
```

### Deploy With Firewall (If Needed)

```bash
# terraform.tfvars
enable_firewall   = true
firewall_sku_tier = "Basic"

# Deploy
terraform apply -var-file=environments/poc/terraform.tfvars

# Validate
./scripts/validate-deployment.sh <rg> <env>
./scripts/test-etl-job.sh <rg> <env>
```

## Questions?

- **"Is it secure without firewall?"** - Yes! All services are private with no public access.
- **"Can I add firewall later?"** - Yes! Just set `enable_firewall = true` and apply.
- **"Will it break anything?"** - No, seamless addition with minimal downtime.
- **"What if I'm not sure?"** - Start without firewall, add later if needed.

## Bottom Line

**For most Airflow deployments: Skip the firewall and save $146-912/month.**

Your services are already private and secure. Add the firewall only if you have specific compliance requirements or need to restrict which external websites your containers can access.

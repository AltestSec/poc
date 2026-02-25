# Resource Naming Convention

## Overview

Resources are named using a flexible pattern that supports both simple and prefixed naming:

- **Without prefix:** `{env_name}-{resource}`
- **With prefix:** `{prefix}-{env_name}-{resource}`

## Configuration

### Option 1: Without Prefix (Default)

```hcl
# terraform.tfvars
env_name = "airflow-poc"
# prefix not set or empty
```

**Result:**
| Resource Type | Name |
|---|---|
| Resource Group | `airflow-poc-rg` |
| ACR | `airflowpocacr` |
| Storage Account | `airflowpocstor` |
| Key Vault | `airflow-poc-kv` |
| PostgreSQL | `airflow-poc-pg` |
| Redis | `airflow-poc-redis` |
| Log Analytics | `airflow-poc-logs` |
| ACA Environment | `airflow-poc-env` |
| Scheduler | `airflow-poc-scheduler` |
| Webserver | `airflow-poc-webserver` |
| Worker | `airflow-poc-worker` |
| Triggerer | `airflow-poc-triggerer` |
| ETL Job | `airflow-poc-etl-runner` |

### Option 2: With Prefix (Recommended for Production)

```hcl
# terraform.tfvars
env_name = "airflow-poc"
prefix   = "mycompany"
```

**Result:**
| Resource Type | Name |
|---|---|
| Resource Group | `airflow-poc-rg` (not affected by prefix) |
| ACR | `mycompanyairflowpocacr` |
| Storage Account | `mycompanyairflowpocstor` |
| Key Vault | `mycompany-airflow-poc-kv` |
| PostgreSQL | `mycompany-airflow-poc-pg` |
| Redis | `mycompany-airflow-poc-redis` |
| Log Analytics | `mycompany-airflow-poc-logs` |
| ACA Environment | `airflow-poc-env` (uses env_name only) |
| Scheduler | `airflow-poc-scheduler` (uses env_name only) |
| Webserver | `airflow-poc-webserver` (uses env_name only) |
| Worker | `airflow-poc-worker` (uses env_name only) |
| Triggerer | `airflow-poc-triggerer` (uses env_name only) |
| ETL Job | `airflow-poc-etl-runner` (uses env_name only) |

## Naming Rules by Resource Type

### Globally Unique Resources (Must be unique across all Azure)

These resources use the prefix to ensure global uniqueness:

1. **Azure Container Registry (ACR)**
   - Pattern: `{prefix}{env_name}acr` (hyphens removed)
   - Max length: 50 characters
   - Allowed: alphanumeric only
   - Example: `mycompanyairflowpocacr`

2. **Storage Account**
   - Pattern: `{prefix}{env_name}stor` (hyphens removed)
   - Max length: 24 characters
   - Allowed: lowercase alphanumeric only
   - Example: `mycompanyairflowpocstor`

3. **Key Vault**
   - Pattern: `{prefix}-{env_name}-kv`
   - Max length: 24 characters
   - Allowed: alphanumeric and hyphens
   - Example: `mycompany-airflow-poc-kv`

### Regionally Unique Resources

These resources only need to be unique within the region/subscription:

4. **PostgreSQL Flexible Server**
   - Pattern: `{prefix}-{env_name}-pg`
   - Example: `mycompany-airflow-poc-pg`

5. **Redis Cache**
   - Pattern: `{prefix}-{env_name}-redis`
   - Example: `mycompany-airflow-poc-redis`

6. **Log Analytics Workspace**
   - Pattern: `{prefix}-{env_name}-logs`
   - Example: `mycompany-airflow-poc-logs`

### Resource Group Scoped Resources

These resources use `env_name` only (not affected by prefix):

7. **Container Apps Environment**
   - Pattern: `{env_name}-env`
   - Example: `airflow-poc-env`

8. **Container Apps**
   - Pattern: `{env_name}-{component}`
   - Examples:
     - `airflow-poc-scheduler`
     - `airflow-poc-webserver`
     - `airflow-poc-worker`
     - `airflow-poc-triggerer`

9. **Container App Job**
   - Pattern: `{env_name}-etl-runner`
   - Example: `airflow-poc-etl-runner`

10. **Managed Identities**
    - Pattern: `{env_name}-{component}-mi`
    - Examples:
      - `airflow-poc-scheduler-mi`
      - `airflow-poc-worker-mi`
      - `airflow-poc-webserver-mi`
      - `airflow-poc-triggerer-mi`

## Best Practices

### When to Use Prefix

✅ **Use prefix when:**
- Deploying to shared Azure subscriptions
- Multiple teams/projects in same subscription
- Need to ensure globally unique names
- Production environments
- Company/organization naming standards require it

❌ **Skip prefix when:**
- Personal/development subscriptions
- Single team/project per subscription
- Testing/PoC environments
- Shorter names preferred

### Prefix Recommendations

1. **Company/Team identifier:** `mycompany`, `teamname`, `projectcode`
2. **Keep it short:** 3-10 characters recommended
3. **Use lowercase:** Easier to read and type
4. **Avoid special characters:** Use only alphanumeric and hyphens
5. **Be consistent:** Use same prefix across all environments

### Examples by Use Case

**Scenario 1: Single company, multiple environments**
```hcl
# PoC
prefix   = "acme"
env_name = "airflow-poc"
# Result: acme-airflow-poc-pg, acmeairflowpocacr

# Production
prefix   = "acme"
env_name = "airflow-prod"
# Result: acme-airflow-prod-pg, acmeairflowprodacr
```

**Scenario 2: Multiple teams in same subscription**
```hcl
# Data Engineering team
prefix   = "dataeng"
env_name = "airflow-poc"
# Result: dataeng-airflow-poc-pg, dataengairflowpocacr

# Analytics team
prefix   = "analytics"
env_name = "airflow-poc"
# Result: analytics-airflow-poc-pg, analyticsairflowpocacr
```

**Scenario 3: Project-based naming**
```hcl
# Project Alpha
prefix   = "alpha"
env_name = "airflow-dev"
# Result: alpha-airflow-dev-pg, alphaairflowdevacr

# Project Beta
prefix   = "beta"
env_name = "airflow-dev"
# Result: beta-airflow-dev-pg, betaairflowdevacr
```

## Validation

### Check Name Availability

Before deploying, you can check if names are available:

```bash
# Check ACR name availability
az acr check-name --name mycompanyairflowpocacr

# Check Storage Account name availability
az storage account check-name --name mycompanyairflowpocstor

# Check Key Vault name availability
az keyvault list --query "[?name=='mycompany-airflow-poc-kv']"
```

### Name Length Limits

Be aware of Azure naming limits:

| Resource | Max Length | Current Pattern Length |
|---|---|---|
| ACR | 50 | `{prefix}{env_name}acr` |
| Storage | 24 | `{prefix}{env_name}stor` |
| Key Vault | 24 | `{prefix}-{env_name}-kv` |
| PostgreSQL | 63 | `{prefix}-{env_name}-pg` |
| Redis | 63 | `{prefix}-{env_name}-redis` |

**Example calculation:**
- prefix: `mycompany` (9 chars)
- env_name: `airflow-poc` (11 chars)
- Storage: `mycompanyairflowpocstor` = 9 + 11 + 4 = 24 chars ✓

## Troubleshooting

### Name Already Exists

If you get "name already exists" error:

1. **Change prefix:**
   ```hcl
   prefix = "mycompany2"  # or "mycompany-v2"
   ```

2. **Add random suffix (not recommended):**
   ```hcl
   # In main.tf locals
   resource_prefix = var.prefix != "" ? "${var.prefix}-${var.env_name}-${random_string.suffix.result}" : var.env_name
   ```

3. **Use different env_name:**
   ```hcl
   env_name = "airflow-poc-v2"
   ```

### Name Too Long

If name exceeds Azure limits:

1. **Shorten prefix:**
   ```hcl
   prefix = "acme"  # instead of "acmecompany"
   ```

2. **Shorten env_name:**
   ```hcl
   env_name = "af-poc"  # instead of "airflow-poc"
   ```

3. **Use abbreviations:**
   ```hcl
   prefix   = "ac"      # acme company
   env_name = "af-p"    # airflow poc
   ```

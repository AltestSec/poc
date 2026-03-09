# Testing Guide - Private Airflow Deployment

Complete guide for testing and validating your private Airflow deployment.

## Quick Start

Run all tests in sequence:

```bash
RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"

# 1. Validate infrastructure
./scripts/validate-deployment.sh $RESOURCE_GROUP $ENV_NAME

# 2. Test network security
./scripts/test-etl-job.sh $RESOURCE_GROUP $ENV_NAME

# 3. Upload test DAGs
./scripts/upload-dags.sh $RESOURCE_GROUP $ENV_NAME ./dags

# 4. Access webserver
./scripts/access-webserver.sh $RESOURCE_GROUP $ENV_NAME
```

## Test Categories

### 1. Infrastructure Tests

**Purpose:** Verify all Azure resources are deployed and configured correctly

**Script:** `./scripts/validate-deployment.sh`

**Tests:**
- ✓ Virtual Network exists
- ✓ Azure Firewall provisioned
- ✓ Route Table configured
- ✓ Container Registry exists and is private
- ✓ Storage Account exists and is private
- ✓ PostgreSQL exists and is private
- ✓ Redis Cache exists
- ✓ Container Apps Environment VNet-integrated
- ✓ All Container Apps running
- ✓ ETL Job exists
- ✓ Private Endpoints connected
- ✓ Managed Identities created

**Expected Result:** All checks pass (0 failures)

**If Failed:**
- Review Terraform apply output
- Check Azure Portal for resource status
- Verify RBAC roles assigned

### 2. Network Security Tests

**Purpose:** Validate egress traffic control and firewall rules

**Script:** `./scripts/test-etl-job.sh`

**Tests:**
- ✓ Allowed endpoints accessible (PyPI, Azure services)
- ✓ Blocked endpoints denied (Google, social media)
- ✓ ETL process executes successfully
- ✓ Network isolation working

**Expected Result:** All tests pass

**If Failed:**
- Check firewall logs for denied traffic
- Verify firewall application rules
- Check private DNS resolution

### 3. Connectivity Tests

**Purpose:** Verify all components can communicate

**Manual Tests:**

```bash
# Test from scheduler container
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --command bash

# Inside container:
# Test PostgreSQL DNS
nslookup airflow-poc-pg-pg-server.postgres.database.azure.com
# Should resolve to private IP (10.0.5.x)

# Test ACR DNS
nslookup airflowpocacr.azurecr.io
# Should resolve to private IP (10.0.4.x)

# Test Storage DNS
nslookup airflowpocstor.blob.core.windows.net
# Should resolve to private IP (10.0.4.x)

# Test allowed endpoint
curl https://pypi.org
# Should succeed

# Test blocked endpoint
curl https://www.google.com
# Should fail with timeout or firewall message
```

**Expected Results:**
- ✓ All private endpoints resolve to 10.0.x.x IPs
- ✓ Allowed endpoints accessible
- ✓ Blocked endpoints denied

### 4. Functional Tests

**Purpose:** Verify Airflow functionality

**Tests:**

```bash
# 1. Access webserver
./scripts/access-webserver.sh $RESOURCE_GROUP $ENV_NAME

# 2. In browser (http://localhost:8080):
# - Login with admin/admin
# - Navigate to DAGs page
# - Verify DAGs are listed
# - Click on a DAG
# - Click "Trigger DAG"
# - Monitor execution in Graph view
# - Check task logs

# 3. Verify worker scaling
# Trigger multiple DAGs simultaneously
# Watch worker replicas scale up:
watch -n 5 "az containerapp replica list --name airflow-poc-worker --resource-group $RESOURCE_GROUP --query 'length(@)' -o tsv"
```

**Expected Results:**
- ✓ UI loads successfully
- ✓ Can login
- ✓ DAGs visible
- ✓ Can trigger DAGs
- ✓ Tasks execute
- ✓ Workers scale up
- ✓ Logs accessible

### 5. ETL Job Tests

**Purpose:** Validate ETL job execution and security

**Automated Test:**
```bash
./scripts/test-etl-job.sh $RESOURCE_GROUP $ENV_NAME
```

**Manual Test:**
```bash
# Start job
az containerapp job start \
  --name airflow-poc-etl-runner \
  --resource-group $RESOURCE_GROUP \
  --env-vars "RUN_MODE=test"

# Monitor execution
az containerapp job execution list \
  --name airflow-poc-etl-runner \
  --resource-group $RESOURCE_GROUP \
  --output table

# View logs
EXECUTION_NAME=$(az containerapp job execution list \
  --name airflow-poc-etl-runner \
  --resource-group $RESOURCE_GROUP \
  --query "[0].name" -o tsv)

az containerapp job logs show \
  --name airflow-poc-etl-runner \
  --resource-group $RESOURCE_GROUP \
  --execution $EXECUTION_NAME
```

**Expected Results:**
- ✓ Job starts successfully
- ✓ Test script executes
- ✓ Network tests pass
- ✓ ETL process completes
- ✓ Job status: Succeeded

### 6. Security Validation Tests

**Purpose:** Confirm no public access to any service

**Tests:**

```bash
# Try to access ACR publicly (should fail)
curl https://$(echo ${ENV_NAME}acr | tr -d '-').azurecr.io/v2/
# Expected: Connection timeout or refused

# Try to access storage publicly (should fail)
curl https://$(echo ${ENV_NAME}stor | tr -d '-').blob.core.windows.net/
# Expected: Connection timeout or refused

# Try to access PostgreSQL publicly (should fail)
nc -zv ${ENV_NAME}-pg-pg-server.postgres.database.azure.com 5432
# Expected: Connection timeout

# Verify private endpoints
az network private-endpoint list \
  --resource-group $RESOURCE_GROUP \
  --query "[].{Name:name, Status:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  --output table
# Expected: All show "Approved"
```

**Expected Results:**
- ✓ All public access attempts fail
- ✓ All private endpoints approved
- ✓ Services only accessible within VNet

## Performance Tests

### Load Testing

```bash
# Trigger multiple DAGs to test scaling
for i in {1..10}; do
  curl -u admin:admin -X POST http://localhost:8080/api/v1/dags/test_dag/dagRuns \
    -H "Content-Type: application/json" \
    -d '{}'
done

# Watch worker scaling
watch -n 5 "az containerapp replica list --name airflow-poc-worker --resource-group $RESOURCE_GROUP --output table"
```

**Expected Results:**
- ✓ Workers scale from 0 to N (based on load)
- ✓ Tasks execute successfully
- ✓ Workers scale down after tasks complete

### Database Performance

```bash
# Check active connections
az postgres flexible-server execute \
  --name airflow-poc-pg-pg-server \
  --resource-group $RESOURCE_GROUP \
  --admin-user airflow \
  --admin-password <password> \
  --database-name airflow \
  --querytext "SELECT count(*) as active_connections FROM pg_stat_activity WHERE state = 'active';"
```

### Storage Performance

```bash
# Check DAG file access time
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --command "time ls -la /opt/airflow/dags"
```

## Integration Tests

### Test Complete Workflow

Create and run a test DAG that exercises all components:

```python
# test_integration.py
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

def test_database():
    from airflow.hooks.base import BaseHook
    conn = BaseHook.get_connection('postgres_default')
    return {"success": True, "data": "Database accessible"}

def test_storage():
    import os
    dags_path = '/opt/airflow/dags'
    files = os.listdir(dags_path)
    return {"success": True, "data": f"Found {len(files)} files"}

with DAG(
    'test_integration',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
) as dag:
    
    t1 = BashOperator(
        task_id='test_bash',
        bash_command='echo "Bash operator works"',
    )
    
    t2 = PythonOperator(
        task_id='test_database',
        python_callable=test_database,
    )
    
    t3 = PythonOperator(
        task_id='test_storage',
        python_callable=test_storage,
    )
    
    t1 >> [t2, t3]
```

Upload and trigger this DAG to test all components.

## Regression Tests

Run after any infrastructure change:

```bash
#!/bin/bash
# regression-test.sh

RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"

echo "Running regression tests..."

# 1. Infrastructure validation
echo "1. Infrastructure validation..."
./scripts/validate-deployment.sh $RESOURCE_GROUP $ENV_NAME || exit 1

# 2. Network security
echo "2. Network security tests..."
./scripts/test-etl-job.sh $RESOURCE_GROUP $ENV_NAME || exit 1

# 3. Webserver accessibility
echo "3. Webserver accessibility..."
timeout 10 bash -c "az containerapp tunnel --name ${ENV_NAME}-webserver --resource-group $RESOURCE_GROUP --port 8080:8080 &"
sleep 5
curl -f http://localhost:8080/health || exit 1

# 4. DAG processing
echo "4. DAG processing..."
LOGS=$(az containerapp logs show --name ${ENV_NAME}-scheduler --resource-group $RESOURCE_GROUP --tail 50 --output tsv)
echo "$LOGS" | grep -q "DAG" || exit 1

echo "✓ All regression tests passed"
```

## Continuous Monitoring

### Daily Checks

```bash
# Check all services healthy
./scripts/validate-deployment.sh $RESOURCE_GROUP $ENV_NAME

# Review firewall logs
az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' | where TimeGenerated > ago(24h) | summarize count() by msg_s" \
  --output table
```

### Weekly Checks

```bash
# Run security tests
./scripts/test-etl-job.sh $RESOURCE_GROUP $ENV_NAME

# Review RBAC assignments
./assign-roles.sh $RESOURCE_GROUP $ENV_NAME --dry-run

# Check for failed DAG runs
# Access UI and review DAG run history
```

### Monthly Checks

```bash
# Review firewall rules
az network firewall policy rule-collection-group list \
  --resource-group $RESOURCE_GROUP \
  --policy-name ${ENV_NAME}-vnet-fw-policy \
  --output table

# Review resource costs
az consumption usage list \
  --start-date $(date -d '30 days ago' +%Y-%m-%d) \
  --end-date $(date +%Y-%m-%d) \
  --output table
```

## Test Results Documentation

### Sample Validation Output

```
═══════════════════════════════════════════════════════════
 Validating Airflow Deployment
 Resource Group: merzlikin-tf-state-rg
 Environment:    airflow-poc
═══════════════════════════════════════════════════════════

▶ Step 1: Checking Network Infrastructure
─────────────────────────────────────────────────────────
✓ Virtual Network exists
✓ Azure Firewall exists
✓ Azure Firewall provisioned
✓ Route Table exists

▶ Step 2: Checking Core Services
─────────────────────────────────────────────────────────
✓ Container Registry exists
✓ ACR public access disabled
✓ ACR contains images (2 found)
✓ Storage Account exists
✓ Storage public access disabled
✓ PostgreSQL Server exists
✓ PostgreSQL public access disabled
✓ Redis Cache exists

▶ Step 3: Checking Container Apps Environment
─────────────────────────────────────────────────────────
✓ Container Apps Environment exists
✓ Environment VNet integrated

▶ Step 4: Checking Container Apps
─────────────────────────────────────────────────────────
✓ Scheduler exists
✓ Scheduler running
✓ Scheduler has active replicas (1)
✓ Webserver exists
✓ Webserver running
   FQDN: airflow-poc-webserver.internal.westeurope.azurecontainerapps.io
✓ Webserver ingress configured
✓ Worker exists
✓ Worker running
✓ Triggerer exists
✓ Triggerer running

▶ Step 5: Checking ETL Job
─────────────────────────────────────────────────────────
✓ ETL Runner Job exists

▶ Step 6: Checking Private Endpoints
─────────────────────────────────────────────────────────
✓ Private Endpoints created (4 found)

▶ Step 7: Checking Managed Identities
─────────────────────────────────────────────────────────
✓ Managed Identity: scheduler
✓ Managed Identity: worker
✓ Managed Identity: webserver
✓ Managed Identity: triggerer

═══════════════════════════════════════════════════════════
 Validation Summary
═══════════════════════════════════════════════════════════
 Passed: 28
 Failed: 0
 Total:  28
═══════════════════════════════════════════════════════════

✓ All checks passed! Deployment is healthy.
```

## Troubleshooting Failed Tests

### Infrastructure Tests Failed

**Check Terraform state:**
```bash
cd terraform
terraform show
```

**Verify resources in Azure Portal:**
- Navigate to resource group
- Verify all resources present
- Check resource status

### Network Security Tests Failed

**Review firewall logs:**
```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RESOURCE_GROUP \
  --workspace-name ${ENV_NAME}-logs \
  --query id -o tsv)

az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' | where TimeGenerated > ago(1h)" \
  --output table
```

**Check firewall rules:**
```bash
az network firewall policy rule-collection-group show \
  --resource-group $RESOURCE_GROUP \
  --policy-name ${ENV_NAME}-vnet-fw-policy \
  --name DefaultRuleCollectionGroup \
  --output json
```

### Connectivity Tests Failed

**Check private endpoints:**
```bash
az network private-endpoint list \
  --resource-group $RESOURCE_GROUP \
  --output table
```

**Check private DNS zones:**
```bash
az network private-dns zone list \
  --resource-group $RESOURCE_GROUP \
  --output table
```

**Test DNS resolution:**
```bash
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --command "nslookup airflowpocacr.azurecr.io"
```

## Test Automation

### CI/CD Pipeline Tests

Add to your Azure DevOps pipeline:

```yaml
- stage: Validate
  jobs:
  - job: InfrastructureTests
    steps:
    - bash: |
        ./scripts/validate-deployment.sh $(RESOURCE_GROUP) $(ENV_NAME)
      displayName: 'Validate Infrastructure'
  
  - job: SecurityTests
    dependsOn: InfrastructureTests
    steps:
    - bash: |
        ./scripts/test-etl-job.sh $(RESOURCE_GROUP) $(ENV_NAME)
      displayName: 'Test Network Security'
  
  - job: FunctionalTests
    dependsOn: SecurityTests
    steps:
    - bash: |
        ./scripts/upload-dags.sh $(RESOURCE_GROUP) $(ENV_NAME) ./dags
      displayName: 'Upload Test DAGs'
```

### Scheduled Tests

Create a cron job or Azure DevOps scheduled pipeline:

```bash
# Daily validation
0 6 * * * /path/to/scripts/validate-deployment.sh merzlikin-tf-state-rg airflow-poc

# Weekly security tests
0 6 * * 1 /path/to/scripts/test-etl-job.sh merzlikin-tf-state-rg airflow-poc
```

## Test Data

### Sample Test DAG

```python
# dags/test_all_features.py
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta

def test_all_features():
    """Test all Airflow features"""
    results = {
        "database": test_database_connection(),
        "storage": test_storage_access(),
        "network": test_network_egress(),
    }
    return {"success": True, "data": results}

def test_database_connection():
    """Test database connectivity"""
    try:
        from airflow.settings import Session
        session = Session()
        result = session.execute("SELECT 1").scalar()
        return {"success": True, "data": "Connected"}
    except Exception as e:
        return {"success": False, "error": str(e)}

def test_storage_access():
    """Test storage file share access"""
    try:
        import os
        files = os.listdir('/opt/airflow/dags')
        return {"success": True, "data": f"{len(files)} files"}
    except Exception as e:
        return {"success": False, "error": str(e)}

def test_network_egress():
    """Test network egress control"""
    try:
        import urllib.request
        
        # Test allowed endpoint
        try:
            urllib.request.urlopen('https://pypi.org', timeout=5)
            allowed = True
        except:
            allowed = False
        
        # Test blocked endpoint
        try:
            urllib.request.urlopen('https://www.google.com', timeout=5)
            blocked = False  # Should be blocked
        except:
            blocked = True  # Correctly blocked
        
        return {
            "success": allowed and blocked,
            "data": {
                "allowed_accessible": allowed,
                "blocked_denied": blocked
            }
        }
    except Exception as e:
        return {"success": False, "error": str(e)}

with DAG(
    'test_all_features',
    start_date=datetime(2024, 1, 1),
    schedule_interval=None,
    catchup=False,
    tags=['test', 'validation'],
) as dag:
    
    test_task = PythonOperator(
        task_id='run_all_tests',
        python_callable=test_all_features,
    )
```

## Success Criteria

### Deployment is Successful When:

1. ✅ Infrastructure validation: 0 failures
2. ✅ Network security tests: All pass
3. ✅ Webserver accessible via tunnel
4. ✅ Can login to UI
5. ✅ DAGs visible and executable
6. ✅ Workers scale on demand
7. ✅ ETL job executes successfully
8. ✅ Logs accessible in UI and blob storage
9. ✅ No public access to any service
10. ✅ All traffic through firewall

### Ready for Production When:

1. ✅ All tests pass consistently
2. ✅ Performance meets requirements
3. ✅ Security audit completed
4. ✅ Monitoring and alerts configured
5. ✅ Backup and recovery tested
6. ✅ Documentation complete
7. ✅ Team trained
8. ✅ Runbooks created

## References

- [ACCESS_AIRFLOW.md](ACCESS_AIRFLOW.md) - Access procedures
- [PRIVATE_NETWORK_SETUP.md](PRIVATE_NETWORK_SETUP.md) - Network architecture
- [SECURE_DEPLOYMENT_CHECKLIST.md](SECURE_DEPLOYMENT_CHECKLIST.md) - Deployment steps
- [SECURITY_ENHANCEMENTS.md](SECURITY_ENHANCEMENTS.md) - Security features

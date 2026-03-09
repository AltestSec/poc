# Accessing Airflow Web UI - Private Network Setup

## Quick Validation & Access

### Step 1: Validate Deployment

Run the comprehensive validation script:

```bash
./scripts/validate-deployment.sh <resource-group> <env-name>
```

Example:
```bash
./scripts/validate-deployment.sh merzlikin-tf-state-rg airflow-poc
```

This checks:
- ✓ Network infrastructure (VNet, Firewall, Routes)
- ✓ Core services (ACR, Storage, PostgreSQL, Redis)
- ✓ Container Apps Environment
- ✓ All Container Apps (Scheduler, Webserver, Worker, Triggerer)
- ✓ ETL Job
- ✓ Private Endpoints
- ✓ Managed Identities
- ✓ Connectivity and logs

### Step 2: Access Webserver

Since the webserver is **internal-only** (no public access), use Azure Container Apps tunnel:

```bash
./scripts/access-webserver.sh <resource-group> <env-name>
```

Example:
```bash
./scripts/access-webserver.sh merzlikin-tf-state-rg airflow-poc
```

Then open: **http://localhost:8080**

### Step 3: Login

**Default credentials:**
- Username: `admin`
- Password: `admin`

⚠️ **IMPORTANT:** Change the password immediately after first login!

## Manual Access (Alternative)

If you prefer manual steps:

```bash
RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"

# Create tunnel
az containerapp tunnel \
  --name ${ENV_NAME}-webserver \
  --resource-group $RESOURCE_GROUP \
  --port 8080:8080
```

Then open: http://localhost:8080

## Complete Validation Workflow

### 1. Infrastructure Health Check

```bash
RESOURCE_GROUP="merzlikin-tf-state-rg"
ENV_NAME="airflow-poc"

# Check all Container Apps status
az containerapp list \
  --resource-group $RESOURCE_GROUP \
  --query "[].{Name:name, Status:properties.runningStatus, Replicas:properties.template.scale.minReplicas}" \
  --output table
```

Expected output:
```
Name                    Status    Replicas
----------------------  --------  --------
airflow-poc-scheduler   Running   1
airflow-poc-webserver   Running   1
airflow-poc-worker      Running   0
airflow-poc-triggerer   Running   1
```

### 2. Check Private Network Configuration

```bash
# Verify ACR is private
az acr show \
  --name $(echo "${ENV_NAME}acr" | tr -d '-') \
  --resource-group $RESOURCE_GROUP \
  --query "{Name:name, PublicAccess:publicNetworkAccess}" \
  --output table

# Verify Storage is private
az storage account show \
  --name $(echo "${ENV_NAME}stor" | tr -d '-') \
  --resource-group $RESOURCE_GROUP \
  --query "{Name:name, PublicAccess:publicNetworkAccess}" \
  --output table

# Verify PostgreSQL is private
az postgres flexible-server show \
  --name ${ENV_NAME}-pg-pg-server \
  --resource-group $RESOURCE_GROUP \
  --query "{Name:name, PublicAccess:network.publicNetworkAccess}" \
  --output table
```

All should show: `PublicAccess: Disabled`

### 3. Check Component Logs

```bash
# Scheduler logs (should show DAG processing)
az containerapp logs show \
  --name ${ENV_NAME}-scheduler \
  --resource-group $RESOURCE_GROUP \
  --tail 20

# Webserver logs (should show startup)
az containerapp logs show \
  --name ${ENV_NAME}-webserver \
  --resource-group $RESOURCE_GROUP \
  --tail 20
```

Look for:
- ✓ "Connected to database"
- ✓ "Connected to Redis"
- ✓ "DAGs folder: /opt/airflow/dags"
- ✗ Connection errors or timeouts

### 4. Test Network Security

Run the ETL job security tests:

```bash
./scripts/test-etl-job.sh $RESOURCE_GROUP $ENV_NAME
```

This validates:
- ✓ Allowed endpoints accessible (PyPI, Azure services)
- ✓ Blocked endpoints denied (Google, etc.)
- ✓ Firewall rules working correctly

### 5. Upload and Test DAGs

```bash
# Upload DAGs
./scripts/upload-dags.sh $RESOURCE_GROUP $ENV_NAME ./dags

# Wait 1-2 minutes for Airflow to detect DAGs

# Access webserver
./scripts/access-webserver.sh $RESOURCE_GROUP $ENV_NAME
```

## What You'll See in Airflow UI

After logging in at http://localhost:8080:

### 1. DAGs Page (Main)
- List of all DAGs
- DAG status, last run, schedule
- Pause/unpause toggles
- Trigger DAG button

### 2. Navigation Menu
- **DAGs** - Main DAG list
- **Datasets** - Data dependencies
- **Security** - User management
- **Browse** - Task instances, jobs, logs
- **Admin** - Connections, variables, configuration

### 3. Initial State
- If no DAGs uploaded: "No DAGs found" (normal)
- After uploading: DAGs appear within 1-2 minutes

## Troubleshooting

### Webserver Not Accessible

**Check status:**
```bash
az containerapp show \
  --name airflow-poc-webserver \
  --resource-group $RESOURCE_GROUP \
  --query "{Status:properties.runningStatus, FQDN:properties.configuration.ingress.fqdn}" \
  --output table
```

**Check logs:**
```bash
az containerapp logs show \
  --name airflow-poc-webserver \
  --resource-group $RESOURCE_GROUP \
  --follow
```

**Common issues:**
- Webserver still starting (wait 2-3 minutes)
- Database connection failed (check PostgreSQL private DNS)
- Health probe failing (check logs for errors)

### Container Apps Not Starting

**Check logs:**
```bash
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --tail 50
```

**Common issues:**
- Can't pull image from ACR → Check private endpoint and managed identity
- Can't connect to PostgreSQL → Check private DNS and network
- Can't mount file share → Check storage private endpoint

### Image Pull Failures

**Test DNS resolution:**
```bash
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --command "nslookup $(echo ${ENV_NAME}acr | tr -d '-').azurecr.io"
```

Should resolve to private IP (10.0.4.x)

**Solution:**
- Verify private DNS zone linked to VNet
- Check managed identity has AcrPull role
- Verify firewall allows `*.azurecr.io`

### Database Connection Failures

**Test connection:**
```bash
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --command "nc -zv ${ENV_NAME}-pg-pg-server.postgres.database.azure.com 5432"
```

**Solution:**
- Verify PostgreSQL private DNS zone configured
- Check connection string in environment variables
- Verify PostgreSQL in delegated subnet

### Storage Access Denied

**Check file share mount:**
```bash
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --command "ls -la /opt/airflow/dags"
```

**Solution:**
- Verify storage private endpoints for blob and file
- Check managed identity has Storage Blob Data Contributor role
- Verify firewall allows `*.blob.core.windows.net`

## Testing Network Security

### From Container Shell

```bash
# Connect to scheduler
az containerapp exec \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --command bash

# Inside container:
# Should succeed (allowed by firewall)
curl https://pypi.org

# Should fail (blocked by firewall)
curl https://www.google.com
```

### Automated Security Tests

```bash
./scripts/test-etl-job.sh $RESOURCE_GROUP $ENV_NAME
```

### View Firewall Logs

```bash
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RESOURCE_GROUP \
  --workspace-name ${ENV_NAME}-logs \
  --query id -o tsv)

az monitor log-analytics query \
  --workspace $WORKSPACE_ID \
  --analytics-query "AzureDiagnostics | where Category == 'AzureFirewallApplicationRule' | where TimeGenerated > ago(1h) | project TimeGenerated, msg_s | take 20" \
  --output table
```

## After First Login

### 1. Change Admin Password

Navigate to: **Security → List Users → admin → Edit**

### 2. Upload DAGs

```bash
./scripts/upload-dags.sh $RESOURCE_GROUP $ENV_NAME ./dags
```

Wait 1-2 minutes, then refresh the UI.

### 3. Configure Connections

Navigate to: **Admin → Connections**

Add connections for:
- Databases (PostgreSQL, MySQL, etc.)
- Cloud services (Azure, AWS, GCP)
- APIs and webhooks

### 4. Set Variables

Navigate to: **Admin → Variables**

Add configuration variables your DAGs need.

### 5. Test DAG Execution

- Click on a DAG
- Click "Trigger DAG" button
- Monitor execution in Graph or Grid view
- Check task logs

## Monitoring & Validation

### Real-time Monitoring

```bash
# Follow scheduler logs
az containerapp logs show \
  --name airflow-poc-scheduler \
  --resource-group $RESOURCE_GROUP \
  --follow

# Watch container status
watch -n 5 "az containerapp list --resource-group $RESOURCE_GROUP --query '[].{Name:name, Status:properties.runningStatus}' --output table"
```

### Health Checks

```bash
# Check all components
for COMPONENT in scheduler webserver worker triggerer; do
  echo "=== $COMPONENT ==="
  az containerapp show \
    --name airflow-poc-$COMPONENT \
    --resource-group $RESOURCE_GROUP \
    --query "{Status:properties.runningStatus}" \
    --output json
done
```

### Performance Metrics

View in Azure Portal:
1. Go to Container Apps Environment
2. Select "Metrics"
3. View CPU, Memory, Request metrics

## Complete Validation Checklist

After deployment, verify:

- [ ] Run validation script: `./scripts/validate-deployment.sh`
- [ ] All Container Apps show "Running" status
- [ ] Webserver accessible via tunnel at http://localhost:8080
- [ ] Can login with admin/admin
- [ ] Scheduler processing (check logs)
- [ ] ACR public access disabled
- [ ] Storage public access disabled
- [ ] PostgreSQL public access disabled
- [ ] Private endpoints connected
- [ ] Firewall logs showing traffic
- [ ] Security tests passing: `./scripts/test-etl-job.sh`
- [ ] Upload test DAG: `./scripts/upload-dags.sh`
- [ ] DAG appears in UI (wait 1-2 minutes)
- [ ] Can trigger DAG run
- [ ] Worker scales up for tasks
- [ ] Task logs accessible
- [ ] Logs written to blob storage

## Success Indicators

Your deployment is working when:

1. ✅ Validation script passes all checks
2. ✅ Webserver UI loads at http://localhost:8080
3. ✅ Can login successfully
4. ✅ DAGs appear in UI after upload
5. ✅ Can trigger and execute DAG runs
6. ✅ Worker scales up when tasks queued
7. ✅ Task logs visible in UI
8. ✅ Security tests pass
9. ✅ No public access to any service
10. ✅ All traffic flows through Azure Firewall

## API Access

Access Airflow REST API through the tunnel:

```bash
# Start tunnel in background
./scripts/access-webserver.sh $RESOURCE_GROUP $ENV_NAME &

# Wait for tunnel to establish
sleep 5

# List DAGs
curl -u admin:admin http://localhost:8080/api/v1/dags

# Trigger DAG
curl -u admin:admin -X POST http://localhost:8080/api/v1/dags/test_dag/dagRuns \
  -H "Content-Type: application/json" \
  -d '{}'

# Get DAG runs
curl -u admin:admin http://localhost:8080/api/v1/dags/test_dag/dagRuns
```

## Security Best Practices

### 1. Change Default Credentials

Immediately after first login:
- Change admin password
- Create individual user accounts
- Disable default admin if using SSO

### 2. Configure Authentication

For production, enable Azure AD OAuth:
- Edit `docker/airflow/config/webserver_config.py`
- Configure Azure AD app registration
- Redeploy webserver

### 3. Monitor Access

- Review webserver logs regularly
- Set up alerts for failed logins
- Monitor API usage

### 4. Network Security

- Keep firewall rules minimal
- Review firewall logs weekly
- Run security tests after changes

## Next Steps

1. **Validate**: `./scripts/validate-deployment.sh $RESOURCE_GROUP $ENV_NAME`
2. **Access**: `./scripts/access-webserver.sh $RESOURCE_GROUP $ENV_NAME`
3. **Upload DAGs**: `./scripts/upload-dags.sh $RESOURCE_GROUP $ENV_NAME ./dags`
4. **Test Security**: `./scripts/test-etl-job.sh $RESOURCE_GROUP $ENV_NAME`
5. **Change Password**: In Airflow UI
6. **Configure Connections**: Add your data sources
7. **Deploy Production DAGs**: Upload your actual workflows

## Support & Documentation

- **Validation Issues**: See [PRIVATE_NETWORK_SETUP.md](PRIVATE_NETWORK_SETUP.md)
- **Deployment Checklist**: See [SECURE_DEPLOYMENT_CHECKLIST.md](SECURE_DEPLOYMENT_CHECKLIST.md)
- **Security Details**: See [SECURITY_ENHANCEMENTS.md](SECURITY_ENHANCEMENTS.md)
- **Architecture**: See [ARCHITECTURE_DIAGRAM.md](ARCHITECTURE_DIAGRAM.md)
- **Airflow Docs**: https://airflow.apache.org/docs/

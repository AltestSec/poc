# Accessing Airflow Web UI

## Quick Access

### Step 1: Apply Terraform Changes

The webserver is now configured for external access. Apply the changes:

```bash
cd terraform
terraform apply -var-file=environments/poc/terraform.tfvars
```

### Step 2: Get the Webserver URL

```bash
# Option 1: Via Terraform output
terraform output -raw webserver_fqdn

# Option 2: Via management script
./scripts/manage-airflow.sh url

# Option 3: Via Azure CLI
az containerapp show \
  --name airflow-poc-webserver \
  --resource-group merzlikin-tf-state-rg \
  --query "properties.configuration.ingress.fqdn" -o tsv
```

### Step 3: Access the Web UI

Open your browser and navigate to:

```
https://<webserver-fqdn>
```

Example:
```
https://airflow-poc-webserver.redsky-99b402df.westeurope.azurecontainerapps.io
```

### Step 4: Login

**Default credentials:**
- Username: `admin`
- Password: `admin`

⚠️ **IMPORTANT:** Change the password immediately after first login!

## What You'll See

After logging in, you'll see the Airflow UI with:

1. **DAGs page** (main page)
   - List of all DAGs (will be empty initially)
   - DAG status, last run, schedule
   - Pause/unpause toggles

2. **Top navigation:**
   - DAGs - Main DAG list
   - Datasets - Data dependencies
   - Security - User management
   - Browse - Task instances, jobs, logs
   - Admin - Connections, variables, configuration
   - Docs - Airflow documentation

3. **Empty state:**
   - If no DAGs uploaded yet, you'll see "No DAGs found"
   - This is normal for a fresh installation

## Troubleshooting

### Cannot access the URL

**Check webserver status:**
```bash
az containerapp show \
  --name airflow-poc-webserver \
  --resource-group merzlikin-tf-state-rg \
  --query "{Status:properties.runningStatus, FQDN:properties.configuration.ingress.fqdn}" \
  -o table
```

**Check webserver logs:**
```bash
./scripts/manage-airflow.sh logs webserver
```

### Login fails

**Check if database is initialized:**
```bash
./scripts/manage-airflow.sh logs scheduler | grep -i "database\|admin"
```

**Reset admin password (if needed):**
The scheduler command automatically creates the admin user. If it doesn't exist, check scheduler logs for errors.

### Page loads but shows errors

**Check scheduler is running:**
```bash
./scripts/manage-airflow.sh status
```

**Check database connection:**
```bash
./scripts/manage-airflow.sh db-check
```

### SSL/Certificate warnings

Azure Container Apps provides automatic HTTPS with valid certificates. If you see warnings:
- Clear browser cache
- Try incognito/private mode
- Verify the URL is correct

## Next Steps After Login

### 1. Change Admin Password

Go to: Security → List Users → Click on admin → Edit

### 2. Upload DAGs

```bash
# Create a simple test DAG
cat > test_dag.py << 'EOF'
from airflow import DAG
from airflow.operators.bash import BashOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'test_dag',
    default_args=default_args,
    description='A simple test DAG',
    schedule_interval=timedelta(days=1),
    catchup=False,
)

t1 = BashOperator(
    task_id='print_date',
    bash_command='date',
    dag=dag,
)

t2 = BashOperator(
    task_id='print_hello',
    bash_command='echo "Hello from Airflow!"',
    dag=dag,
)

t1 >> t2
EOF

# Upload to storage
./scripts/manage-airflow.sh upload-dags .
```

Wait 30-60 seconds for Airflow to detect the new DAG, then refresh the UI.

### 3. Configure Connections

Go to: Admin → Connections

Add connections for:
- Databases
- Cloud services (Azure, AWS, GCP)
- APIs
- Other services

### 4. Set Variables

Go to: Admin → Variables

Add configuration variables your DAGs need.

### 5. Monitor

- View DAG runs
- Check task logs
- Monitor worker status
- Set up alerts

## Security Recommendations

### 1. Change Default Password Immediately

```bash
# Via Airflow UI: Security → List Users → admin → Edit
```

### 2. Enable Authentication (Optional)

For production, consider:
- Azure AD OAuth (configured in `webserver_config.py`)
- LDAP authentication
- Multi-factor authentication

### 3. Restrict Access (Optional)

For production, consider:
- Azure Front Door with WAF
- Private endpoints
- IP allowlisting
- VNet integration

### 4. Use Secrets Management

Store sensitive data in:
- Azure Key Vault (already configured)
- Airflow Connections (encrypted in database)
- Airflow Variables (encrypted in database)

## API Access

You can also access Airflow via REST API:

```bash
WEBSERVER_URL="https://$(terraform output -raw webserver_fqdn)"

# List DAGs
curl -u admin:admin "$WEBSERVER_URL/api/v1/dags"

# Trigger DAG
curl -u admin:admin -X POST "$WEBSERVER_URL/api/v1/dags/test_dag/dagRuns" \
  -H "Content-Type: application/json" -d '{}'
```

## Useful Links

- Airflow Documentation: https://airflow.apache.org/docs/
- REST API Reference: https://airflow.apache.org/docs/apache-airflow/stable/stable-rest-api-ref.html
- Azure Container Apps Docs: https://learn.microsoft.com/en-us/azure/container-apps/

## Support

If you encounter issues:
1. Check logs: `./scripts/manage-airflow.sh logs webserver`
2. Check status: `./scripts/manage-airflow.sh health`
3. Review scheduler logs: `./scripts/manage-airflow.sh logs scheduler`
4. Check database initialization: See `DATABASE_INIT.md`

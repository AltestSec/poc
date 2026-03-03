# Webserver Crashing Fix

## Problem

The Airflow webserver was crashing with SIGTERM (signal 15) and showing 404 errors. Analysis of system logs revealed:

```
Startup probe failed: connection refused (20+ times)
Container 'webserver' was terminated with exit code '0'
Persistent Failure to start container
```

## Root Cause

The `startup_probe` configuration was too aggressive:
- `failure_count_threshold = 3` (only 3 failures allowed)
- `interval_seconds = 10` (check every 10 seconds)
- Total time before kill: 30 seconds (3 × 10)

Airflow webserver takes 1-2 minutes to fully start and open port 8080. The startup probe was killing the container before it could finish initialization.

## Solution

Modified `terraform/modules/container_apps/main.tf` webserver configuration:

### Before
```hcl
startup_probe {
  transport        = "HTTP"
  port             = 8080
  path             = "/health"
  interval_seconds = 10
  timeout          = 5
  failure_count_threshold = 3  # Only 30 seconds!
}

readiness_probe {
  failure_count_threshold = 3  # Only 30 seconds
}

liveness_probe {
  failure_count_threshold = 3  # Only 90 seconds
}
```

### After
```hcl
# Removed startup_probe entirely

readiness_probe {
  transport             = "HTTP"
  port                  = 8080
  path                  = "/health"
  interval_seconds      = 10
  timeout               = 5
  success_count_threshold = 1
  failure_count_threshold = 30  # 5 minutes (30 × 10s)
}

liveness_probe {
  transport             = "HTTP"
  port                  = 8080
  path                  = "/health"
  interval_seconds      = 30
  timeout               = 5
  failure_count_threshold = 10  # 5 minutes (10 × 30s)
}
```

## Changes

1. **Removed startup_probe**: Not needed, readiness probe handles startup detection
2. **Increased readiness_probe threshold**: 30 failures = 5 minutes for startup
3. **Increased liveness_probe threshold**: 10 failures = 5 minutes before restart

This gives the webserver adequate time to:
- Initialize Airflow components
- Connect to PostgreSQL and Redis
- Start Gunicorn workers
- Open port 8080 and respond to health checks

## Apply the Fix

Run the helper script:

```bash
cd airflow-aca-tf
./scripts/fix-webserver-probes.sh
```

Or manually:

```bash
cd airflow-aca-tf/terraform

# Set required variables
export TF_VAR_postgres_admin_password="YourSecurePassword"
export TF_VAR_airflow_fernet_key="$(python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')"
export TF_VAR_airflow_webserver_secret_key="$(openssl rand -base64 32)"
export TF_VAR_owner="your.email@example.com"
export TF_VAR_duedate="2026-03-10"

# Apply changes
terraform plan -var-file=environments/poc/terraform.tfvars -out=tfplan
terraform apply tfplan
```

## Verification

After applying, verify the webserver stays running:

```bash
# Check webserver status
az containerapp show \
  --name airflow-poc-webserver \
  --resource-group merzlikin-tf-state-rg \
  --query "properties.runningStatus" -o tsv

# Watch logs (should NOT see SIGTERM anymore)
az containerapp logs show \
  --name airflow-poc-webserver \
  --resource-group merzlikin-tf-state-rg \
  --follow

# Check system logs (should NOT see startup probe failures)
az containerapp logs show \
  --name airflow-poc-webserver \
  --resource-group merzlikin-tf-state-rg \
  --type system \
  --tail 50

# Access the web UI
az containerapp show \
  --name airflow-poc-webserver \
  --resource-group merzlikin-tf-state-rg \
  --query "properties.configuration.ingress.fqdn" -o tsv
```

Expected results:
- Webserver status: `Running`
- Logs show: `Running the Gunicorn Server with: Workers: 4 sync`
- No SIGTERM signals
- No startup probe failures
- FQDN responds with Airflow login page (not 404)

## Timeline

The webserver should:
- Start at T+0s
- Begin initialization (database connection, etc.)
- Open port 8080 at T+60-120s
- Respond to health checks
- Become ready and receive traffic

With the new configuration, Container Apps will:
- Wait up to 5 minutes for readiness (30 failures × 10s)
- Only restart if unhealthy for 5 minutes (10 failures × 30s)
